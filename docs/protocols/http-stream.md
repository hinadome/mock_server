# HTTP Streams (Fetch)

## Summary (learn this first)

**HTTP Streams (Fetch)** means a normal **HTTP** response whose body arrives in chunks. Clients use the Fetch API’s `ReadableStream` (`response.body.getReader()`) to read bytes as they arrive — not a separate wire protocol.

| Idea | Meaning |
|------|---------|
| Still HTTP | Same request/response model as REST |
| Chunked body | Server writes pieces over time (`Transfer-Encoding: chunked`) |
| Client API | `fetch` + `ReadableStream` (browsers, Node 18+, Deno, Bun) |
| Best for | LLM token streams, progress, large downloads, progressive JSON (NDJSON) |
| Not ideal for | Bidirectional chat (use WebSocket) or named browser events (use SSE) |

**Compared to others:** Plain HTTP returns one finished body. SSE wraps a long-lived HTTP stream in `event:` / `data:` lines for `EventSource`. HTTP Streams (Fetch) is raw body chunks — you parse them yourself (often **NDJSON**).

## How a stream works

```
Client (fetch)                         Server :3000
  |  GET /http-stream/demo               |
  |------------------------------------->|
  |  200 + chunked body                  |
  |  {"seq":1,...}\n                     |
  |<-------------------------------------|
  |  {"seq":2,...}\n                     |
  |<-------------------------------------|
  |  ... then connection closes          |
```

Browser / Node:

```js
const res = await fetch('http://localhost:3000/http-stream/demo');
const reader = res.body.getReader();
const decoder = new TextDecoder();
for (;;) {
  const { done, value } = await reader.read();
  if (done) break;
  console.log(decoder.decode(value, { stream: true }));
}
```

## On this server

| Item | Value |
|------|-------|
| Port | `3000` |
| Path pattern | `/http-stream/{name}` |
| Demo | `/http-stream/demo` — 5 NDJSON chunks, then closes |
| Tokens | `/http-stream/tokens` — fake LLM token stream |
| Live bus | `/http-stream/orders.created` — stays open for emits |
| Default format | `application/x-ndjson` (one JSON object per line) |
| Text mode | `?format=text` |
| Mock file | [`mocks/http-stream.yaml`](../../mocks/http-stream.yaml) |

`/http-stream` redirects to `/http-stream/demo`.

## Try it

```bash
# Watch chunks arrive (do not buffer)
curl -N http://localhost:3000/http-stream/demo
curl -N http://localhost:3000/http-stream/tokens

# Plain text chunks
curl -N 'http://localhost:3000/http-stream/demo?format=text'
```

Live bus (keep open, then emit from another terminal):

```bash
curl -N http://localhost:3000/http-stream/orders.created
# elsewhere:
curl -X POST http://localhost:3000/http/orders \
  -H 'Content-Type: application/json' -d '{"item":"book"}'
```

Node one-liner style:

```bash
node --input-type=module -e '
const res = await fetch("http://localhost:3000/http-stream/demo");
for await (const chunk of res.body) process.stdout.write(chunk);
'
```

## Mock configuration

```yaml
# mocks/http-stream.yaml
routes:
  - match: { topic: demo }
    response:
      headers:
        Content-Type: application/x-ndjson
      chunkDelayMs: 400
      stream:
        - { seq: 1, message: "first" }
        - { seq: 2, message: "second" }
      keepOpen: false   # end after stream (Fetch consumers see done: true)

  - match: { topic: orders.created }
    response:
      stream:
        - { type: connected, topic: orders.created }
      keepOpen: true    # stay open for event-bus publishes
```

The path name (`/http-stream/orders.created` → topic `orders.created`) is what the bus matches when `keepOpen: true`.

## Common mistakes

- Expecting `EventSource` to work — that needs SSE (`text/event-stream`), not NDJSON
- Buffering with `curl` without `-N`
- Calling `res.json()` / `res.text()` — that waits for the **entire** body; use `getReader()` or `for await`
- Confusing this with WebSocket — Fetch streams are still one HTTP response

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [MDN — Using readable streams](https://developer.mozilla.org/en-US/docs/Web/API/Streams_API/Using_readable_streams) | `getReader()` patterns |
| [MDN — Response.body](https://developer.mozilla.org/en-US/docs/Web/API/Response/body) | Fetch streaming body |
| [MDN — fetch()](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API) | Fetch overview |
| [WHATWG Fetch](https://fetch.spec.whatwg.org/) | Spec |
| [NDJSON](https://github.com/ndjson/ndjson-spec) | Newline-delimited JSON |
