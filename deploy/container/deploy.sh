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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"
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

Options:
  --no-tls                   HTTP-only verify mode: no certificates, no HTTPS.
                             Use to test app/gateway before TLS. Serves :80,
                             cleartext gRPC :50051, MQTT :1883.
  --env FILE                 Env file (default: deploy/container/.env.production)
  --force-certs              Regenerate self-signed certs even if certs exist
                             (ignored with --no-tls)
  --mqtt-cleartext           Also publish host TCP 1883 → MQTT
                             (implied by --no-tls)
  --skip-validate            Skip post-up smoke checks
  --no-build                 docker compose up without --build
  --down                     Stop and remove this Compose stack only
  -h, --help

Repeatable: re-run after code changes to rebuild/restart. Existing
deploy/container/certs/*.pem and .env.production are preserved by default.

Does NOT modify host nginx or other Compose projects.

Upgrade from --no-tls to TLS later:
  ./deploy/container/deploy.sh --domain HOST
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --env) ENV_FILE="${2:-}"; shift 2 ;;
    --no-tls) NO_TLS=1; MQTT_CLEARTEXT=1; shift ;;
    --force-certs) FORCE_CERTS=1; shift ;;
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
fi

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
mkdir -p "$CERT_DIR"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"

ensure_certs() {
  if [[ "$FORCE_CERTS" -ne 1 && -f "$FULLCHAIN" && -f "$PRIVKEY" ]]; then
    log "Using existing certificates in $CERT_DIR (not overridden)"
    return 0
  fi
  if [[ "$FORCE_CERTS" -eq 1 ]]; then
    warn "--force-certs: replacing certs in $CERT_DIR"
    rm -f "$FULLCHAIN" "$PRIVKEY"
  fi
  log "Creating self-signed certificate for $DOMAIN (30 days) — replace with LE/production PEMs when ready"
  openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout "$PRIVKEY" -out "$FULLCHAIN" \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1"
  chmod 644 "$FULLCHAIN"
  chmod 600 "$PRIVKEY"
}

if [[ "$NO_TLS" -eq 1 ]]; then
  log "Skipping certificate setup (--no-tls)"
else
  ensure_certs
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

cd "$SCRIPT_DIR"

COMPOSE_ARGS=(-f "$COMPOSE_FILE")
if [[ -f "$OVERRIDE_FILE" ]]; then
  COMPOSE_ARGS+=(-f "$OVERRIDE_FILE")
fi

log "Building / starting Compose stack (app + nginx gateway)"
UP_ARGS=(up -d --remove-orphans)
if [[ "$NO_BUILD" -eq 0 ]]; then
  UP_ARGS+=(--build)
fi

docker compose "${COMPOSE_ARGS[@]}" "${UP_ARGS[@]}"

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
   ./deploy/container/deploy.sh --domain $DOMAIN

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

 Re-run / upgrade:
   ./deploy/container/deploy.sh --domain $DOMAIN

 Validate:
   ./deploy/validate.sh --base https://$DOMAIN --insecure

 Verify first without TLS:
   ./deploy/container/deploy.sh --domain $DOMAIN --no-tls

 Stop this stack only:
   ./deploy/container/deploy.sh --down

 Replace TLS: copy PEMs to $CERT_DIR/{fullchain,privkey}.pem
 then re-run (without --force-certs) — existing files are kept.
============================================================
EOF
fi
