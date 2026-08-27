# Provision cloud VMs (AWS / GCP / Linode)

These scripts create an Ubuntu VM, open the ports needed for the nginx frontend, then optionally sync this repo and run [`deploy/deploy.sh`](../deploy.sh).

| Script | Cloud | CLI / auth |
|--------|-------|------------|
| [`aws-create-vm.sh`](./aws-create-vm.sh) | AWS EC2 | `aws` CLI configured |
| [`gcp-create-vm.sh`](./gcp-create-vm.sh) | Google Compute Engine | `gcloud` + project set |
| [`linode-create-vm.sh`](./linode-create-vm.sh) | Linode (Akamai) | `LINODE_TOKEN` env var |
| [`aws-list-images.sh`](./aws-list-images.sh) | AWS AMIs | `aws` CLI |
| [`gcp-list-images.sh`](./gcp-list-images.sh) | GCP images | `gcloud` |
| [`linode-list-images.sh`](./linode-list-images.sh) | Linode images | `LINODE_TOKEN` |
| [`aws-list-machine-types.sh`](./aws-list-machine-types.sh) | EC2 instance types | `aws` CLI |
| [`gcp-list-machine-types.sh`](./gcp-list-machine-types.sh) | GCE machine types | `gcloud` |
| [`linode-list-machine-types.sh`](./linode-list-machine-types.sh) | Linode plans | `LINODE_TOKEN` |

Shared helpers: [`common.sh`](./common.sh)

## List images

```bash
# AWS (Ubuntu by default)
./deploy/cloud/aws-list-images.sh --region us-east-1
./deploy/cloud/aws-list-images.sh --region us-west-2 --filter jammy

# Google Cloud
./deploy/cloud/gcp-list-images.sh --family ubuntu --filter 2204

# Linode
export LINODE_TOKEN=...
./deploy/cloud/linode-list-images.sh --vendor ubuntu --filter 22.04
```

## List machine types

```bash
# AWS
./deploy/cloud/aws-list-machine-types.sh --region us-east-1 --filter t3

# Google Cloud
./deploy/cloud/gcp-list-machine-types.sh --zone us-central1-a --filter e2

# Linode
export LINODE_TOKEN=...
./deploy/cloud/linode-list-machine-types.sh --class standard --filter g6-standard
```

## Ports opened on the VM

| Port | Purpose |
|------|---------|
| 22 | SSH |
| 80 | HTTP (ACME + redirect) |
| 443 | HTTPS / WSS |
| 50051 | gRPC TLS |
| 8883 | MQTT TLS |

## Prerequisites (all)

1. A **domain** whose DNS A record you can point at the new public IP  
2. Local tools: `bash`, `curl`, `jq`, `ssh`, `rsync` (for `--deploy`)  
3. Cloud-specific CLI/token (below)

## AWS

```bash
# One-time: aws configure   (or SSO)
# Create an EC2 key pair in the console/CLI and download the .pem

chmod +x deploy/cloud/*.sh

./deploy/cloud/aws-create-vm.sh \
  --domain api.example.com \
  --key-name my-ec2-keypair \
  --ssh-key ~/.ssh/my-ec2-keypair.pem \
  --region us-east-1 \
  --email you@example.com \
  --deploy
```

Without `--deploy`, the script only creates the VM and prints SSH instructions.

## Google Cloud

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud services enable compute.googleapis.com

./deploy/cloud/gcp-create-vm.sh \
  --domain api.example.com \
  --zone us-central1-a \
  --email you@example.com \
  --deploy
```

SSH without a local key file:

```bash
gcloud compute ssh mock-server --zone us-central1-a
```

## Linode

```bash
export LINODE_TOKEN="your-personal-access-token"

./deploy/cloud/linode-create-vm.sh \
  --domain api.example.com \
  --root-pass 'A-Strong-Passw0rd!' \
  --ssh-pub ~/.ssh/id_rsa.pub \
  --ssh-key ~/.ssh/id_rsa \
  --region us-east \
  --email you@example.com \
  --deploy
```

## After the VM exists (manual deploy)

```bash
# Point DNS: api.example.com → <PUBLIC_IP>

ssh -i KEY ubuntu@PUBLIC_IP   # or root@ on Linode
# sync + deploy:
rsync -az --exclude node_modules --exclude dist --exclude .git ./ user@PUBLIC_IP:~/mock_server/
ssh user@PUBLIC_IP 'sudo bash ~/mock_server/deploy/deploy.sh --domain api.example.com --email you@example.com'
```

## Verify

```bash
curl -sS https://api.example.com/health
curl -sS https://api.example.com/http/demo
curl -sS -N https://api.example.com/http-stream/demo
./deploy/validate.sh --base https://api.example.com
wscat -c wss://api.example.com/ws/demo
```

Full nginx layout: [../docs/production.md](../../docs/production.md) (from repo root: `docs/production.md`).
