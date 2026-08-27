#!/usr/bin/env bash
# Generate self-signed certs for local TLS / mTLS testing.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/certs"
mkdir -p "$DIR"

# CA
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$DIR/ca.key" -out "$DIR/ca.crt" \
  -subj "/CN=Mock Server Dev CA"

# Server
openssl req -newkey rsa:2048 -nodes \
  -keyout "$DIR/server.key" -out "$DIR/server.csr" \
  -subj "/CN=localhost"
openssl x509 -req -in "$DIR/server.csr" -days 825 \
  -CA "$DIR/ca.crt" -CAkey "$DIR/ca.key" -CAcreateserial \
  -out "$DIR/server.crt" \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1")

# Client (mTLS)
openssl req -newkey rsa:2048 -nodes \
  -keyout "$DIR/client.key" -out "$DIR/client.csr" \
  -subj "/CN=mock-client"
openssl x509 -req -in "$DIR/client.csr" -days 825 \
  -CA "$DIR/ca.crt" -CAkey "$DIR/ca.key" -CAcreateserial \
  -out "$DIR/client.crt"

rm -f "$DIR"/*.csr "$DIR"/*.srl
echo "Wrote certs to $DIR"
echo
echo "TLS only:"
echo "  TLS_ENABLED=1 TLS_CERT=$DIR/server.crt TLS_KEY=$DIR/server.key npm start"
echo
echo "mTLS:"
echo "  TLS_ENABLED=1 TLS_MTLS=1 TLS_CERT=$DIR/server.crt TLS_KEY=$DIR/server.key TLS_CA=$DIR/ca.crt npm start"
echo
echo "JWT required:"
echo "  AUTH_REQUIRED=1 JWT_ENABLED=1 npm start"
