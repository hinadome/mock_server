#!/usr/bin/env bash
# Container deployment for mock-server (Docker Compose + nginx gateway).
#
# SEPARATE from VM deploy (deploy/deploy.sh). This script:
#   - Never edits the host /etc/nginx or sites-enabled
#   - Runs nginx only inside the Compose "gateway" service
#   - Reuses existing certs in deploy/container/certs/ (does not override)
#   - Is idempotent: safe to re-run for upgrades
#
# Usage:
#   ./deploy/container/deploy.sh --domain api.example.com
#   ./deploy/container/deploy.sh --domain api.example.com --no-tls
#   ./deploy/container/deploy.sh --domain api.example.com --force-certs
#   ./deploy/container/deploy.sh --domain api.example.com --mqtt-cleartext
#   ./deploy/container/deploy.sh --down
#
set -euo pipefail

DOMAIN=""
ENV_FILE=""
FORCE_CERTS=0
MQTT_CLEARTEXT=0
SKIP_VALIDATE=0
DO_DOWN=0
NO_BUILD=0
NO_TLS=0
SELF_SIGNED=1
USE_CERTBOT=0
EMAIL=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"
LE_DIR="$SCRIPT_DIR/letsencrypt"
CERTBOT_WWW="$SCRIPT_DIR/certbot-www"
RUNTIME_CONF="$SCRIPT_DIR/nginx/runtime/conf.d"
RUNTIME_STREAM="$SCRIPT_DIR/nginx/runtime/stream.d"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
OVERRIDE_FILE="$SCRIPT_DIR/docker-compose.override.yml"
DEFAULT_ENV="$SCRIPT_DIR/.env.production"

usage() {
  cat <<EOF
Usage: $0 --domain <hostname> [options]

Required (except --down):
  --domain HOST              Public DNS / Host header for PUBLIC_URL

TLS certificate options:
  --self-signed              openssl self-signed in deploy/container/certs/ (default)
  --force-self-signed        Regenerate self-signed (alias: --force-certs)
  --certbot                  Let's Encrypt via certbot (webroot); needs public DNS → :80
  --email EMAIL              Let's Encrypt email (recommended with --certbot)
  --force-certs              Alias for --force-self-signed

Other:
  --no-tls                   HTTP-only verify (no certificates / HTTPS)
  --env FILE                 Env file (default: deploy/container/.env.production)
  --mqtt-cleartext           Also publish host TCP 1883 → MQTT
  --skip-validate            Skip post-up smoke checks
  --no-build                 docker compose up without --build
  --down                     Stop and remove this Compose stack only
  -h, --help

Examples:
  $0 --domain api.example.com --self-signed
  $0 --domain api.example.com --certbot --email you@example.com
  $0 --domain api.example.com --no-tls
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --env) ENV_FILE="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --no-tls) NO_TLS=1; MQTT_CLEARTEXT=1; shift ;;
    --self-signed) SELF_SIGNED=1; USE_CERTBOT=0; shift ;;
    --force-self-signed|--force-certs) SELF_SIGNED=1; USE_CERTBOT=0; FORCE_CERTS=1; shift ;;
    --certbot) USE_CERTBOT=1; SELF_SIGNED=0; shift ;;
    --mqtt-cleartext) MQTT_CLEARTEXT=1; shift ;;
    --skip-validate) SKIP_VALIDATE=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --down) DO_DOWN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

if [[ "$DO_DOWN" -eq 1 ]]; then
  require_cmd docker
  log "Stopping Compose stack (project mock-server only)"
  cd "$SCRIPT_DIR"
  if [[ -f "$OVERRIDE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" down --remove-orphans
  else
    compose down --remove-orphans
  fi
  log "Stack stopped. Host nginx (if any) was not modified."
  exit 0
fi

if [[ -z "$DOMAIN" ]]; then
  echo "--domain is required"
  usage
  exit 1
fi

if [[ "$NO_TLS" -eq 1 && ( "$USE_CERTBOT" -eq 1 || "$FORCE_CERTS" -eq 1 ) ]]; then
  echo "ERROR: --no-tls cannot be combined with --certbot / --force-self-signed" >&2
  exit 1
fi
if [[ "$USE_CERTBOT" -eq 1 && "$FORCE_CERTS" -eq 1 ]]; then
  echo "ERROR: use either --certbot or --force-self-signed, not both" >&2
  exit 1
fi

require_cmd docker
if [[ "$NO_TLS" -eq 0 ]]; then
  require_cmd openssl
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin is required" >&2
  exit 1
fi

ENV_FILE="${ENV_FILE:-$DEFAULT_ENV}"
SCHEME="https"
if [[ "$NO_TLS" -eq 1 ]]; then
  SCHEME="http"
  log "Mode: HTTP-only verify (--no-tls; no certificates)"
elif [[ "$USE_CERTBOT" -eq 1 ]]; then
  log "Mode: HTTPS with Certbot Let's Encrypt"
else
  log "Mode: HTTPS with self-signed certificate"
fi

# Compose always mounts deploy/container/.env.production — sync --env into that path
if [[ -n "${ENV_FILE}" && -f "$ENV_FILE" ]]; then
  abs_env="$(cd "$(dirname "$ENV_FILE")" && pwd)/$(basename "$ENV_FILE")"
  abs_default="$(cd "$(dirname "$DEFAULT_ENV")" && pwd)/$(basename "$DEFAULT_ENV")"
  if [[ "$abs_env" != "$abs_default" ]]; then
    cp "$ENV_FILE" "$DEFAULT_ENV"
    log "Synced --env $ENV_FILE → $DEFAULT_ENV (Compose env_file)"
  fi
fi
ENV_FILE="$DEFAULT_ENV"

# --- Env (preserve existing) ---
if [[ ! -f "$ENV_FILE" ]]; then
  log "Creating $ENV_FILE from example (first run)"
  sed -e "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
      -e "s|https://|${SCHEME}://|g" \
      "$SCRIPT_DIR/env.production.example" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  log "Reusing existing env: $ENV_FILE"
  if grep -q 'DOMAIN_PLACEHOLDER' "$ENV_FILE" 2>/dev/null; then
    tmp="$(mktemp)"
    sed -e "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" -e "s|https://|${SCHEME}://|g" "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  fi
  if [[ "$NO_TLS" -eq 1 ]]; then
    tmp="$(mktemp)"
    sed -e "s|^PUBLIC_URL=.*|PUBLIC_URL=http://$DOMAIN|" \
        -e "s|^CORS_ORIGINS=.*|CORS_ORIGINS=http://$DOMAIN|" \
        "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "Updated PUBLIC_URL/CORS for HTTP-only verify mode"
  elif grep -qE '^PUBLIC_URL=http://' "$ENV_FILE" 2>/dev/null; then
    tmp="$(mktemp)"
    sed -e "s|^PUBLIC_URL=.*|PUBLIC_URL=https://$DOMAIN|" \
        -e "s|^CORS_ORIGINS=.*|CORS_ORIGINS=https://$DOMAIN|" \
        "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "Updated PUBLIC_URL/CORS to HTTPS (left --no-tls)"
  fi
fi

# --- Certificates ---
mkdir -p "$CERT_DIR" "$CERTBOT_WWW"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"
TLS_SOURCE_FILE="$CERT_DIR/.tls-source"

write_tls_source() {
  echo "$1" > "$TLS_SOURCE_FILE"
  chmod 644 "$TLS_SOURCE_FILE" 2>/dev/null || true
}

read_tls_source() {
  if [[ -f "$TLS_SOURCE_FILE" ]]; then
    tr -d '[:space:]' < "$TLS_SOURCE_FILE"
  elif [[ -f "$FULLCHAIN" && -f "$PRIVKEY" ]]; then
    # Legacy deploys without marker — unknown; treat as reusable until mode switch
    echo "unknown"
  else
    echo ""
  fi
}

create_self_signed_certs() {
  log "Creating self-signed certificate for $DOMAIN in $CERT_DIR"
  rm -f "$FULLCHAIN" "$PRIVKEY"
  if ! openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout "$PRIVKEY" -out "$FULLCHAIN" \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1" 2>/dev/null; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
      -keyout "$PRIVKEY" -out "$FULLCHAIN" \
      -subj "/CN=$DOMAIN"
  fi
  chmod 644 "$FULLCHAIN"
  chmod 600 "$PRIVKEY"
  write_tls_source "self-signed"
}

ensure_certs_self_signed() {
  local src
  src="$(read_tls_source)"
  if [[ "$FORCE_CERTS" -eq 1 ]]; then
    warn "--force-self-signed: replacing certs in $CERT_DIR"
    create_self_signed_certs
    return 0
  fi
  # Switching from Let's Encrypt copies → must replace (container stores PEMs, not symlinks)
  if [[ "$src" == "letsencrypt" ]]; then
    log "Switching from Let's Encrypt to self-signed (--self-signed)"
    create_self_signed_certs
    return 0
  fi
  if [[ -f "$FULLCHAIN" && -f "$PRIVKEY" && ( "$src" == "self-signed" || "$src" == "unknown" ) ]]; then
    log "Using existing certificates in $CERT_DIR (source=$src; use --force-self-signed to rotate)"
    if [[ "$src" == "unknown" ]]; then
      write_tls_source "self-signed"
    fi
    return 0
  fi
  create_self_signed_certs
}

install_le_certs_into_gateway() {
  local le_live="$LE_DIR/live/$DOMAIN"
  if [[ ! -f "$le_live/fullchain.pem" || ! -f "$le_live/privkey.pem" ]]; then
    echo "ERROR: Let's Encrypt files missing under $le_live" >&2
    return 1
  fi
  log "Installing Let's Encrypt PEMs into $CERT_DIR (replacing any prior self-signed)"
  rm -f "$FULLCHAIN" "$PRIVKEY"
  cp -L "$le_live/fullchain.pem" "$FULLCHAIN"
  cp -L "$le_live/privkey.pem" "$PRIVKEY"
  chmod 644 "$FULLCHAIN"
  chmod 600 "$PRIVKEY"
  write_tls_source "letsencrypt"
  log "Installed Let's Encrypt PEMs into $CERT_DIR"
}

run_certbot() {
  mkdir -p "$LE_DIR" "$CERTBOT_WWW"
  local args=(certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos)
  if [[ -n "$EMAIL" ]]; then
    args+=(--email "$EMAIL")
  else
    args+=(--register-unsafely-without-email)
  fi
  # Re-run when switching from self-signed or renewing
  if [[ -d "$LE_DIR/live/$DOMAIN" ]]; then
    args+=(--force-renewal)
  fi
  log "Running certbot (DNS for $DOMAIN must point here; port 80 must reach the gateway)"
  docker run --rm \
    -v "$CERTBOT_WWW:/var/www/certbot" \
    -v "$LE_DIR:/etc/letsencrypt" \
    certbot/certbot "${args[@]}"
}

if [[ "$NO_TLS" -eq 1 ]]; then
  log "Skipping certificate setup (--no-tls)"
elif [[ "$USE_CERTBOT" -eq 1 ]]; then
  # Need some cert so TLS nginx config can start; then swap to LE
  if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
    create_self_signed_certs
  else
    log "Temporary gateway cert present (will replace with Let's Encrypt after ACME)"
  fi
else
  ensure_certs_self_signed
fi

# --- Render nginx runtime configs (owned files only under this directory) ---
mkdir -p "$RUNTIME_CONF" "$RUNTIME_STREAM"
rm -f "$RUNTIME_CONF"/*.conf "$RUNTIME_STREAM"/*.conf "$OVERRIDE_FILE"

if [[ "$NO_TLS" -eq 1 ]]; then
  sed "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
    "$SCRIPT_DIR/nginx/conf.d/default-http.conf.template" > "$RUNTIME_CONF/default.conf"
  cp "$SCRIPT_DIR/nginx/stream.d/mqtt-cleartext.conf.template" \
    "$RUNTIME_STREAM/mqtt-cleartext.conf"
  cat > "$OVERRIDE_FILE" <<'EOF'
# Generated by deploy/container/deploy.sh — HTTP-only verify (--no-tls)
services:
  gateway:
    ports:
      - "1883:1883"
EOF
  log "Rendered HTTP-only gateway config (no TLS listeners in nginx)"
else
  sed "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" \
    "$SCRIPT_DIR/nginx/conf.d/default.conf.template" > "$RUNTIME_CONF/default.conf"
  cp "$SCRIPT_DIR/nginx/stream.d/mqtt.conf.template" "$RUNTIME_STREAM/mqtt.conf"
  if [[ "$MQTT_CLEARTEXT" -eq 1 ]]; then
    log "Enabling MQTT cleartext on host :1883"
    cp "$SCRIPT_DIR/nginx/stream.d/mqtt-cleartext.conf.template" \
      "$RUNTIME_STREAM/mqtt-cleartext.conf"
    cat > "$OVERRIDE_FILE" <<'EOF'
# Generated by deploy/container/deploy.sh — MQTT cleartext publish
services:
  gateway:
    ports:
      - "1883:1883"
EOF
  fi
fi

# nginx include *.conf fails on some builds if the directory has zero matches
if ! compgen -G "$RUNTIME_STREAM/*.conf" >/dev/null; then
  echo "# placeholder — no stream servers" > "$RUNTIME_STREAM/zz-empty.conf"
fi

cd "$SCRIPT_DIR"

COMPOSE_ARGS=(-f "$COMPOSE_FILE")
if [[ -f "$OVERRIDE_FILE" ]]; then
  COMPOSE_ARGS+=(-f "$OVERRIDE_FILE")
fi

log "Validating gateway nginx config"
if ! docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps gateway nginx -t; then
  echo "ERROR: gateway nginx -t failed — check deploy/container/nginx/runtime/" >&2
  exit 1
fi

log "Building / starting Compose stack (app + nginx gateway)"
# --force-recreate so bind-mounted nginx runtime conf is picked up on re-run
# (plain up -d leaves a running gateway with stale in-memory config)
UP_ARGS=(up -d --remove-orphans --force-recreate)
if [[ "$NO_BUILD" -eq 0 ]]; then
  UP_ARGS+=(--build)
fi

docker compose "${COMPOSE_ARGS[@]}" "${UP_ARGS[@]}"

if [[ "$NO_TLS" -eq 0 && "$USE_CERTBOT" -eq 1 ]]; then
  log "Waiting for HTTP :80 (ACME webroot) before certbot..."
  sleep 3
  if run_certbot && install_le_certs_into_gateway; then
    log "Reloading gateway with Let's Encrypt certificates"
    docker compose "${COMPOSE_ARGS[@]}" up -d --force-recreate --no-deps gateway
  else
    warn "certbot failed — continuing with certificates already in $CERT_DIR"
    warn "Retry: $0 --domain $DOMAIN --certbot --email you@example.com"
    warn "Or use self-signed: $0 --domain $DOMAIN --self-signed"
  fi
fi

log "Waiting for gateway..."
sleep 2
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if [[ "$NO_TLS" -eq 1 ]]; then
    if curl -sf --connect-timeout 2 "http://127.0.0.1/health" -H "Host: $DOMAIN" >/dev/null 2>&1 \
      || curl -sf --connect-timeout 2 "http://localhost/health" >/dev/null 2>&1; then
      break
    fi
  else
    if curl -skf --connect-timeout 2 "https://127.0.0.1/health" -H "Host: $DOMAIN" >/dev/null 2>&1 \
      || curl -skf --connect-timeout 2 "https://localhost/health" >/dev/null 2>&1; then
      break
    fi
  fi
  sleep 2
done

if [[ "$SKIP_VALIDATE" -eq 0 ]]; then
  VALIDATE="$REPO_ROOT/deploy/validate.sh"
  if [[ -f "$VALIDATE" ]]; then
    if [[ "$NO_TLS" -eq 1 ]]; then
      log "Smoke validation via HTTP gateway (includes HTTP Streams)"
      bash "$VALIDATE" --base "http://127.0.0.1" || \
        warn "validate.sh reported failures — check: docker compose -f $COMPOSE_FILE logs"
    else
      log "Smoke validation via HTTPS gateway (includes HTTP Streams)"
      bash "$VALIDATE" --base "https://127.0.0.1" --insecure || \
        warn "validate.sh reported failures — check: docker compose -f $COMPOSE_FILE logs"
    fi
  fi
fi

if [[ "$NO_TLS" -eq 1 ]]; then
  cat <<EOF

============================================================
 Container deploy complete — HTTP-only verify (--no-tls)

 No certificates were created.
 Host /etc/nginx was NOT modified.

 Compose project: mock-server
   $SCRIPT_DIR/nginx/runtime/
   $ENV_FILE

 Verify via gateway:
   http://$DOMAIN/                 (:80)
   http://$DOMAIN/http-stream/demo
   ws://$DOMAIN/ws/demo
   gRPC cleartext  $DOMAIN:50051
   MQTT cleartext  $DOMAIN:1883

   ./deploy/validate.sh --base http://127.0.0.1
   ./deploy/validate.sh --base http://$DOMAIN

 When ready for TLS, re-run WITHOUT --no-tls:
   ./deploy/container/deploy.sh --domain $DOMAIN --self-signed
   ./deploy/container/deploy.sh --domain $DOMAIN --certbot --email you@example.com

 Stop this stack only:
   ./deploy/container/deploy.sh --down
============================================================
EOF
else
  cat <<EOF

============================================================
 Container deploy complete (repeatable)

 Compose project: mock-server
 Files owned here only:
   $SCRIPT_DIR/docker-compose.yml
   $SCRIPT_DIR/nginx/runtime/
   $SCRIPT_DIR/certs/          (reused if present)
   $ENV_FILE

 Host /etc/nginx was NOT modified.
 Other Compose projects were NOT touched.

 Public (gateway):
   https://$DOMAIN/                 (:443)
   https://$DOMAIN/http-stream/demo
   wss://$DOMAIN/ws/demo
   gRPC TLS  $DOMAIN:50051
   MQTT TLS  $DOMAIN:8883
$([ "$MQTT_CLEARTEXT" -eq 1 ] && echo "   MQTT clear $DOMAIN:1883")

 TLS mode: $([ "$USE_CERTBOT" -eq 1 ] && echo "certbot / Let's Encrypt" || echo "self-signed")
 Certs:    $CERT_DIR

 Re-run / upgrade:
   ./deploy/container/deploy.sh --domain $DOMAIN --self-signed
   ./deploy/container/deploy.sh --domain $DOMAIN --certbot --email you@example.com

 Validate:
   ./deploy/validate.sh --base https://$DOMAIN --insecure

 Verify first without TLS:
   ./deploy/container/deploy.sh --domain $DOMAIN --no-tls

 Stop this stack only:
   ./deploy/container/deploy.sh --down
============================================================
EOF
fi
