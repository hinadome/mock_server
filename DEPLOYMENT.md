# Deployment

Production deploy for multi-protocol **mock-server**: **nginx** is the HTTPS FrontendGateway.  
**VM** and **Container** use separate scripts so one never rewrites the other’s host.

Index: [`deploy/README.md`](deploy/README.md)

## Overview

```
Clients
   │
   ├─ VM:        host nginx  →  systemd app on 127.0.0.1:*
   └─ Container: Compose nginx gateway  →  app (private network)
```

| | VM (`deploy/deploy.sh`) | Container (`deploy/container/deploy.sh`) |
|--|-------------------------|------------------------------------------|
| Gateway | Host nginx site files | nginx service in Compose |
| App | `/opt/mock-server` + systemd | `app` service image |
| Host nginx | Only mock-server-owned files | Never touched |
| TLS | Self-signed **or** Certbot → `/etc/nginx/ssl/mock-server` | Self-signed **or** Certbot → `deploy/container/certs/` |

**Typical flow:** `--no-tls` to verify → then `--self-signed` or `--certbot` for HTTPS.

## Prerequisites

| | Requirements |
|--|--------------|
| Shared | DNS A/AAAA for the domain; firewall open for the ports you publish |
| VM | Ubuntu/Debian, `sudo`, `rsync`; Node 22 installed by the script |
| Container | Docker Engine + Compose; bind host `80` / `443` / `50051` / `8883` |

## Architecture / ports

| Public (gateway) | Protocol | Upstream (app) |
|------------------|----------|----------------|
| `443` | HTTPS, WSS `/ws/`, SSE, HTTP Streams, GraphQL | `:3000` / `:3001` |
| `80` | ACME + redirect → HTTPS *(or HTTP-only with `--no-tls`)* | `:3000` / `:3001` |
| `50051` | gRPC TLS / cleartext | VM: `127.0.0.1:15051` · Container: private `50051` |
| `8883` | MQTT TLS | VM: `127.0.0.1:11883` · Container: private `1883` |
| `1883` | MQTT cleartext (`--no-tls` / `--mqtt-cleartext`) | Same MQTT upstream as above |

**Port collision (VM):** nginx publishes `50051` / `1883` on the host, so the app must use different internal ports (`GRPC_PORT=15051`, `MQTT_PORT=11883`). Compose keeps app ports on the private network only — no host conflict.

---

## VM deployment

Script: [`deploy/deploy.sh`](deploy/deploy.sh) · Configs: [`deploy/nginx/`](deploy/nginx/), [`deploy/systemd/`](deploy/systemd/)

### Install

```bash
# 1) Optional: verify on HTTP (no certificates)
sudo ./deploy/deploy.sh --domain api.example.com --no-tls

# 2a) HTTPS — Let's Encrypt (default when TLS is on)
sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com
# same as: ... --certbot --email you@example.com

# 2b) HTTPS — self-signed (no ACME / public DNS required)
sudo ./deploy/deploy.sh --domain api.example.com --self-signed
```

### Re-run / upgrade

```bash
sudo ./deploy/deploy.sh --domain api.example.com
```

### Flags

| Flag | Meaning |
|------|---------|
| `--domain` | Required vhost name |
| `--no-tls` | HTTP-only verify (no certs) |
| `--certbot` | Let's Encrypt webroot (default TLS path) |
| `--self-signed` / `--force-self-signed` | openssl PEMs in `/etc/nginx/ssl/mock-server` |
| `--email` | Let's Encrypt contact |
| `--skip-certbot` | Alias for `--self-signed` |
| `--force-certbot` | Re-issue LE even if a cert exists |
| `--mqtt-cleartext` | Publish host `:1883` (implied by `--no-tls`) |
| `--enable-ufw` | UFW allows only if UFW is already active |
| `--remove-default-site` | Opt-in remove stock `default` site |

### Owned files

- `/opt/mock-server` (keeps `.env.production` across rsync)
- `/etc/nginx/sites-available/mock-server` (+ `sites-enabled` symlink)
- `/etc/nginx/streams-enabled/mock-server-mqtt*.conf`
- `/etc/nginx/ssl/mock-server/`
- systemd unit `mock-server.service`
- backups under `/var/backups/mock-server/`

### Will not touch

Other `sites-enabled/*` or foreign stream configs · LE files under `/etc/letsencrypt/live` (symlinked, not overwritten) · does not `ufw --force enable`

Cloud helpers: [`deploy/cloud/README.md`](deploy/cloud/README.md)

---

## Container deployment

Script: [`deploy/container/deploy.sh`](deploy/container/deploy.sh) · Compose: [`deploy/container/docker-compose.yml`](deploy/container/docker-compose.yml) · Gateway: [`deploy/container/nginx/`](deploy/container/nginx/)

### Install

```bash
# 1) Optional: verify on HTTP (no certificates)
./deploy/container/deploy.sh --domain api.example.com --no-tls

# 2a) HTTPS — self-signed (default when TLS is on)
./deploy/container/deploy.sh --domain api.example.com --self-signed

# 2b) HTTPS — Let's Encrypt (public DNS → :80)
./deploy/container/deploy.sh --domain api.example.com --certbot --email you@example.com
```

Creates if missing: `.env.production`, certs under `certs/` (when TLS), rendered nginx under `nginx/runtime/`.  
Starts **app** + **gateway**; only gateway ports are published on the host.

### Re-run / upgrade

```bash
./deploy/container/deploy.sh --domain api.example.com
./deploy/container/deploy.sh --domain api.example.com --no-build   # skip image rebuild
./deploy/container/deploy.sh --down                                 # stop this project only
```

### Flags

| Flag | Meaning |
|------|---------|
| `--domain` | Required (TLS CN / `PUBLIC_URL`) |
| `--no-tls` | HTTP-only verify (no certs) |
| `--self-signed` | openssl self-signed (**default** TLS) |
| `--force-self-signed` | Replace self-signed (alias `--force-certs`) |
| `--certbot` | Let's Encrypt webroot (needs public DNS → `:80`) |
| `--email` | Let's Encrypt contact |
| `--env FILE` | Alternate env file |
| `--mqtt-cleartext` | Also publish host `:1883` (implied by `--no-tls`) |
| `--skip-validate` | Skip smoke tests |
| `--no-build` | `compose up` without `--build` |
| `--down` | Stop this Compose project only |

### Volumes

| Path | Role |
|------|------|
| `deploy/container/certs/*.pem` | Gateway TLS (reused in the same mode) |
| `deploy/container/.env.production` | Secrets (created once; not wiped) |
| `deploy/container/nginx/runtime/` | Generated nginx conf |

Bring your own PEMs: copy into `certs/`, then re-run without `--force-self-signed`.

### Will not touch

Host `/etc/nginx` · other Compose projects · certs unless `--force-self-signed` or a Certbot/self-signed **mode switch**

---

## HTTPS and certificates

Same-mode re-runs **reuse** existing certs. Override only with `--force-self-signed` / `--force-certbot`, or by **switching mode** (below).

### Modes at a glance

| Mode | VM | Container |
|------|----|-----------|
| Certbot | Default TLS: `--email` (or `--certbot`) | `--certbot --email` |
| Self-signed | `--self-signed` | Default TLS: `--self-signed` |
| Force rotate | `--force-self-signed` / `--force-certbot` | `--force-self-signed` / re-run `--certbot` |
| No TLS | `--no-tls` | `--no-tls` |

Validate self-signed with: `./deploy/validate.sh --base https://api.example.com --insecure`

### `--no-tls` (verify before certs)

| | Behavior |
|--|----------|
| Certificates | Not created or required |
| `:80` | Dashboard, REST, SSE, HTTP Streams, GraphQL, `/ws/` |
| `:50051` / `:1883` | Cleartext gRPC / MQTT |
| HTTPS / MQTT TLS | Off |

When ready for TLS, re-run **without** `--no-tls` (`.env.production` kept; `PUBLIC_URL` → `https://`). Use `--self-signed` or `--certbot` as above.

### Switching self-signed ↔ Certbot

| Prior | Next | Result |
|-------|------|--------|
| Self-signed | `--certbot` | On success, gateway PEMs become Let's Encrypt |
| Let's Encrypt | `--self-signed` | Gateway PEMs replaced with new self-signed (LE left on disk unused) |
| Same mode again | same flag | Keep existing (use `--force-*` to rotate) |

Source marker: VM `/etc/nginx/ssl/mock-server/.tls-source` · Container `deploy/container/certs/.tls-source`

| | Cert location |
|--|---------------|
| VM | `/etc/nginx/ssl/mock-server` (LE via symlink from `/etc/letsencrypt/live`) |
| Container | `deploy/container/certs/` |

VM Certbot uses **webroot**, not `certbot --nginx`, so other vhosts are not rewritten.

---

## Coexistence

- **VM:** only named mock-server site/stream files; backup before overwrite; `nginx -t` before reload  
- **Container:** Compose project `mock-server` only; no host nginx edits  

---

## Operations

### Smoke tests

```bash
./deploy/validate.sh --base http://127.0.0.1:3000          # app direct (VM)
./deploy/validate.sh --base https://api.example.com --insecure
curl -sS -N https://api.example.com/http-stream/demo
```

Checks `/health`, `/http/demo`, discovery (`httpStream`), `/http-stream/demo`, `/sse/demo`.

### VM

```bash
systemctl status mock-server
journalctl -u mock-server -f
nginx -t && systemctl reload nginx
```

### Container

```bash
cd deploy/container
docker compose ps
docker compose logs -f gateway app
docker compose restart gateway
```

### Rollback

- **VM:** restore from `/var/backups/mock-server/`; redeploy a previous git revision  
- **Container:** `docker compose down`, redeploy previous image/tag; certs/env on disk remain  

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| HTTP Streams arrive all at once | `proxy_buffering off` on `/http-stream/` (VM + container nginx) |
| HTTPS validate fails (self-signed) | Pass `--insecure`; ensure `80`/`443` free |
| gRPC / MQTT unreachable | Open `50051` / `8883`; confirm gateway published ports |
| Secrets missing after upgrade | Both scripts preserve `.env.production` |
| `ngx_stream_module is already loaded` | Ubuntu loads stream via `modules-enabled`. Re-run deploy (scrubs duplicate `load_module`) or remove it from `nginx.conf`, then `nginx -t`. Container Alpine is unaffected. |
| `no port in upstream "mock_mqtt"` | Need shared upstream: sync deploy (`mqtt-stream-upstream.conf`) or add `upstream mock_mqtt { server 127.0.0.1:11883; }` under `streams-enabled/`, then `nginx -t` |
| validate `rc=7` / refused on `:3000` | App crashed from port clash with nginx. Set `MQTT_PORT=11883` `GRPC_PORT=15051`, restart, check `journalctl -u mock-server -e` |
| `graphql` EBADENGINE on Node 20 | Use Node 22+ (VM install / `Dockerfile` use `node:22-alpine`) |

---

## Security notes

- Prefer production / Certbot PEMs over self-signed for public hosts  
- Keep `.env.production` mode `600`; do not commit it  
- Prefer MQTT **8883** over cleartext **1883**  
- Container: do not publish app `3000`/`3001` on the host when using the gateway  
- VM: app binds `127.0.0.1`; only nginx is public  

---

## Related

- Protocols: [`docs/protocols/`](docs/protocols/) · HTTP Streams: [`docs/protocols/http-stream.md`](docs/protocols/http-stream.md)  
- Auth / TLS app options: [`docs/auth-tls.md`](docs/auth-tls.md)  
- Legacy VM notes: [`docs/production.md`](docs/production.md)  
