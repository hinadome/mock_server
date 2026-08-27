#!/usr/bin/env bash
# Exercise all protocol demos. Set HOST to a remote LAN IP for external tests.
set -euo pipefail
HOST="${HOST:-localhost}"
HTTP="http://${HOST}:3000"
WS="ws://${HOST}:3001"

echo "=== HTTP ==="
curl -s "${HTTP}/http/demo"
echo -e "\n"

echo "=== HTTP Streams (Fetch) ==="
curl -s -N --max-time 3 "${HTTP}/http-stream/demo" | head -n 6 || true
echo -e "\n"

echo "=== HTTP users ==="
curl -s "${HTTP}/http/users/42"
echo -e "\n"

echo "=== GraphQL path demo ==="
curl -s "${HTTP}/graphql/demo"
echo -e "\n"

echo "=== GraphQL POST ==="
curl -s -X POST "${HTTP}/graphql" \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ demo hello(name: \"Ada\") }"}'
echo -e "\n"

echo "=== gRPC HTTP path ==="
curl -s "${HTTP}/grpc/demo"
echo -e "\n"

echo "=== SSE (2s) ==="
curl -s -N --max-time 2 "${HTTP}/sse/demo" | head -n 8 || true
echo -e "\n"

echo "=== Health ==="
curl -s "${HTTP}/health"
echo -e "\n"

echo "=== Discovery ==="
curl -s "${HTTP}/api/discovery" | head -c 500
echo -e "\n"

if command -v grpcurl >/dev/null 2>&1; then
  echo "=== gRPC reflection ==="
  grpcurl -plaintext "${HOST}:50051" list || true
  echo
  echo "=== gRPC Ping ==="
  grpcurl -plaintext -d '{"message":"hello"}' "${HOST}:50051" demo.DemoService/Ping || true
  echo
fi

if command -v mosquitto_pub >/dev/null 2>&1; then
  echo "=== MQTT (publish mqtt/demo) ==="
  mosquitto_pub -h "${HOST}" -p 1883 -t mqtt/demo -m '{"message":"hi"}' || true
fi

echo
echo "WebSocket try: wscat -c ${WS}/ws/demo"
echo "Done."
