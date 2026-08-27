# Mock Server

Multi-protocol **mock/stub server** for local development, integration tests, and learning how network protocols work.

One process speaks **multiple protocols**, returns YAML-configured fixtures, and includes a dashboard, discovery API, request inspector, optional JWT auth, and optional TLS/mTLS.

| Protocol | Port (local / Docker) | Path pattern | Guide |
|----------|----------------------|--------------|-------|
| HTTP / REST | `3000` | `/http/{name}` | [docs/protocols/http.md](docs/protocols/http.md) |
| HTTP Streams (Fetch) | `3000` | `/http-stream/{name}` | [docs/protocols/http-stream.md](docs/protocols/http-stream.md) |
| WebSocket | `3001` | `/ws/{name}` | [docs/protocols/websocket.md](docs/protocols/websocket.md) |
| SSE | `3000` | `/sse/{topic}` | [docs/protocols/sse.md](docs/protocols/sse.md) |
| GraphQL | `3000` | `/graphql` (+ subscriptions over WS) | [docs/protocols/graphql.md](docs/protocols/graphql.md) |
| gRPC | `50051` (+ HTTP helpers on `3000`) | `demo.DemoService/*` | [docs/protocols/grpc.md](docs/protocols/grpc.md) |
| MQTT | `1883` | topics `mqtt/{name}` | [docs/protocols/mqtt.md](docs/protocols/mqtt.md) |

Security: [docs/auth-tls.md](docs/auth-tls.md) · Protocols: [docs/protocols/README.md](docs/protocols/README.md) · **Production (VM + Container):** [DEPLOYMENT.md](DEPLOYMENT.md) · Changelog: [CHANGELOG.md](CHANGELOG.md)

### Production public ports (behind nginx)

Local ports above are for the **app process**. In production, nginx terminates TLS and exposes well-known ports:

| Protocol | Public port | Client URL example |
|----------|-------------|--------------------|
| HTTP / SSE / GraphQL / HTTP Streams | **443** | `https://api.example.com/http/demo` |
| WebSocket | **443** (`wss`) | `wss://api.example.com/ws/demo` |
| gRPC | **50051** (TLS) or **443** | `api.example.com:50051` |
| MQTT cleartext | **1883** | Often firewalled; prefer TLS |
| MQTT TLS | **8883** | `api.example.com:8883` |

WebSocket is not a separate public port in production — it shares **443** with HTTPS. MQTT’s IANA ports are **1883** / **8883**. gRPC commonly uses **50051** (or **443** with HTTP/2).

```bash
# VM (host nginx + systemd)
sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com   # Certbot
sudo ./deploy/deploy.sh --domain api.example.com --self-signed             # self-signed TLS
# Verify first without certificates:
sudo ./deploy/deploy.sh --domain api.example.com --no-tls

# Container (Compose + nginx gateway — does not touch host nginx)
./deploy/container/deploy.sh --domain api.example.com --self-signed
./deploy/container/deploy.sh --domain api.example.com --certbot --email you@example.com
# Verify first without certificates:
./deploy/container/deploy.sh --domain api.example.com --no-tls
```

Full guide: [DEPLOYMENT.md](DEPLOYMENT.md) · Cloud VMs: [deploy/cloud/README.md](deploy/cloud/README.md)

---

## Quick start

```bash
npm install
npm run dev          # watch mode
# or
npm run build && npm start
```

Open **http://localhost:3000/** — dashboard with protocol cards, copy-paste examples, and live request inspector.

```bash
./examples/try-all.sh         # smoke several protocols
./examples/http-verbs.sh      # all HTTP verbs
./examples/http-stream.sh     # Fetch ReadableStream / NDJSON chunks
./examples/mqtt-demo.sh       # MQTT pub/sub
```

---

## Architecture

```
Clients (curl, apps, CI, mobile)
        │
        ▼
┌───────────────────────────────────────┐
│  Protocol adapters                    │
│  HTTP · HTTP Streams · WS · SSE · GraphQL · gRPC · MQTT │
└──────────────────┬────────────────────┘
                   ▼
┌───────────────────────────────────────┐
│  Mock engine  (match → delay → template │
│               → emit → inspect)         │
└──────────────────┬────────────────────┘
                   ▼
         YAML fixtures in mocks/
                   │
                   ▼
         Event bus → SSE / WS / MQTT / GraphQL subscriptions
```

**Path convention:** most HTTP-facing demos use `/{protocol}/{name}` so each sample is its own endpoint (no `?query=` required).

---

## Features

| Feature | What it does |
|---------|----------------|
| Shared mock engine | One matcher/templating layer for all protocols |
| YAML fixtures | Edit `mocks/*.yaml` — no code changes for responses |
| Hot-reload | Mock files reload automatically (`HOT_RELOAD=0` to disable) |
| Cross-protocol emit | `emit: orders.created` fans out to SSE, WS, MQTT, GraphQL subs |
| Dashboard | `/` — learn + try + inspect |
| Discovery | `GET /api/discovery` — host, ports, example commands |
| Inspector | `GET /api/requests` — last N requests (protocol, IP, route, response) |
| Health | `GET /health` — adapter status |
| GraphQL subscriptions | `graphql-ws` on `/graphql` |
| gRPC all stream types | Unary, server, client, bidirectional |
| JWT | Optional Bearer auth (`AUTH_REQUIRED=1`) |
| TLS / mTLS | Optional HTTPS + client certs (`./scripts/gen-certs.sh`) |
| Docker | `docker compose up --build` |

---

## Protocol cheat sheet

### HTTP — verbs & samples

| Verb | Endpoint | Purpose |
|------|----------|---------|
| GET | `/http/demo` | Verb index / demo |
| GET | `/http/users` | List |
| GET | `/http/users/:id` | Read one |
| POST | `/http/users` | Create |
| POST | `/http/orders` | Create + `emit: orders.created` |
| PUT | `/http/users/:id` | Full replace |
| PATCH | `/http/users/:id` | Partial update |
| DELETE | `/http/users/:id` | Delete |
| HEAD | `/http/users/:id` | Exists check |
| OPTIONS | `/http/users` | Allowed methods |

```bash
curl http://localhost:3000/http/users/42
curl -X POST http://localhost:3000/http/users \
  -H 'Content-Type: application/json' -d '{"name":"Ada","email":"ada@example.com"}'
```

Details: [docs/protocols/http.md](docs/protocols/http.md)

### HTTP Streams (Fetch)

```bash
curl -N http://localhost:3000/http-stream/demo
curl -N http://localhost:3000/http-stream/tokens
./examples/http-stream.sh
```

```js
const res = await fetch('http://localhost:3000/http-stream/demo');
const reader = res.body.getReader();
const decoder = new TextDecoder();
for (;;) {
  const { done, value } = await reader.read();
  if (done) break;
  console.log(decoder.decode(value));
}
```

Details: [docs/protocols/http-stream.md](docs/protocols/http-stream.md)

### WebSocket

```bash
wscat -c ws://localhost:3001/ws/demo
# then: {"action":"ping"}  or  {"action":"subscribe","topic":"orders.created"}
```

Details: [docs/protocols/websocket.md](docs/protocols/websocket.md)

### SSE

```bash
curl -N http://localhost:3000/sse/demo
curl -N http://localhost:3000/sse/orders.created
```

Details: [docs/protocols/sse.md](docs/protocols/sse.md)

### GraphQL — query, mutation, subscription

```bash
curl -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ users { id name } }"}'
```

Open http://localhost:3000/graphql (GraphiQL):

```graphql
subscription { countdown(from: 3) }
subscription { orderCreated { orderId status item } }
mutation { publishOrder(item: "book") { orderId status } }
```

Details: [docs/protocols/graphql.md](docs/protocols/graphql.md)

### gRPC — four RPC styles

| Method | Style |
|--------|-------|
| `Ping` | Unary |
| `StreamPings` | Server streaming |
| `CollectPings` | Client streaming |
| `Chat` | Bidirectional |

```bash
curl http://localhost:3000/grpc/demo
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext -d '{"message":"hello"}' localhost:50051 demo.DemoService/Ping
```

Details: [docs/protocols/grpc.md](docs/protocols/grpc.md)

### MQTT

```bash
mosquitto_sub -h localhost -p 1883 -t 'mqtt/demo/response' -v
mosquitto_pub -h localhost -p 1883 -t mqtt/demo -m '{"message":"hi"}'
```

Details: [docs/protocols/mqtt.md](docs/protocols/mqtt.md)

---

## Custom mocks

| File | Used by |
|------|---------|
| `mocks/http.yaml` | HTTP routes |
| `mocks/http-stream.yaml` | HTTP Streams (Fetch) chunk fixtures |
| `mocks/websocket.yaml` | WebSocket paths |
| `mocks/sse.yaml` | SSE topics |
| `mocks/graphql/schema.graphql` | GraphQL schema |
| `mocks/graphql/routes.yaml` | Field fixtures |
| `mocks/grpc/demo.proto` | gRPC service |
| `mocks/grpc/routes.yaml` | gRPC method fixtures |
| `mocks/mqtt.yaml` | MQTT topics |
| `mocks/config.yaml` | Optional unified overrides (merged on top) |

Example:

```yaml
routes:
  - match: { method: GET, path: /http/users/:id }
    response:
      status: 200
      delayMs: 50
      body:
        id: "{{params.id}}"
        name: Ada
      emit: users.updated   # optional: push to SSE / WS / MQTT / GraphQL subs
```

Templates: `{{params.id}}`, `{{query.x}}`, `{{req.body.name}}`, `{{req.clientIp}}`

---

## External clients

Binds to **`0.0.0.0`** by default. Use your LAN IP (printed at startup, or from discovery):

```bash
curl http://localhost:3000/api/discovery
curl http://192.168.x.x:3000/http/demo
```

| Variable | Purpose |
|----------|---------|
| `HOST` | Listen address (default `0.0.0.0`) |
| `CORS_ORIGINS` | `*` or comma-separated origins |
| `PUBLIC_URL` | Override URLs in discovery behind a proxy |
| `HTTP_PORT` / `WS_PORT` / `GRPC_PORT` / `MQTT_PORT` | Ports |
| `MOCKS_DIR` | Fixture directory |
| `INSPECTOR_MAX` | Request ring-buffer size (default `100`) |
| `HOT_RELOAD` | Set `0` to disable |

---

## Auth & TLS

Full guide: [docs/auth-tls.md](docs/auth-tls.md)

```bash
# JWT required on non-public routes
AUTH_REQUIRED=1 JWT_ENABLED=1 npm start
curl -X POST http://localhost:3000/auth/token \
  -H 'Content-Type: application/json' -d '{"sub":"ada"}'

# HTTPS
./scripts/gen-certs.sh
TLS_ENABLED=1 TLS_CERT=./certs/server.crt TLS_KEY=./certs/server.key npm start

# mTLS
TLS_ENABLED=1 TLS_MTLS=1 TLS_CERT=./certs/server.crt TLS_KEY=./certs/server.key \
  TLS_CA=./certs/ca.crt npm start
```

---

## Docker

```bash
docker compose up --build
```

Exposes app ports `3000`, `3001`, `50051`, `1883` directly (fine for LAN/dev). For internet-facing production, prefer the **nginx VM deploy** below instead of publishing those ports raw.

---

## Production deploy (VM + nginx)

**Not for Vercel/Netlify** (no multi-port TCP). Use a VM:

```bash
sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com
```

| Public | Routes to |
|--------|-----------|
| `https://domain/` `:443` | App `:3000` (HTTP, SSE, GraphQL, dashboard) |
| `wss://domain/ws/` `:443` | App `:3001` (WebSocket) |
| `domain:50051` TLS | App gRPC `:50051` |
| `domain:8883` TLS | App MQTT `:1883` |

Full guide: [docs/production.md](docs/production.md)

---

## Project layout

```
mock_server/
├── src/
│   ├── adapters/          # http, http-stream, websocket, sse, graphql, grpc, mqtt
│   ├── api/               # discovery, health, inspector
│   ├── auth/              # JWT + TLS helpers
│   ├── config/            # env + YAML loader
│   ├── core/              # engine, matcher, bus, hot-reload
│   ├── dashboard/         # UI at /
│   └── index.ts
├── mocks/                 # fixtures
├── deploy/                # VM + nginx production deploy
│   ├── deploy.sh
│   ├── cloud/             # AWS / GCP / Linode VM provisioning
│   ├── nginx/
│   ├── systemd/
│   └── env.production.example
├── docs/protocols/        # learning guides
├── docs/auth-tls.md
├── docs/production.md
├── examples/
├── scripts/gen-certs.sh
├── Dockerfile
└── docker-compose.yml
```

---

## Scripts

```bash
npm run build
npm start
npm run dev
./examples/try-all.sh
./examples/http-verbs.sh
./examples/mqtt-demo.sh
./scripts/gen-certs.sh
sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com
```

---

## Learning path

1. Start the server and open the dashboard  
2. Read [docs/protocols/README.md](docs/protocols/README.md) for the compare table  
3. Work through each protocol guide (summary → try it → references)  
4. Edit a YAML mock and watch hot-reload change the next response  
5. Use `emit` + SSE/WS/MQTT/GraphQL subscription to see cross-protocol events  
6. For internet hosting, follow [docs/production.md](docs/production.md) (nginx on a VM)  
