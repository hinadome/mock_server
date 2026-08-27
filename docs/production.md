# Production deployment (VM + nginx)

> Prefer the unified guide: **[DEPLOYMENT.md](../DEPLOYMENT.md)** (VM + Container).

This mock server is **not** a fit for Vercel/Netlify multi-port hosting. For production, run it on a **VM or container host** with **nginx** as the public frontend.

**Container path (Compose gateway):** `./deploy/container/deploy.sh --domain api.example.com`

## Well-known / practical public ports

| Protocol | Typical public port | How clients connect | This deploy |
|----------|---------------------|---------------------|-------------|
| HTTP / SSE / GraphQL / HTTP Streams | **443** | `https://host/...` | nginx → `127.0.0.1:3000` |
| WebSocket | **443** | `wss://host/ws/...` | nginx `/ws/` → `127.0.0.1:3001` |
| GraphQL subscriptions | **443** | `wss` on `/graphql` | nginx → `3000` (upgrade) |
| gRPC | **50051** (or **443** with `grpc_pass`) | `host:50051` TLS | nginx TLS → `127.0.0.1:50051` |
| MQTT cleartext | **1883** | TCP | optional; often firewalled |
| MQTT TLS | **8883** | TCP+TLS | nginx `stream` → `127.0.0.1:1883` |

Internal app ports stay `3000` / `3001` / `50051` / `1883` on **localhost only**. Clients never hit those ports directly.

```
Internet
   │
   ├─ :443  ── nginx ── /              → 127.0.0.1:3000   (HTTP, GraphQL, dashboard)
   │                  /sse/           → 127.0.0.1:3000   (SSE, buffering off)
   │                  /http-stream/   → 127.0.0.1:3000   (Fetch streams, buffering off)
   │                  /ws/            → 127.0.0.1:3001   (WebSocket)
   │                  /graphql        → 127.0.0.1:3000   (HTTP + graphql-ws)
   ├─ :50051 ─ nginx grpc_pass → 127.0.0.1:50051
   └─ :8883  ─ nginx stream   → 127.0.0.1:1883   (MQTT TLS)
```

## Deploy on Ubuntu/Debian VM

**Requirements:** DNS A/AAAA record for your domain → VM public IP; ports 80/443 (and 50051, 8883) open.

### Option A — provision VM on a cloud, then deploy

| Cloud | Create VM script |
|-------|------------------|
| AWS | [`deploy/cloud/aws-create-vm.sh`](../deploy/cloud/aws-create-vm.sh) |
| Google Cloud | [`deploy/cloud/gcp-create-vm.sh`](../deploy/cloud/gcp-create-vm.sh) |
| Linode | [`deploy/cloud/linode-create-vm.sh`](../deploy/cloud/linode-create-vm.sh) |

```bash
# AWS example (creates EC2, waits for SSH, runs deploy/deploy.sh)
./deploy/cloud/aws-create-vm.sh \
  --domain api.example.com \
  --key-name my-ec2-keypair \
  --ssh-key ~/.ssh/my-ec2-keypair.pem \
  --email you@example.com \
  --deploy
```

Full cloud guide: [`deploy/cloud/README.md`](../deploy/cloud/README.md)

### Option B — you already have a VM

```bash
# On the VM
git clone <your-repo-url> mock_server
cd mock_server
sudo ./deploy/deploy.sh --domain api.example.com --email you@example.com
```

Flags:

| Flag | Meaning |
|------|---------|
| `--domain` | Required public hostname |
| `--email` | Let's Encrypt registration email |
| `--skip-certbot` | Never call certbot |
| `--force-certbot` | Request/reissue even if a cert already exists |
| `--enable-ufw` | Add allow rules only if UFW is already active (never force-enables UFW) |
| `--mqtt-cleartext` | Also expose public TCP 1883 (off by default) |
| `--remove-default-site` | Remove stock `sites-enabled/default` only |

## Repeatable deploys (safe re-runs)

`deploy/deploy.sh` is safe to run many times for upgrades **without wiping other nginx apps**:

| Behavior | Detail |
|----------|--------|
| Owns only its files | `sites-*/mock-server.conf`, `streams-enabled/mock-server-mqtt*.conf`, `/opt/mock-server`, systemd unit |
| Preserves env | `.env.production` is excluded from `rsync --delete` |
| Preserves other sites | Does not delete unrelated `sites-enabled/*` |
| Default site | Left alone unless `--remove-default-site` |
| Certbot | Uses **webroot** (not `--nginx` rewriter); skipped if LE cert already exists |
| TLS files | `/etc/nginx/ssl/mock-server` — never writes into `/etc/letsencrypt/live` |
| UFW | Does not run `ufw --force enable` |
| Backups | Previous mock-server nginx files → `/var/backups/mock-server/` |
| MQTT :1883 | Off by default (avoids clashing with other brokers) |

```bash
sudo ./deploy/deploy.sh --domain api.example.com
```

The script installs Node 20 (if needed), nginx, certbot; builds the app to `/opt/mock-server`; enables systemd; refreshes **only** mock-server nginx files.

## Files

| Path | Role |
|------|------|
| [`deploy/deploy.sh`](../deploy/deploy.sh) | Idempotent VM installer / upgrader |
| [`deploy/validate.sh`](../deploy/validate.sh) | Post-deploy smoke tests (incl. HTTP Streams) |
| [`deploy/nginx/mock-server.conf`](../deploy/nginx/mock-server.conf) | HTTPS + WS + HTTP Streams + gRPC site |
| [`deploy/nginx/mqtt-stream.conf`](../deploy/nginx/mqtt-stream.conf) | MQTT TLS stream (:8883) |
| [`deploy/nginx/mqtt-stream-cleartext.conf`](../deploy/nginx/mqtt-stream-cleartext.conf) | Optional MQTT :1883 |
| [`deploy/systemd/mock-server.service`](../deploy/systemd/mock-server.service) | App unit |
| [`deploy/env.production.example`](../deploy/env.production.example) | Env template → `/opt/mock-server/.env.production` |

## After deploy — smoke tests

```bash
# Local app (on the VM) or public URL
./deploy/validate.sh --base http://127.0.0.1:3000
./deploy/validate.sh --base https://api.example.com
# self-signed: ./deploy/validate.sh --base https://api.example.com --insecure

curl -sS https://api.example.com/health
curl -sS https://api.example.com/http/demo
curl -sS -N https://api.example.com/http-stream/demo   # Fetch / NDJSON chunks
wscat -c wss://api.example.com/ws/demo

grpcurl api.example.com:50051 list   # TLS — may need -cacert if using staging LE

mosquitto_sub -h api.example.com -p 8883 \
  --cafile /etc/ssl/certs/ca-certificates.crt \
  -t 'mqtt/demo/response' -v
```

`deploy/validate.sh` checks health, HTTP, discovery (`httpStream`), HTTP Streams chunk delivery / TTFB (buffering), and SSE.
## Operations

```bash
systemctl status mock-server
journalctl -u mock-server -f
systemctl restart mock-server

nginx -t && systemctl reload nginx
certbot renew --dry-run
```

Edit env: `/opt/mock-server/.env.production` then `systemctl restart mock-server`.

## Why not Vercel / Netlify?

Those platforms expose **HTTPS :443 only** and run serverless functions — not long-lived TCP listeners for MQTT, native gRPC `:50051`, or a separate WS process port. Use a VM, Fly.io, Railway, Render, or similar for this architecture.

## Security notes

- App binds `127.0.0.1` — only nginx is public
- Prefer **8883** for MQTT; leave **1883** closed on the firewall unless required
- Set a strong `JWT_SECRET` and optionally `AUTH_REQUIRED=1`
- Keep OS packages and certbot renewals enabled (`certbot.timer`)
