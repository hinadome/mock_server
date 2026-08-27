# HTTP / REST

## Summary (learn this first)

**HTTP** (Hypertext Transfer Protocol) is the request/response protocol of the web. A client opens a short-lived connection, sends one request (method + URL + optional body), and the server returns one response (status + headers + body). Keep-alive may reuse the TCP connection for the next request.

**REST** is a common *style* of HTTP API design: resources are URLs (e.g. `/http/users/42`), and HTTP verbs describe the action.

| Idea | Meaning |
|------|---------|
| Stateless | Each request carries what the server needs |
| Verbs | Method = intent; status codes (`200`, `201`, `404`) = outcome |
| Best for | CRUD APIs, form submits, public web APIs, simple integrations |
| Not ideal for | Continuous live updates (prefer SSE/WebSocket) or IoT pub/sub (prefer MQTT) |

**Compared to others on this server:** HTTP is pull-based. SSE/WebSocket/MQTT push. GraphQL also uses HTTP but lets the client pick fields. gRPC is RPC over HTTP/2 with binary protobuf.

## How a request works

```
Client                         Server
  |  GET /http/users/42          |
  |----------------------------->|
  |  200 { id, name, email }     |
  |<-----------------------------|
```

## On this server

| Item | Value |
|------|-------|
| Port | `3000` (same process as SSE, GraphQL, dashboard) |
| Path pattern | `/http/{name}` |
| Demo index | `GET /http/demo` |
| Mock file | [`mocks/http.yaml`](../../mocks/http.yaml) |
| CORS | Enabled (`CORS_ORIGINS`, default `*`) |
| Auth | Optional JWT — see [auth-tls.md](../auth-tls.md) |

## Built-in sample endpoints

| Verb | Path | What it returns |
|------|------|-----------------|
| GET | `/http/demo` | Verb index + protocol explainer |
| GET | `/http/users` | User list |
| GET | `/http/users/:id` | One user (`{{params.id}}`) |
| POST | `/http/users` | Created user from body |
| POST | `/http/orders` | Order + **`emit: orders.created`** (cross-protocol) |
| PUT | `/http/users/:id` | Full replace |
| PATCH | `/http/users/:id` | Partial update |
| DELETE | `/http/users/:id` | `{ deleted: true }` |
| HEAD | `/http/users/:id` | Headers only (`X-User-Id`, …) |
| OPTIONS | `/http/users` | `Allow` / CORS methods |

## Try it

```bash
curl http://localhost:3000/http/demo
curl http://localhost:3000/http/users
curl http://localhost:3000/http/users/42

curl -X POST http://localhost:3000/http/users \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada","email":"ada@example.com"}'

curl -X PUT http://localhost:3000/http/users/42 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada Lovelace","email":"ada@example.com"}'

curl -X PATCH http://localhost:3000/http/users/42 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Augusta Ada"}'

curl -X DELETE http://localhost:3000/http/users/42
curl -I http://localhost:3000/http/users/42
curl -X OPTIONS http://localhost:3000/http/users -D - -o /dev/null
```

Full suite: `./examples/http-verbs.sh`

## Mock configuration

```yaml
# mocks/http.yaml
routes:
  - match: { method: GET, path: /http/users/:id }
    response:
      status: 200
      delayMs: 100
      headers:
        X-Mock: "true"
      body:
        id: "{{params.id}}"
        name: "{{req.body.name}}"
      emit: users.updated   # optional fan-out
```

Supported templates: `{{params.*}}`, `{{query.*}}`, `{{req.body.*}}`, `{{req.clientIp}}`.

## Common mistakes

- Browser CORS errors → set `CORS_ORIGINS`
- Phone/CI using `localhost` → use LAN IP from `/api/discovery`
- Confusing PUT (replace) with PATCH (partial)
- Expecting live push over plain HTTP → use SSE or WebSocket

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [MDN — HTTP overview](https://developer.mozilla.org/en-US/docs/Web/HTTP/Overview) | Beginner-friendly intro |
| [MDN — HTTP request methods](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Methods) | GET, POST, PUT, PATCH, DELETE |
| [MDN — HTTP status codes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status) | `200`, `201`, `404`, `500` |
| [RFC 9110 — HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html) | Official standard |
| [Fielding — REST (Ch. 5)](https://ics.uci.edu/~fielding/pubs/dissertation/rest_arch_style.htm) | Original REST style |
| [restfulapi.net](https://restfulapi.net/) | Practical REST patterns |
