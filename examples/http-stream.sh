#!/usr/bin/env bash
# HTTP Streams (Fetch) — watch NDJSON chunks arrive.
set -euo pipefail
HOST="${HOST:-localhost}"
HTTP="http://${HOST}:3000"

echo "=== /http-stream/demo (finite NDJSON) ==="
curl -s -N --max-time 5 "${HTTP}/http-stream/demo" || true
echo

echo "=== /http-stream/tokens ==="
curl -s -N --max-time 5 "${HTTP}/http-stream/tokens" || true
echo

echo "=== Fetch ReadableStream (Node) ==="
node --input-type=module -e "
const res = await fetch('${HTTP}/http-stream/demo');
const reader = res.body.getReader();
const dec = new TextDecoder();
for (;;) {
  const { done, value } = await reader.read();
  if (done) break;
  process.stdout.write(dec.decode(value, { stream: true }));
}
"
echo
echo "Done."
