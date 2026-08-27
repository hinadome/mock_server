# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-08-26

Initial multi-protocol mock server release: protocols, DX surfaces, auth/TLS options, and VM + container deployment.

### Added

#### Core platform
- Shared mock engine (match → delay → template → emit → inspect)
- YAML fixtures under `mocks/` with Zod validation and hot-reload (`HOT_RELOAD=0` to disable)
- Cross-protocol event bus (`emit`) fanning out to SSE, WebSocket, MQTT, and GraphQL subscriptions
- Path convention `/{protocol}/{name}` for HTTP-facing demos
- Dashboard at `/` with protocol cards, examples, and live inspector
- Discovery API (`GET /api/discovery`), request inspector (`GET /api/requests`), health (`GET /health`)
- Docker image + root `docker-compose.yml` for local multi-port runs
- Example scripts: `examples/try-all.sh`, `http-verbs.sh`, `mqtt-demo.sh`, `http-stream.sh`

#### Protocols
- **HTTP / REST** — CRUD samples, full verb coverage (`mocks/http.yaml`, `docs/protocols/http.md`)
- **HTTP Streams (Fetch)** — chunked NDJSON / text bodies for `fetch().body.getReader()` at `/http-stream/{name}` (`src/adapters/http-stream.ts`, `mocks/http-stream.yaml`, `docs/protocols/http-stream.md`)
  - Demo, tokens, and live bus topics; `chunkDelayMs` / `keepOpen` fixture options
- **WebSocket** — standalone server on `:3001`, path `/ws/{name}`, subscribe/ping demos
- **SSE** — `/sse/{topic}` with demo stream and bus fan-in
- **GraphQL** — queries/mutations + GraphiQL; subscriptions via `graphql-ws` on `/graphql`
- **gRPC** — unary, server/client/bidi streaming, reflection; HTTP helpers on `/grpc/*`
- **MQTT** — Aedes broker on `:1883`, topic demos and bus bridge

#### Security options
- Optional JWT Bearer auth (`AUTH_REQUIRED`, `JWT_*`, `POST /auth/token`)
- Optional app TLS / mTLS (`TLS_*`, `scripts/gen-certs.sh`)
- Auth & TLS guide: `docs/auth-tls.md`

#### Deployment — VM
- Idempotent `deploy/deploy.sh` (host nginx + systemd; owns only mock-server files)
- Certificate reuse (no override of existing LE/app certs); certbot webroot (not `--nginx`)
- nginx site for HTTPS, WSS `/ws/`, SSE, HTTP Streams (`proxy_buffering off`), gRPC TLS, MQTT TLS stream
- `--no-tls` HTTP-only verify mode (no certs/certbot; `:80` + cleartext gRPC/MQTT) before enabling TLS
- `deploy/validate.sh` smoke tests (health, HTTP, discovery/`httpStream`, stream TTFB, SSE)
- Cloud VM helpers: AWS / GCP / Linode create + image/machine-type list scripts (`deploy/cloud/`)

#### Deployment — Container
- Separate Compose stack: `deploy/container/deploy.sh` + `docker-compose.yml`
- nginx FrontendGateway in Compose (does **not** edit host nginx)
- Cert reuse under `deploy/container/certs/`; `--force-certs` only when explicit
- `--no-tls` HTTP-only verify path with HTTP gateway templates
- Env preservation (`.env.production`); upgrade from `--no-tls` to TLS without wiping secrets

#### Documentation
- Root [`DEPLOYMENT.md`](DEPLOYMENT.md) — VM vs container, ports, certs, `--no-tls`, ops
- [`deploy/README.md`](deploy/README.md) index
- Protocol learning guides under `docs/protocols/`
- Production notes in `docs/production.md`

### Notes
- Intended primarily for local/lab learning and integration mocks. Production exposure should enable JWT, bind the app behind nginx (`HOST=127.0.0.1` on VM), avoid open MQTT, and treat `--no-tls` as temporary verify-only.
- Personal Cursor skill `deployment-scripts` documents the VM/container/`--no-tls`/`DEPLOYMENT.md` conventions used here.
