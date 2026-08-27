#!/usr/bin/env bash
# Subscribe to mqtt/demo/response, then publish to mqtt/demo
HOST="${HOST:-localhost}"
echo "Subscribing to mqtt/demo/response (Ctrl+C to stop)..."
mosquitto_sub -h "$HOST" -p 1883 -t 'mqtt/demo/response' -v &
SUB_PID=$!
sleep 1
mosquitto_pub -h "$HOST" -p 1883 -t mqtt/demo -m '{"message":"hello from example"}'
sleep 1
kill "$SUB_PID" 2>/dev/null || true
