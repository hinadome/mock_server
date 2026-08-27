# WebSocket

## Summary (learn this first)

**WebSocket** upgrades an HTTP connection into a **persistent, bidirectional** channel. After the handshake, both client and server can send messages anytime without a new HTTP request per message.

| Idea | Meaning |
|------|---------|
| Stateful | One long-lived connection after `101 Switching Protocols` |
| Full duplex | Client → server and server → client on the same socket |
| Best for | Chat, games, collaborative editors, two-way live UIs |
| Not ideal for | One-shot APIs (HTTP); listen-only feeds (SSE is simpler) |

**Compared to others:** SSE is one-way. MQTT fans out via a broker. GraphQL subscriptions also use WebSocket (`graphql-ws`) but on port `3000` path `/graphql`, not this demo port.

## How a connection works

```
Client                              Server :3001
  |  HTTP GET Upgrade: websocket      |
  |---------------------------------->|
  |  101 Switching Protocols          |
  |<----------------------------------|
  |  {"action":"ping"}                |
  |---------------------------------->|
  |  {"type":"pong", ...}             |
  |<----------------------------------|
```

## On this server

| Item | Value |
|------|-------|
| Port | **`3001`** (separate from HTTP `3000`) |
| Path pattern | `/ws/{name}` |
| Demos | `/ws/demo`, `/ws/chat` |
| Mock file | [`mocks/websocket.yaml`](../../mocks/websocket.yaml) |
| Event bus | Subscribed topics receive `emit` / bus publishes |

Connecting to `/ws/demo` auto-subscribes to topic `demo`.

## Message protocol (JSON)

| Client sends | Server does |
|--------------|-------------|
| `{"action":"ping"}` | Replies `{"type":"pong",...}` |
| `{"action":"subscribe","topic":"orders.created"}` | Subscribes; later bus events arrive as `{"type":"event",...}` |
| Other JSON | Matched against mocks / echoed as `{"type":"response",...}` |

## Try it

```bash
# npm i -g wscat
wscat -c ws://localhost:3001/ws/demo
```

Then:

```json
{"action":"ping"}
{"action":"subscribe","topic":"orders.created"}
{"action":"message","payload":{"text":"hello"}}
```

Trigger a bus event from HTTP:

```bash
curl -X POST http://localhost:3000/http/orders \
  -H 'Content-Type: application/json' -d '{"item":"book"}'
```

## Mock configuration

```yaml
# mocks/websocket.yaml
routes:
  - match: { path: /ws/demo }
    response:
      body:
        type: echo
        message: Message received via WebSocket
```

## Common mistakes

- Using port `3000` for these demos — use **`3001`**
- Non-JSON messages — this mock expects JSON objects
- Expecting HTTP status codes per message — WS uses frames
- Confusing with GraphQL subscription WS on `/graphql`

## Production ports

In production (behind nginx), clients use **`wss://your-domain/ws/...` on port 443**, not a public `:3001`. The app still listens on `127.0.0.1:3001` locally. See [production.md](../production.md).

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [MDN — WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API) | Browser API + concepts |
| [MDN — Writing WebSocket clients](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_client_applications) | Practical examples |
| [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.html) | Official protocol |
| [websocket.org](https://websocket.org/what-is-websocket/) | Short overview |
| [WHATWG Web sockets](https://html.spec.whatwg.org/multipage/web-sockets.html) | Living standard |
