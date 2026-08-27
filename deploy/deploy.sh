#!/usr/bin/env bash
# Deploy / update mock-server on an Ubuntu/Debian VM behind nginx.
#
# Designed to be REPEATABLE (idempotent):
#   - Safe to re-run for upgrades
#   - Only manages mock-server-owned files (does not wipe other nginx sites)
#   - Preserves /opt/mock-server/.env.production across syncs
#   - Does not force-enable UFW or remove unrelated site configs
#   - Never writes into /etc/letsencrypt/live (uses /etc/nginx/ssl/mock-server)
#   - Certbot runs only when a LE cert is missing (webroot, not --nginx rewriter)
#   - --no-tls: HTTP-only verify mode (no certs / certbot) before enabling TLS
#
# Usage (as root):
#   ./deploy/deploy.sh --domain api.example.com [--email you@example.com] [options]
#   ./deploy/deploy.sh --domain api.example.com --no-tls   # verify without certificates
#
set -euo pipefail

DOMAIN=""
EMAIL=""
SKIP_CERTBOT=0
SKIP_UFW=1
MQTT_CLEARTEXT=0
REMOVE_DEFAULT_SITE=0
FORCE_CERTBOT=0
NO_TLS=0
APP_USER=mockserver
APP_DIR=/opt/mock-server
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_NAME="mock-server"
STREAM_NAME="mock-server-mqtt"
SSL_DIR="/etc/nginx/ssl/mock-server"
BACKUP_DIR="/var/backups/mock-server"

usage() {
  cat <<EOF
Usage: sudo $0 --domain <hostname> [options]

Required:
  --domain HOST              Public DNS name for this mock-server vhost

Options:
  --email EMAIL              Let's Encrypt email (recommended)
  --no-tls                   HTTP-only verify mode: no certificates, no certbot,
                             no HTTPS. Use to test app/nginx before TLS setup.
                             Serves :80 + cleartext gRPC :50051 + MQTT :1883.
  --skip-certbot             Never call certbot (still may use/create self-signed)
  --force-certbot            Request/renew cert even if one exists
  --enable-ufw               Add UFW allow rules (only if UFW already active;
                             never runs 'ufw --force enable')
  --mqtt-cleartext           Also proxy public TCP 1883 → local MQTT
                             (implied by --no-tls)
  --remove-default-site      Remove sites-enabled/default only (stock nginx)
  -h, --help

Repeatable: re-run after git pull to rebuild/restart app and refresh our nginx
files only. Other nginx server blocks are left alone.

Upgrade from --no-tls to TLS later:
  sudo $0 --domain HOST --email you@example.com
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --no-tls) NO_TLS=1; SKIP_CERTBOT=1; MQTT_CLEARTEXT=1; shift ;;
    --skip-certbot) SKIP_CERTBOT=1; shift ;;
    --force-certbot) FORCE_CERTBOT=1; shift ;;
    --enable-ufw) SKIP_UFW=0; shift ;;
    --mqtt-cleartext) MQTT_CLEARTEXT=1; shift ;;
    --remove-default-site) REMOVE_DEFAULT_SITE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0 --domain your.domain.com"
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "--domain is required"
  usage
  exit 1
fi

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

backup_file() {
  local src="$1"
  [[ -f "$src" ]] || return 0
  mkdir -p "$BACKUP_DIR"
  local base dest
  base="$(basename "$src")"
  dest="$BACKUP_DIR/${base}.$(date +%Y%m%d%H%M%S).bak"
  cp -a "$src" "$dest"
  log "Backed up $src → $dest"
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt "( sport = :$port )" 2>/dev/null | grep -q ":$port"
  else
    return 1
  fi
}

render_nginx() {
  local src="$1"
  local dest="$2"
  sed -e "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
      -e "s|SSL_CERT_DIR_PLACEHOLDER|$SSL_DIR|g" \
      "$src" > "$dest"
}

ensure_nginx_http_snippet() {
  local marker="snippets/websocket-map.conf"
  if grep -qF "$marker" /etc/nginx/nginx.conf; then
    return 0
  fi
  if grep -qE '^\s*http\s*\{' /etc/nginx/nginx.conf; then
    # Insert once after first http { — do not touch other includes
    sed -i "/^\s*http\s*{/a\\    include /etc/nginx/snippets/websocket-map.conf;" /etc/nginx/nginx.conf
    log "Added websocket map include to nginx.conf http{} (once)"
  else
    warn "Could not find http{} in nginx.conf — add manually: include /etc/nginx/snippets/websocket-map.conf;"
  fi
}

# True when Ubuntu/Debian (or similar) already loads stream via modules-enabled.
stream_loaded_via_distro() {
  if [[ -f /etc/nginx/modules-enabled/50-mod-stream.conf ]]; then
    return 0
  fi
  if [[ -d /etc/nginx/modules-enabled ]] && ls /etc/nginx/modules-enabled/*stream* >/dev/null 2>&1; then
    return 0
  fi
  # Packaged nginx on Debian/Ubuntu almost always includes modules-enabled
  if [[ -f /etc/debian_version ]] && [[ -d /etc/nginx/modules-enabled ]]; then
    return 0
  fi
  return 1
}

# Strip ANY load_module …ngx_stream_module from main nginx.conf (leftover from older deploys).
strip_duplicate_stream_load_module() {
  if ! grep -qE 'load_module.*ngx_stream_module' /etc/nginx/nginx.conf 2>/dev/null; then
    return 0
  fi
  backup_file /etc/nginx/nginx.conf
  # Broad match: any indentation, absolute or relative module path
  sed -i -E '/load_module.*ngx_stream_module/d' /etc/nginx/nginx.conf
  log "Removed load_module ngx_stream_module from /etc/nginx/nginx.conf (already loaded via modules-enabled)"
}

ensure_nginx_stream() {
  # Ubuntu/Debian: modules-enabled/50-mod-stream.conf already loads the module.
  # A second load_module in nginx.conf → "module is already loaded".
  if stream_loaded_via_distro; then
    strip_duplicate_stream_load_module
    log "ngx_stream_module provided by distro modules-enabled — not adding load_module"
  elif ! grep -qE 'load_module.*ngx_stream_module' /etc/nginx/nginx.conf 2>/dev/null; then
    local stream_mod
    stream_mod="$(ls /usr/lib/nginx/modules/ngx_stream_module.so 2>/dev/null || true)"
    if [[ -n "$stream_mod" ]]; then
      backup_file /etc/nginx/nginx.conf
      sed -i "1i load_module $stream_mod;" /etc/nginx/nginx.conf
      log "Enabled ngx_stream_module via load_module"
    else
      warn "ngx_stream_module.so not found — MQTT stream proxy may fail (install libnginx-mod-stream if needed)"
    fi
  fi

  if grep -qF 'streams-enabled' /etc/nginx/nginx.conf; then
    return 0
  fi

  backup_file /etc/nginx/nginx.conf
  if grep -qE '^\s*stream\s*\{' /etc/nginx/nginx.conf; then
    sed -i "/^\s*stream\s*{/a\\    include /etc/nginx/streams-enabled/*.conf;" /etc/nginx/nginx.conf
  else
    cat >> /etc/nginx/nginx.conf <<'EOF'

# Added by mock-server deploy (idempotent marker: streams-enabled)
stream {
    include /etc/nginx/streams-enabled/*.conf;
}
EOF
  fi
  log "Ensured stream { include streams-enabled } in nginx.conf"
}

ensure_ssl_material() {
  mkdir -p "$SSL_DIR"
  local le_dir="/etc/letsencrypt/live/$DOMAIN"
  if [[ -f "$le_dir/fullchain.pem" && -f "$le_dir/privkey.pem" ]]; then
    # Prefer live LE certs via relative-safe copies/symlinks in our SSL_DIR only
    ln -sfn "$le_dir/fullchain.pem" "$SSL_DIR/fullchain.pem"
    ln -sfn "$le_dir/privkey.pem" "$SSL_DIR/privkey.pem"
    log "Using Let's Encrypt certs for $DOMAIN → $SSL_DIR"
    return 0
  fi

  if [[ -f "$SSL_DIR/fullchain.pem" && -f "$SSL_DIR/privkey.pem" ]]; then
    log "Keeping existing TLS material in $SSL_DIR"
    return 0
  fi

  log "Creating self-signed TLS material in $SSL_DIR (not touching /etc/letsencrypt)"
  openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout "$SSL_DIR/privkey.pem" \
    -out "$SSL_DIR/fullchain.pem" \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN" 2>/dev/null \
    || openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
      -keyout "$SSL_DIR/privkey.pem" \
      -out "$SSL_DIR/fullchain.pem" \
      -subj "/CN=$DOMAIN"
  chmod 640 "$SSL_DIR/privkey.pem"
}

log "Domain: $DOMAIN"
log "Repo:   $REPO_DIR"
if [[ "$NO_TLS" -eq 1 ]]; then
  log "Mode:   HTTP-only verify (--no-tls; no certificates)"
else
  log "Mode:   repeatable update (owned files only)"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates gnupg nginx rsync
if [[ "$NO_TLS" -eq 0 ]]; then
  apt-get install -y openssl
fi

# Node.js 22 (graphql@17 requires ^22+)
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]]; then
  log "Installing Node.js 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

if [[ "$SKIP_CERTBOT" -eq 0 ]]; then
  apt-get install -y certbot
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

log "Syncing application → $APP_DIR (preserving .env.production)"
mkdir -p "$APP_DIR"
# Critical: do NOT delete .env.production / local certs on re-run
rsync -a --delete \
  --exclude node_modules \
  --exclude dist \
  --exclude .git \
  --exclude certs \
  --exclude .env.production \
  --exclude .env \
  "$REPO_DIR/" "$APP_DIR/"

cd "$APP_DIR"
npm ci
npm run build
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod +x "$APP_DIR/deploy/deploy.sh" "$APP_DIR/deploy/validate.sh" 2>/dev/null || true
# Keep env readable only by service user
if [[ -f "$APP_DIR/.env.production" ]]; then
  chown "$APP_USER:$APP_USER" "$APP_DIR/.env.production"
  chmod 640 "$APP_DIR/.env.production"
fi

ENV_FILE="$APP_DIR/.env.production"
SCHEME="https"
if [[ "$NO_TLS" -eq 1 ]]; then
  SCHEME="http"
fi
if [[ ! -f "$ENV_FILE" ]]; then
  sed -e "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
      -e "s|https://|${SCHEME}://|g" \
      "$APP_DIR/deploy/env.production.example" > "$ENV_FILE"
  chown "$APP_USER:$APP_USER" "$ENV_FILE"
  chmod 640 "$ENV_FILE"
  log "Created $ENV_FILE (PUBLIC_URL ${SCHEME}://$DOMAIN)"
else
  log "Preserved existing $ENV_FILE"
  if [[ "$NO_TLS" -eq 1 ]]; then
    # Align public URL for verify mode without wiping other secrets
    tmp="$(mktemp)"
    sed -e "s|^PUBLIC_URL=.*|PUBLIC_URL=http://$DOMAIN|" \
        -e "s|^CORS_ORIGINS=.*|CORS_ORIGINS=http://$DOMAIN|" \
        "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    chown "$APP_USER:$APP_USER" "$ENV_FILE"
    chmod 640 "$ENV_FILE"
    log "Updated PUBLIC_URL/CORS for HTTP-only verify mode"
  elif grep -qE '^PUBLIC_URL=http://' "$ENV_FILE" 2>/dev/null; then
    tmp="$(mktemp)"
    sed -e "s|^PUBLIC_URL=.*|PUBLIC_URL=https://$DOMAIN|" \
        -e "s|^CORS_ORIGINS=.*|CORS_ORIGINS=https://$DOMAIN|" \
        "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    chown "$APP_USER:$APP_USER" "$ENV_FILE"
    chmod 640 "$ENV_FILE"
    log "Updated PUBLIC_URL/CORS to HTTPS (left --no-tls)"
  fi
fi

install -m 644 "$APP_DIR/deploy/systemd/mock-server.service" /etc/systemd/system/mock-server.service
systemctl daemon-reload
systemctl enable mock-server
systemctl restart mock-server

# --- nginx: only our site + stream files ---
mkdir -p /etc/nginx/snippets /etc/nginx/streams-enabled /etc/nginx/sites-available /etc/nginx/sites-enabled \
  /var/www/certbot "$BACKUP_DIR"
install -m 644 "$APP_DIR/deploy/nginx/websocket-map.conf" /etc/nginx/snippets/websocket-map.conf

ensure_nginx_http_snippet
ensure_nginx_stream
if [[ "$NO_TLS" -eq 0 ]]; then
  ensure_ssl_material
else
  log "Skipping TLS material (--no-tls)"
fi

SITE_AVAIL="/etc/nginx/sites-available/${SITE_NAME}.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}.conf"
STREAM_UPSTREAM="/etc/nginx/streams-enabled/${STREAM_NAME}-upstream.conf"
STREAM_CONF="/etc/nginx/streams-enabled/${STREAM_NAME}.conf"
STREAM_CLEAR="/etc/nginx/streams-enabled/${STREAM_NAME}-cleartext.conf"

backup_file "$SITE_AVAIL"
backup_file "$STREAM_CONF"
backup_file "$STREAM_UPSTREAM"

if [[ "$NO_TLS" -eq 1 ]]; then
  render_nginx "$APP_DIR/deploy/nginx/mock-server-http.conf" "$SITE_AVAIL"
  log "Installed HTTP-only nginx site (no TLS listeners)"
else
  render_nginx "$APP_DIR/deploy/nginx/mock-server.conf" "$SITE_AVAIL"
fi
ln -sfn "$SITE_AVAIL" "$SITE_ENABLED"
log "Installed nginx site $SITE_ENABLED (other sites untouched)"

if [[ "$REMOVE_DEFAULT_SITE" -eq 1 ]]; then
  if [[ -L /etc/nginx/sites-enabled/default || -f /etc/nginx/sites-enabled/default ]]; then
    backup_file /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-enabled/default
    log "Removed sites-enabled/default (--remove-default-site)"
  fi
else
  if [[ -e /etc/nginx/sites-enabled/default ]]; then
    warn "sites-enabled/default still present (left alone). Use --remove-default-site if needed."
  fi
fi

# Shared upstream required whenever any MQTT stream server is enabled
install -m 644 "$APP_DIR/deploy/nginx/mqtt-stream-upstream.conf" "$STREAM_UPSTREAM"

if [[ "$NO_TLS" -eq 1 ]]; then
  # No TLS MQTT stream — cleartext only for verify
  rm -f "$STREAM_CONF"
  install -m 644 "$APP_DIR/deploy/nginx/mqtt-stream-cleartext.conf" "$STREAM_CLEAR"
  log "MQTT cleartext :1883 enabled (--no-tls); TLS :8883 not configured"
else
  render_nginx "$APP_DIR/deploy/nginx/mqtt-stream.conf" "$STREAM_CONF"
  if [[ "$MQTT_CLEARTEXT" -eq 1 ]]; then
    install -m 644 "$APP_DIR/deploy/nginx/mqtt-stream-cleartext.conf" "$STREAM_CLEAR"
    log "Enabled MQTT cleartext stream on :1883"
  else
    rm -f "$STREAM_CLEAR"
    log "MQTT cleartext :1883 disabled (use --mqtt-cleartext to enable)"
  fi
fi

# Soft conflict checks (do not abort — nginx -t is authoritative)
PORTS_CHECK=(80 50051)
if [[ "$NO_TLS" -eq 0 ]]; then
  PORTS_CHECK+=(443 8883)
fi
if [[ "$MQTT_CLEARTEXT" -eq 1 || "$NO_TLS" -eq 1 ]]; then
  PORTS_CHECK+=(1883)
fi
for p in "${PORTS_CHECK[@]}"; do
  if port_in_use "$p"; then
    warn "Port $p already has listeners — ensure no clash with our server_name/$SITE_NAME blocks"
  fi
done

# Always scrub leftover duplicate stream load_module before nginx -t (fixes prior failed deploys)
if stream_loaded_via_distro; then
  strip_duplicate_stream_load_module
fi

if ! nginx -t; then
  echo "ERROR: nginx -t failed."
  echo "  Tip: if you see 'ngx_stream_module is already loaded', remove any"
  echo "  load_module …ngx_stream_module line from /etc/nginx/nginx.conf then re-run."
  echo "  Checking for leftover load_module lines:"
  grep -n 'load_module' /etc/nginx/nginx.conf || true
  LATEST_BAK="$(ls -1t "$BACKUP_DIR/${SITE_NAME}.conf".*.bak 2>/dev/null | head -1 || true)"
  if [[ -n "$LATEST_BAK" ]]; then
    cp -a "$LATEST_BAK" "$SITE_AVAIL"
    echo "Restored $SITE_AVAIL from $LATEST_BAK"
  fi
  # Attempt one more scrub + test (site restore alone cannot fix nginx.conf)
  if stream_loaded_via_distro; then
    strip_duplicate_stream_load_module
  fi
  if nginx -t; then
    systemctl reload nginx
    log "nginx -t OK after scrubbing duplicate stream load_module"
  else
    echo "ERROR: nginx -t still failing — fix /etc/nginx/nginx.conf manually"
    exit 1
  fi
else
  systemctl reload nginx
fi

# UFW: never force-enable; only add rules if already active and user asked
if [[ "$SKIP_UFW" -eq 0 ]] && command -v ufw >/dev/null 2>&1; then
  if ufw status 2>/dev/null | grep -qi 'Status: active'; then
    ufw allow OpenSSH || true
    ufw allow 80/tcp || true
    ufw allow 50051/tcp || true
    if [[ "$NO_TLS" -eq 0 ]]; then
      ufw allow 443/tcp || true
      ufw allow 8883/tcp || true
    fi
    if [[ "$MQTT_CLEARTEXT" -eq 1 || "$NO_TLS" -eq 1 ]]; then
      ufw allow 1883/tcp || true
    fi
    log "UFW allow rules ensured (firewall already active)"
  else
    warn "UFW is inactive — not enabling it. Activate manually if desired, then re-run with --enable-ufw"
  fi
fi

# Certbot: skipped entirely in --no-tls; otherwise webroot only
LE_LIVE="/etc/letsencrypt/live/$DOMAIN"
if [[ "$NO_TLS" -eq 1 ]]; then
  log "Skipping certbot (--no-tls verify mode)"
elif [[ "$SKIP_CERTBOT" -eq 0 ]]; then
  NEED_CERT=0
  if [[ "$FORCE_CERTBOT" -eq 1 ]]; then
    NEED_CERT=1
  elif [[ ! -f "$LE_LIVE/fullchain.pem" ]]; then
    NEED_CERT=1
  else
    log "Let's Encrypt cert already present for $DOMAIN — skipping certbot (use --force-certbot to renew/reissue)"
  fi

  if [[ "$NEED_CERT" -eq 1 ]]; then
    log "Requesting certificate via webroot (does not rewrite other nginx sites)"
    mkdir -p /var/www/certbot
    CERTBOT_ARGS=(certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos)
    if [[ -n "$EMAIL" ]]; then
      CERTBOT_ARGS+=(--email "$EMAIL")
    else
      CERTBOT_ARGS+=(--register-unsafely-without-email)
    fi
    if certbot "${CERTBOT_ARGS[@]}"; then
      ensure_ssl_material
      nginx -t && systemctl reload nginx
      log "Certificate installed and nginx reloaded"
    else
      warn "certbot failed — continuing with certs in $SSL_DIR"
      warn "Fix DNS for $DOMAIN, then: sudo $0 --domain $DOMAIN --force-certbot"
    fi
  fi
fi

systemctl --no-pager --full status mock-server || true

log "Running local smoke validation (includes HTTP Streams)"
if [[ -f "$APP_DIR/deploy/validate.sh" ]]; then
  bash "$APP_DIR/deploy/validate.sh" --base "http://127.0.0.1:3000" || \
    warn "validate.sh reported failures — check journalctl -u mock-server"
else
  warn "deploy/validate.sh missing under $APP_DIR — skip smoke checks"
fi

if [[ "$NO_TLS" -eq 1 ]]; then
  cat <<EOF

============================================================
 Deploy complete — HTTP-only verify mode (--no-tls)

 No certificates were created. Other nginx sites were NOT removed.

 Owned by this script only:
   App:     $APP_DIR  (systemd: mock-server)
   Nginx:   $SITE_ENABLED  (HTTP site)
   Stream:  $STREAM_CLEAR  (MQTT cleartext)
   Backups: $BACKUP_DIR

 Verify via gateway:
   http://$DOMAIN/                 (:80)
   http://$DOMAIN/http-stream/demo
   ws://$DOMAIN/ws/demo
   gRPC cleartext  $DOMAIN:50051
   MQTT cleartext  $DOMAIN:1883

   ./deploy/validate.sh --base http://$DOMAIN
   # or on the VM:
   ./deploy/validate.sh --base http://127.0.0.1

 When ready for TLS / certificates, re-run WITHOUT --no-tls:
   sudo ./deploy/deploy.sh --domain $DOMAIN --email you@example.com
============================================================
EOF
else
  cat <<EOF

============================================================
 Deploy complete (repeatable)

 Owned by this script only:
   App:     $APP_DIR  (systemd: mock-server)
   Nginx:   $SITE_ENABLED
   Stream:  $STREAM_CONF
   TLS dir: $SSL_DIR
   Backups: $BACKUP_DIR

 Other nginx sites / stream configs were NOT removed.

 Public:
   https://$DOMAIN/              (:443)
   https://$DOMAIN/http-stream/demo
   wss://$DOMAIN/ws/demo
   gRPC TLS  $DOMAIN:50051
   MQTT TLS  $DOMAIN:8883

 Smoke (from laptop after DNS/TLS):
   ./deploy/validate.sh --base https://$DOMAIN
   # self-signed: add --insecure

 Re-run anytime after updates:
   sudo ./deploy/deploy.sh --domain $DOMAIN

 Optional flags:
   --no-tls             verify without certificates
   --mqtt-cleartext     expose :1883
   --remove-default-site
   --enable-ufw         only if ufw already active
   --force-certbot
============================================================
EOF
fi
