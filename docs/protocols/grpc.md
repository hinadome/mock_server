# gRPC

## Summary (learn this first)

**gRPC** is a high-performance **Remote Procedure Call** framework. You define services and messages in a `.proto` file (Protocol Buffers). Clients call methods like local functions; the wire format is compact binary over **HTTP/2**.

| RPC style | Shape | Demo method |
|-----------|-------|-------------|
| Unary | 1 → 1 | `Ping` |
| Server streaming | 1 → many | `StreamPings` |
| Client streaming | many → 1 | `CollectPings` |
| Bidirectional | many ↔ many | `Chat` |

| Idea | Meaning |
|------|---------|
| Contract-first | `.proto` is shared by client and server |
| Best for | Service-to-service calls, low latency, strongly typed APIs |
| Not ideal for | Ad-hoc browser curl without tooling (use `/grpc/demo` helpers or REST) |

**Compared to others:** REST/GraphQL usually exchange JSON. gRPC uses protobuf + HTTP/2. This mock also exposes curl-friendly HTTP paths so you can learn without `grpcurl` first.

## How a unary call works

```
Client (grpcurl)                    Server :50051
  |  DemoService.Ping({message})      |
  |---------------------------------->|
  |  PingReply({message, protocol})   |
  |<----------------------------------|
```

## On this server

| Item | Value |
|------|-------|
| gRPC port | **`50051`** |
| Package / service | `demo.DemoService` |
| Reflection | Enabled (`grpcurl list` works without local proto) |
| HTTP helpers | `GET /grpc/demo`, `GET /grpc/ping` on port `3000` |
| Proto | [`mocks/grpc/demo.proto`](../../mocks/grpc/demo.proto) |
| Fixtures | [`mocks/grpc/routes.yaml`](../../mocks/grpc/routes.yaml) |
| TLS / mTLS | Same env as HTTP — [auth-tls.md](../auth-tls.md) |

## Try it — HTTP helpers

```bash
curl http://localhost:3000/grpc/demo
curl "http://localhost:3000/grpc/ping?message=hi"
```

## Try it — real gRPC

```bash
# Install: https://github.com/fullstorydev/grpcurl
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext localhost:50051 list demo.DemoService

grpcurl -plaintext -d '{"message":"hello"}' \
  localhost:50051 demo.DemoService/Ping

grpcurl -plaintext -d '{"message":"hello"}' \
  localhost:50051 demo.DemoService/StreamPings
```

**Client streaming / bidi** need a streaming client (grpcurl interactive mode or a small program). Methods:

- `demo.DemoService/CollectPings` — send multiple `PingRequest`, get one `PingReply`
- `demo.DemoService/Chat` — send/receive interleaved messages

## Mock configuration

```protobuf
# mocks/grpc/demo.proto
service DemoService {
  rpc Ping (PingRequest) returns (PingReply);
  rpc StreamPings (PingRequest) returns (stream PingReply);
  rpc CollectPings (stream PingRequest) returns (PingReply);
  rpc Chat (stream PingRequest) returns (stream PingReply);
}
```

```yaml
# mocks/grpc/routes.yaml
routes:
  - match: { service: DemoService, grpcMethod: Ping }
    response:
      body:
        message: "Pong from mock: {{req.body.message}}"
  - match: { service: DemoService, grpcMethod: StreamPings }
    response:
      stream:
        - { message: "stream-1", protocol: "grpc" }
```

Proto changes are applied at startup (file is written/loaded when the gRPC adapter starts).

## TLS

```bash
./scripts/gen-certs.sh
TLS_ENABLED=1 TLS_CERT=./certs/server.crt TLS_KEY=./certs/server.key npm start

grpcurl -cacert certs/ca.crt localhost:50051 list
```

## Common mistakes

- Plain `curl` against `:50051` — use `grpcurl` or `/grpc/demo`
- Forgetting `-plaintext` when TLS is off
- Editing proto and forgetting to restart
- Confusing HTTP helper paths with real gRPC port

## Production ports

Common public setups: **50051** with TLS (this deploy), or **443** with nginx `grpc_pass`. The app listens on `127.0.0.1:50051`. See [production.md](../production.md).

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [gRPC introduction](https://grpc.io/docs/what-is-grpc/introduction/) | Official intro |
| [Core concepts](https://grpc.io/docs/what-is-grpc/core-concepts/) | All four RPC types |
| [Protocol Buffers](https://protobuf.dev/programming-guides/proto3/) | `.proto` language |
| [Language guides](https://grpc.io/docs/languages/) | Node, Go, Java, Python… |
| [grpcurl](https://github.com/fullstorydev/grpcurl) | curl for gRPC |
| [HTTP/2 RFC 9113](https://www.rfc-editor.org/rfc/rfc9113.html) | Transport layer |
