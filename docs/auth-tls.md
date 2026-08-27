# Auth & TLS

Optional security features for local / external-client testing.

## JWT (Bearer tokens)

Disabled by default. Enable enforcement:

```bash
AUTH_REQUIRED=1 JWT_ENABLED=1 npm start
```

Get a token:

```bash
curl -s -X POST http://localhost:3000/auth/token \
  -H 'Content-Type: application/json' \
  -d '{"sub":"ada","role":"admin"}'
```

Call a protected route:

```bash
TOKEN=... # from access_token
curl http://localhost:3000/http/users \
  -H "Authorization: Bearer $TOKEN"
```

Check token:

```bash
curl http://localhost:3000/auth/me -H "Authorization: Bearer $TOKEN"
```

Public paths (no JWT when `AUTH_REQUIRED=1`): `/`, `/health`, `/api/discovery`, `/auth/token`, `/graphql/demo`, `/http/demo`, `/docs/*`  
Override with `AUTH_PUBLIC_PATHS`.

Env:

| Variable | Default | Meaning |
|----------|---------|---------|
| `JWT_ENABLED` | off | Enable JWT helpers |
| `AUTH_REQUIRED` | off | Require Bearer JWT on non-public routes |
| `JWT_SECRET` | `mock-server-dev-secret-change-me` | HS256 secret |
| `JWT_ISSUER` | `mock-server` | Expected `iss` claim |

## TLS (HTTPS)

```bash
./scripts/gen-certs.sh
TLS_ENABLED=1 \
  TLS_CERT=./certs/server.crt \
  TLS_KEY=./certs/server.key \
  npm start
```

Then open `https://localhost:3000/` (accept the self-signed warning).

## mTLS (client certificates)

```bash
TLS_ENABLED=1 TLS_MTLS=1 \
  TLS_CERT=./certs/server.crt \
  TLS_KEY=./certs/server.key \
  TLS_CA=./certs/ca.crt \
  npm start
```

Client example:

```bash
curl --cacert ./certs/ca.crt \
  --cert ./certs/client.crt \
  --key ./certs/client.key \
  https://localhost:3000/http/demo
```

gRPC uses the same cert env vars when TLS is enabled.

## Learn more

| Resource | Link |
|----------|------|
| JWT introduction | https://jwt.io/introduction |
| MDN — Transport Layer Security | https://developer.mozilla.org/en-US/docs/Web/Security/Transport_Layer_Security |
| RFC 8446 — TLS 1.3 | https://www.rfc-editor.org/rfc/rfc8446 |
| mTLS overview (Cloudflare) | https://www.cloudflare.com/learning/access-management/what-is-mutual-tls/ |
