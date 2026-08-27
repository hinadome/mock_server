#!/usr/bin/env bash
# Create an Ubuntu VM on Google Compute Engine, open firewall, optionally deploy.
#
# Prerequisites:
#   - gcloud CLI authenticated (gcloud auth login)
#   - A project set: gcloud config set project PROJECT_ID
#   - Compute Engine API enabled
#
# Usage:
#   ./deploy/cloud/gcp-create-vm.sh \
#     --domain api.example.com \
#     [--zone us-central1-a] \
#     [--machine-type e2-small] \
#     [--ssh-key ~/.ssh/id_rsa] \
#     [--email you@example.com] \
#     [--deploy]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

DOMAIN=""
EMAIL=""
ZONE="${CLOUDSDK_COMPUTE_ZONE:-us-central1-a}"
MACHINE_TYPE="e2-small"
SSH_KEY=""
DO_DEPLOY=0
NAME="mock-server"
NETWORK_TAGS="mock-server"

usage() {
  cat <<EOF
Usage: $0 --domain HOST [options]

Required:
  --domain HOST           DNS name you will point at the instance

Options:
  --zone ZONE             Default: $ZONE
  --machine-type TYPE     Default: $MACHINE_TYPE
  --name NAME             Instance name (default: mock-server)
  --ssh-key PATH          Private key for SSH/rsync
  --email EMAIL           Let's Encrypt email (with --deploy)
  --deploy                Sync repo and run deploy/deploy.sh after boot
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --zone) ZONE="${2:-}"; shift 2 ;;
    --machine-type) MACHINE_TYPE="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --deploy) DO_DEPLOY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$DOMAIN" ]] || { usage; exit 1; }
require_cmd gcloud
[[ "$DO_DEPLOY" -eq 1 ]] && require_cmd rsync ssh jq

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set a GCP project: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi
echo "==> Project: $PROJECT  zone: $ZONE"

echo "==> Ensuring firewall rule mock-server-allow ..."
if ! gcloud compute firewall-rules describe mock-server-allow --project "$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules create mock-server-allow \
    --project "$PROJECT" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:22,tcp:80,tcp:443,tcp:50051,tcp:8883 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$NETWORK_TAGS"
fi

echo "==> Creating instance $NAME ..."
gcloud compute instances create "$NAME" \
  --project "$PROJECT" \
  --zone "$ZONE" \
  --machine-type "$MACHINE_TYPE" \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags="$NETWORK_TAGS" \
  --labels=app=mock-server

PUBLIC_IP="$(gcloud compute instances describe "$NAME" --zone "$ZONE" --project "$PROJECT" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"
echo "==> Public IP: $PUBLIC_IP"

USER=ubuntu
# Prefer OS Login / project SSH keys via gcloud; also support plain ssh
wait_for_ssh "$PUBLIC_IP" "$USER" "$SSH_KEY" || {
  echo "==> Direct SSH failed; trying gcloud compute ssh ..."
  gcloud compute ssh "$NAME" --zone "$ZONE" --project "$PROJECT" --command "echo ok"
}

if [[ "$DO_DEPLOY" -eq 1 ]]; then
  # Use gcloud scp/ssh when no key provided
  if [[ -n "$SSH_KEY" ]]; then
    remote_deploy "$PUBLIC_IP" "$USER" "$SSH_KEY" "$DOMAIN" "$EMAIL"
  else
    echo "==> Syncing via gcloud compute scp ..."
    gcloud compute ssh "$NAME" --zone "$ZONE" --project "$PROJECT" --command "rm -rf ~/mock_server && mkdir -p ~/mock_server"
    gcloud compute scp --recurse --zone "$ZONE" --project "$PROJECT" \
      --compress \
      "$REPO_ROOT"/deploy "$REPO_ROOT"/src "$REPO_ROOT"/mocks "$REPO_ROOT"/docs \
      "$REPO_ROOT"/package.json "$REPO_ROOT"/package-lock.json "$REPO_ROOT"/tsconfig.json \
      "$REPO_ROOT"/Dockerfile "$REPO_ROOT"/docker-compose.yml "$REPO_ROOT"/README.md \
      "${NAME}:~/mock_server/" || true
    # Full rsync over gcloud IAP/ssh
    gcloud compute ssh "$NAME" --zone "$ZONE" --project "$PROJECT" --command "sudo apt-get update -y && sudo apt-get install -y rsync"
    rsync -az -e "gcloud compute ssh --zone=$ZONE --project=$PROJECT --" \
      --exclude node_modules --exclude dist --exclude .git --exclude certs \
      "$REPO_ROOT/" "${NAME}:~/mock_server/"
    EMAIL_ARGS=""
    [[ -n "$EMAIL" ]] && EMAIL_ARGS="--email $EMAIL"
    gcloud compute ssh "$NAME" --zone "$ZONE" --project "$PROJECT" -- \
      "sudo bash ~/mock_server/deploy/deploy.sh --domain $DOMAIN $EMAIL_ARGS"
  fi
fi

print_next_steps "$PUBLIC_IP" "$USER" "$SSH_KEY" "$DOMAIN"
echo "GCP instance: $NAME (zone $ZONE, project $PROJECT)"
echo "Remember: create DNS A record $DOMAIN → $PUBLIC_IP"
echo "SSH via gcloud: gcloud compute ssh $NAME --zone $ZONE"
