# Deployment

Multi-protocol **mock-server** production deploy uses **nginx as the HTTPS FrontendGateway**.  
**VM** and **Container** paths are separate scripts so one never rewrites the other’s host.

Short index: [`deploy/README.md`](deploy/README.md)

## Overview

```
Clients
   │
   ├─ VM path:        host nginx  →  systemd app on 127.0.0.1:*
   └─ Container path: Compose nginx gateway container  →  app container (private network)
```

| Concern | VM (`deploy/deploy.sh`) | Container (`deploy/container/deploy.sh`) |
|---------|-------------------------|------------------------------------------|
| Gateway | Host nginx site files | nginx service in Compose |
| App | `/opt/mock-server` + systemd | `app` service image |
| Host nginx | Updates **only** mock-server-owned files | **Never** touches host nginx |
| Certs | `/etc/nginx/ssl/mock-server` (reuse LE) | `deploy/container/certs/` (reuse; no overwrite) |

## Prerequisites

**Shared:** DNS A/AAAA for your domain (production), open firewall ports as needed.

**VM:** Ubuntu/Debian, root/`sudo`, `rsync`, Node 20 (installed by script).

**Container:** Docker Engine + Compose plugin, `openssl`, ability to bind host ports `80`/`443`/`50051`/`8883`.

## Architecture / ports

| Public (gateway) | Protocol | Upstream (app) |
|------------------|----------|----------------|
| `443` | HTTPS, WSS `/ws/`, SSE, HTTP Streams, GraphQL | `:3000` / `:3001` |
| `80` | ACME + redirect → HTTPS | — |
| `50051` | gRPC TLS | `:50051` |
| `8883` | MQTT TLS | `:1883` |
| `1883` | MQTT cleartext (opt-in) | `:1883` |

App binds **localhost** on VM, or **private Compose network** on Container — not published directly when nginx is the gateway.

---

## VM deployment

Script: [`deploy/deploy.sh`](deploy/deploy.sh)  
Configs: [`deploy/nginx/`](deploy/nginx/), [`deploy/systemd/`](deploy/systemd/)

### First-time install

```bash
# Optional: verify app on HTTP before certificates
sudo ./deploy/deploy.sh --domain api.example.com --no-tls

sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com
```

### Repeatable upgrade (re-run)

```bash
sudo ./deploy/deploy.sh --domain api.example.com
```

### Script flags

| Flag | Meaning |
|------|---------|
| `--domain` | Required vhost name |
| `--no-tls` | HTTP-only verify (no certs / certbot) |
| `--email` | Let's Encrypt contact |
| `--skip-certbot` / `--force-certbot` | Certbot control |
| `--mqtt-cleartext` | Publish host `:1883` (implied by `--no-tls`) |
| `--enable-ufw` | Add UFW allows only if UFW already active |
| `--remove-default-site` | Opt-in remove stock `default` site |

### Files this deploy owns

- `/opt/mock-server` (preserves `.env.production` across rsync)
- `/etc/nginx/sites-available/mock-server` (+ `sites-enabled` symlink)
- `/etc/nginx/streams-enabled/mock-server-mqtt*.conf`
- `/etc/nginx/ssl/mock-server/`
- `systemd` unit `mock-server.service`
- backups under `/var/backups/mock-server/`

### What this deploy will NOT touch

- Other `sites-enabled/*` (never `rm` foreign sites)
- Foreign stream configs
- Existing Let's Encrypt material under `/etc/letsencrypt/live` (symlinked, not overwritten)
- Does not `ufw --force enable`

Cloud VM helpers: [`deploy/cloud/README.md`](deploy/cloud/README.md)

---

## Container deployment

Script: [`deploy/container/deploy.sh`](deploy/container/deploy.sh)  
Compose: [`deploy/container/docker-compose.yml`](deploy/container/docker-compose.yml)  
Gateway nginx: [`deploy/container/nginx/`](deploy/container/nginx/)

### First-time install

```bash
# Optional: verify on HTTP before certificates
./deploy/container/deploy.sh --domain api.example.com --no-tls

./deploy/container/deploy.sh --domain api.example.com
```

Creates (if missing):

- `deploy/container/.env.production`
- Self-signed PEMs in `deploy/container/certs/` **only when certs are absent**
- Rendered configs under `deploy/container/nginx/runtime/`

Starts **app** + **gateway** (nginx). App ports are **not** published on the host; only the gateway is.

### Repeatable upgrade (re-run)

```bash
./deploy/container/deploy.sh --domain api.example.com
# faster restart without rebuild:
./deploy/container/deploy.sh --domain api.example.com --no-build
```

### Script flags

| Flag | Meaning |
|------|---------|
| `--domain` | Required (TLS CN / `PUBLIC_URL`) |
| `--no-tls` | HTTP-only verify (no certs / HTTPS) |
| `--env FILE` | Alternate env file |
| `--force-certs` | Replace certs (default: **reuse**; ignored with `--no-tls`) |
| `--mqtt-cleartext` | Also publish host `:1883` (implied by `--no-tls`) |
| `--skip-validate` | Skip smoke tests |
| `--no-build` | `compose up` without `--build` |
| `--down` | Stop **this** Compose project only |

### Volumes and certificates

| Path | Role |
|------|------|
| `deploy/container/certs/fullchain.pem` | Gateway TLS cert (reused if present) |
| `deploy/container/certs/privkey.pem` | Gateway TLS key (reused if present) |
| `deploy/container/.env.production` | App secrets/env (created once; not wiped) |
| `deploy/container/nginx/runtime/` | Generated nginx conf (owned by this deploy) |

To use real certs: copy PEMs into `certs/`, then re-run **without** `--force-certs`.

### What this deploy will NOT touch

- Host `/etc/nginx`, `sites-enabled`, or any host nginx process
- Other Docker Compose projects
- Existing files in `certs/` (unless `--force-certs`)

### Stop

```bash
./deploy/container/deploy.sh --down
```

---

## HTTPS and certificates

**Policy (both paths):** if usable cert files already exist → **use them; do not override**.

### Verify without certificates first (`--no-tls`)

Both scripts support **HTTP-only verify mode** so you can exercise the app and gateway before creating or installing TLS certs:

```bash
# VM
sudo ./deploy/deploy.sh --domain api.example.com --no-tls

# Container
./deploy/container/deploy.sh --domain api.example.com --no-tls

# Smoke (plain HTTP)
./deploy/validate.sh --base http://api.example.com
# or locally through gateway:
./deploy/validate.sh --base http://127.0.0.1
```

| With `--no-tls` | Behavior |
|-----------------|----------|
| Certificates | **Not** created or required |
| Certbot / openssl self-signed | Skipped |
| HTTP | `:80` (dashboard, REST, SSE, HTTP Streams, GraphQL, `/ws/`) |
| gRPC | Cleartext `:50051` |
| MQTT | Cleartext `:1883` |
| HTTPS / MQTT TLS | Not configured |

When ready for TLS, re-run **without** `--no-tls` (existing `.env.production` secrets are kept; `PUBLIC_URL` is switched to `https://`):

```bash
sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com
./deploy/container/deploy.sh --domain api.example.com
```

| Path | Location | Create when missing | Force reissue |
|------|----------|---------------------|---------------|
| VM | `/etc/nginx/ssl/mock-server` (+ LE live via symlink) | self-signed or certbot webroot | `--force-certbot` |
| Container | `deploy/container/certs/` | self-signed via openssl | `--force-certs` |

VM certbot uses **webroot**, not `certbot --nginx`, so other vhosts are not rewritten.

---

## Coexistence

- **VM:** only named mock-server site/stream files; backups before overwrite; `nginx -t` before reload.
- **Container:** isolated Compose project `mock-server`; no host nginx edits.

---

## Operations

### Smoke tests (includes HTTP Streams)

```bash
# Against VM app locally
./deploy/validate.sh --base http://127.0.0.1:3000

# Against public / container gateway
./deploy/validate.sh --base https://api.example.com --insecure

curl -sS -N https://api.example.com/http-stream/demo
```

`validate.sh` checks `/health`, `/http/demo`, discovery (`httpStream`), `/http-stream/demo` (chunks + TTFB), `/sse/demo`.

### VM ops

```bash
systemctl status mock-server
journalctl -u mock-server -f
nginx -t && systemctl reload nginx
```

### Container ops

```bash
cd deploy/container
docker compose ps
docker compose logs -f gateway app
docker compose restart gateway
```

### Rollback

- **VM:** restore nginx files from `/var/backups/mock-server/`; redeploy previous git revision.
- **Container:** `docker compose down` then redeploy previous image/tag; certs/env on disk remain.

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| HTTP Streams arrive all at once | nginx must `proxy_buffering off` on `/http-stream/` (both VM + container configs) |
| Container validate fails on HTTPS | Use `--insecure` with self-signed; ensure ports 80/443 free |
| gRPC / MQTT unreachable | Open `50051` / `8883`; confirm gateway published ports |
| Env secrets missing after upgrade | Both scripts preserve `.env.production` by design |

---

## Security notes

- Prefer production PEMs over self-signed.
- Keep `.env.production` mode `600`; do not commit it.
- Prefer MQTT **8883** over cleartext **1883**.
- Container: do not publish app ports `3000`/`3001` on the host when using the gateway.
- VM: app binds `127.0.0.1` so only nginx is public.

---

## Related

- Protocol guides: [`docs/protocols/`](docs/protocols/)
- HTTP Streams: [`docs/protocols/http-stream.md`](docs/protocols/http-stream.md)
- Auth / TLS app options: [`docs/auth-tls.md`](docs/auth-tls.md)
- Legacy VM-focused notes: [`docs/production.md`](docs/production.md)
