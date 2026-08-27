# Protocol learning guides

Detailed guides for every protocol this mock server implements. Each guide includes:

1. **Summary** — what it is and when to use it  
2. **How it works** — connection / request flow  
3. **On this server** — ports, paths, mock files  
4. **Built-in samples** — copy-paste commands  
5. **Mock configuration** — how to customize fixtures  
6. **Common mistakes**  
7. **Learn more** — official specs and tutorials  

| Protocol | Guide | Pattern | Port |
|----------|-------|---------|------|
| [HTTP / REST](./http.md) | Request → response (CRUD verbs) | `3000` |
| [HTTP Streams (Fetch)](./http-stream.md) | Chunked body via `fetch` ReadableStream | `3000` |
| [WebSocket](./websocket.md) | Bidirectional persistent connection | `3001` |
| [SSE](./sse.md) | Server → client event stream | `3000` |
| [GraphQL](./graphql.md) | Query / mutation / subscription | `3000` |
| [gRPC](./grpc.md) | Typed RPC (unary + 3 stream modes) | `50051` |
| [MQTT](./mqtt.md) | Publish / subscribe via broker | `1883` |

Related: [Auth & TLS](../auth-tls.md) · [Main README](../../README.md)

## Quick compare

```
Pull (client asks)              Push (server / broker sends)
─────────────────────           ────────────────────────────
HTTP / REST                     SSE (one-way over HTTP)
GraphQL (query/mutation)        WebSocket (two-way)
gRPC (unary)                    GraphQL subscriptions (WS)
HTTP Streams / Fetch (chunked)  MQTT (pub/sub to many)
                                gRPC streaming
```

## Cross-protocol events

Many demos share an internal **event bus**:

1. `POST /http/orders` (or GraphQL `publishOrder`) emits `orders.created`
2. SSE client on `/sse/orders.created` receives it  
3. WebSocket client subscribed to `orders.created` receives it  
4. MQTT subscribers on that topic receive it  
5. GraphQL `subscription { orderCreated { ... } }` receives it  

## In the running server

| URL | Purpose |
|-----|---------|
| http://localhost:3000/ | Dashboard |
| http://localhost:3000/docs/protocols/{name} | These guides |
| http://localhost:3000/api/discovery | Connection info + examples |
| http://localhost:3000/api/requests | Request inspector |
| http://localhost:3000/health | Adapter status |
