#!/usr/bin/env bash
# Validate mock-server endpoints after deploy (local app or public nginx URL).
#
# Usage:
#   ./deploy/validate.sh                         # http://127.0.0.1:3000
#   ./deploy/validate.sh --base https://api.example.com
#   ./deploy/validate.sh --base http://127.0.0.1:3000 --skip-stream-timing
#
set -euo pipefail

BASE="http://127.0.0.1:3000"
SKIP_STREAM_TIMING=0
INSECURE=0

usage() {
  cat <<EOF
Usage: $0 [--base URL] [--skip-stream-timing] [--insecure]

  --base URL              API base (default: http://127.0.0.1:3000)
  --skip-stream-timing    Only check that http-stream returns NDJSON (not timing)
  --insecure              curl -k (self-signed TLS)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --skip-stream-timing) SKIP_STREAM_TIMING=1; shift ;;
    --insecure) INSECURE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

BASE="${BASE%/}"
CURL=(curl -sS --fail --connect-timeout 5)
if [[ "$INSECURE" -eq 1 ]]; then
  CURL+=(-k)
fi

PASS=0
FAIL=0

ok() { echo "  OK  $*"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }

echo "==> Validating mock-server at $BASE"

# Health
if BODY="$("${CURL[@]}" "$BASE/health" 2>/dev/null)"; then
  if echo "$BODY" | grep -q 'http'; then
    ok "GET /health"
  else
    bad "GET /health (unexpected body)"
  fi
else
  bad "GET /health"
fi

# HTTP demo
if BODY="$("${CURL[@]}" "$BASE/http/demo" 2>/dev/null)"; then
  if echo "$BODY" | grep -qi 'http\|demo\|protocol'; then
    ok "GET /http/demo"
  else
    bad "GET /http/demo (unexpected body)"
  fi
else
  bad "GET /http/demo"
fi

# Discovery includes httpStream
if BODY="$("${CURL[@]}" "$BASE/api/discovery" 2>/dev/null)"; then
  if echo "$BODY" | grep -q 'httpStream\|http-stream'; then
    ok "GET /api/discovery (httpStream present)"
  else
    bad "GET /api/discovery (missing httpStream)"
  fi
else
  bad "GET /api/discovery"
fi

# HTTP Streams — content + optional progressive delivery check
STREAM_URL="$BASE/http-stream/demo"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

STREAM_CURL=(curl -sS -N --connect-timeout 5 --max-time 8)
if [[ "$INSECURE" -eq 1 ]]; then
  STREAM_CURL+=(-k)
fi

STREAM_OK=0
set +e
"${STREAM_CURL[@]}" "$STREAM_URL" >"$TMP" 2>/dev/null
STREAM_RC=$?
set -e
if [[ -s "$TMP" ]]; then
  LINES="$(grep -c '^{' "$TMP" || true)"
  if [[ "${LINES:-0}" -ge 3 ]]; then
    ok "GET /http-stream/demo (NDJSON chunks, ${LINES} lines)"
    STREAM_OK=1
  else
    bad "GET /http-stream/demo (expected ≥3 NDJSON lines; got ${LINES:-0}, rc=$STREAM_RC)"
    head -n 5 "$TMP" | sed 's/^/       /' || true
  fi
else
  bad "GET /http-stream/demo (empty body, rc=$STREAM_RC)"
fi

# Progressive timing: first bytes should arrive before the full 5×400ms stream
if [[ "$SKIP_STREAM_TIMING" -eq 0 && "$STREAM_OK" -eq 1 ]]; then
  TIME_CURL=(curl -sS -N --connect-timeout 5 --max-time 5 -o /dev/null -w '%{time_starttransfer}')
  if [[ "$INSECURE" -eq 1 ]]; then
    TIME_CURL+=(-k)
  fi
  set +e
  FIRST="$("${TIME_CURL[@]}" "$STREAM_URL" 2>/dev/null)"
  set -e
  if [[ -n "${FIRST:-}" ]]; then
    if awk -v t="$FIRST" 'BEGIN { exit !(t+0 > 0 && t+0 < 1.5) }'; then
      ok "GET /http-stream/demo TTFB ${FIRST}s (<1.5s — not fully buffered)"
    else
      bad "GET /http-stream/demo TTFB ${FIRST}s (≥1.5s or 0 — possible nginx buffering)"
    fi
  else
    bad "GET /http-stream/demo timing probe failed"
  fi
elif [[ "$SKIP_STREAM_TIMING" -eq 0 && "$STREAM_OK" -eq 0 ]]; then
  echo "  SKIP stream timing (stream content check failed)"
fi

# SSE still works (regression)
SSE_CURL=(curl -sS -N --connect-timeout 5 --max-time 3)
if [[ "$INSECURE" -eq 1 ]]; then
  SSE_CURL+=(-k)
fi
set +e
SSE_BODY="$("${SSE_CURL[@]}" "$BASE/sse/demo" 2>/dev/null)"
set -e
if echo "$SSE_BODY" | grep -q 'event:'; then
  ok "GET /sse/demo"
else
  bad "GET /sse/demo"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "Deployment endpoint validation OK (including HTTP Streams)."
