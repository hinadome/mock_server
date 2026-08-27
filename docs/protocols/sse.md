# Server-Sent Events (SSE)

## Summary (learn this first)

**SSE** streams updates **from server to client** over a normal HTTP connection. The client opens a long-lived `GET` (`Accept: text/event-stream`); the server pushes `event:` / `data:` lines.

| Idea | Meaning |
|------|---------|
| One-way | Server pushes; client does not send on the same stream |
| HTTP-friendly | Often easier with proxies/CDNs than raw WebSocket |
| Auto-reconnect | Browser `EventSource` reconnects by default |
| Best for | Live feeds, notifications, progress, tickers |
| Not ideal for | Frequent client→server traffic (WebSocket) or IoT fleets (MQTT) |

**Compared to others:** WebSocket is two-way. HTTP is one request/one response. SSE is “HTTP that stays open and streams.”

## How a stream works

```
Client                              Server :3000
  |  GET /sse/demo                    |
  |  Accept: text/event-stream        |
  |---------------------------------->|
  |  event: connected                 |
  |  data: {...}                      |
  |<----------------------------------|
  |  event: demo / message            |
  |  data: {...}                      |
  |<----------------------------------|
```

## On this server

| Item | Value |
|------|-------|
| Port | `3000` |
| Path pattern | `/sse/{topic}` — **each topic is its own path** |
| Demo | `/sse/demo` → 3 timed events, then listens on bus |
| Cross-protocol | `/sse/orders.created` receives HTTP/GraphQL emits |
| Mock file | [`mocks/sse.yaml`](../../mocks/sse.yaml) |

`/sse` redirects to `/sse/demo`.

## Try it

```bash
curl -N http://localhost:3000/sse/demo
curl -N http://localhost:3000/sse/orders.created
```

Trigger an event:

```bash
curl -X POST http://localhost:3000/http/orders \
  -H 'Content-Type: application/json' \
  -d '{"item":"book"}'
```

Browser:

```js
const es = new EventSource('http://localhost:3000/sse/demo');
es.addEventListener('demo', (e) => console.log(JSON.parse(e.data)));
es.onmessage = (e) => console.log(e.data);
```

## Mock configuration

```yaml
# mocks/sse.yaml
routes:
  - match: { topic: orders.created }
    response:
      body:
        event: orders.created
```

The path topic (`/sse/orders.created` → topic `orders.created`) is what the bus matches for push delivery.

## Common mistakes

- Missing `curl -N` (output buffers until close)
- Closing immediately — keep the connection open
- POSTing on the SSE connection — use a separate HTTP request
- zsh globbing on `?query=` — this server uses path topics to avoid that

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [MDN — Server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) | Overview |
| [MDN — Using SSE](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events) | `EventSource` tutorial |
| [MDN — EventSource](https://developer.mozilla.org/en-US/docs/Web/API/EventSource) | API reference |
| [WHATWG SSE](https://html.spec.whatwg.org/multipage/server-sent-events.html) | Wire format |
| [W3C EventSource](https://www.w3.org/TR/eventsource/) | W3C recommendation |
