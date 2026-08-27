#!/usr/bin/env bash
# Sample curls for every common HTTP verb (+ GraphQL / SSE / gRPC paths)
set -euo pipefail
HOST="${HOST:-localhost}"
BASE="http://${HOST}:3000"

echo "=== GET list ==="
curl -s "${BASE}/http/users"
echo -e "\n"

echo "=== GET by id ==="
curl -s "${BASE}/http/users/42"
echo -e "\n"

echo "=== POST create ==="
curl -s -X POST "${BASE}/http/users" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada","email":"ada@example.com"}'
echo -e "\n"

echo "=== PUT replace ==="
curl -s -X PUT "${BASE}/http/users/42" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada Lovelace","email":"ada@example.com"}'
echo -e "\n"

echo "=== PATCH partial ==="
curl -s -X PATCH "${BASE}/http/users/42" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Augusta Ada"}'
echo -e "\n"

echo "=== DELETE ==="
curl -s -X DELETE "${BASE}/http/users/42"
echo -e "\n"

echo "=== HEAD ==="
curl -s -I "${BASE}/http/users/42" | head -n 10
echo

echo "=== OPTIONS ==="
curl -s -X OPTIONS "${BASE}/http/users" -D - -o /dev/null | head -n 15
echo

echo "=== GraphQL query ==="
curl -s -X POST "${BASE}/graphql" \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ users { id name } }"}'
echo -e "\n"

echo "=== GraphQL mutation ==="
curl -s -X POST "${BASE}/graphql" \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { createUser(name: \"Ada\", email: \"ada@example.com\") { id name email } }"}'
echo -e "\n"

echo "=== SSE ==="
curl -s -N --max-time 2 "${BASE}/sse/demo" | head -n 6 || true
echo -e "\n"

echo "=== gRPC path ==="
curl -s "${BASE}/grpc/demo"
echo -e "\n"

echo "Done. WebSocket: wscat -c ws://${HOST}:3001/ws/demo"
echo "MQTT: mosquitto_pub -h ${HOST} -p 1883 -t mqtt/demo -m '{\"message\":\"hi\"}'"
