# Deploy layouts

Full documentation: **[../DEPLOYMENT.md](../DEPLOYMENT.md)**

| Path | Purpose |
|------|---------|
| [`deploy.sh`](./deploy.sh) | **VM** — host nginx + systemd (idempotent); `--no-tls` to verify without certs |
| [`container/deploy.sh`](./container/deploy.sh) | **Container** — Compose + nginx gateway; `--no-tls` to verify without certs |
| [`validate.sh`](./validate.sh) | Smoke tests (health, HTTP, HTTP Streams, SSE) |
| [`cloud/`](./cloud/) | Provision VMs (AWS / GCP / Linode), then run VM deploy |

VM and Container scripts are intentionally separate.
