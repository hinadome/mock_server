#!/usr/bin/env bash
# Create an Ubuntu VM on Linode (Akamai), open firewall, optionally deploy.
#
# Prerequisites:
#   - export LINODE_TOKEN="..."   (Personal Access Token with linodes:read_write)
#   - SSH public key for the instance
#
# Usage:
#   export LINODE_TOKEN=...
#   ./deploy/cloud/linode-create-vm.sh \
#     --domain api.example.com \
#     --root-pass 'A-Strong-Passw0rd!' \
#     [--ssh-pub ~/.ssh/id_rsa.pub] \
#     [--ssh-key ~/.ssh/id_rsa] \
#     [--region us-east] \
#     [--type g6-standard-1] \
#     [--email you@example.com] \
#     [--deploy]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

API="https://api.linode.com/v4"
DOMAIN=""
EMAIL=""
REGION="us-east"
TYPE="g6-standard-1"
IMAGE="linode/ubuntu22.04"
LABEL="mock-server"
ROOT_PASS=""
SSH_PUB=""
SSH_KEY=""
DO_DEPLOY=0

usage() {
  cat <<EOF
Usage: $0 --domain HOST --root-pass PASS [options]

Required:
  --domain HOST           DNS name you will point at the instance
  --root-pass PASS        Root password for the Linode (required by API)

Environment:
  LINODE_TOKEN            Linode API v4 personal access token (required)

Options:
  --region REGION         Default: $REGION
  --type TYPE             Default: $TYPE (g6-standard-1 ≈ 2GB)
  --label NAME            Default: $LABEL
  --image IMAGE           Default: $IMAGE
  --ssh-pub PATH          SSH public key to install (recommended)
  --ssh-key PATH          Private key for SSH/rsync after create
  --email EMAIL           Let's Encrypt email (with --deploy)
  --deploy                Sync repo and run deploy/deploy.sh after boot
  -h, --help
EOF
}

linode_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local args=(-sS -X "$method" -H "Authorization: Bearer $LINODE_TOKEN" -H "Content-Type: application/json")
  if [[ -n "$data" ]]; then
    args+=(-d "$data")
  fi
  curl "${args[@]}" "${API}${path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --type) TYPE="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --root-pass) ROOT_PASS="${2:-}"; shift 2 ;;
    --ssh-pub) SSH_PUB="${2:-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --deploy) DO_DEPLOY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$DOMAIN" && -n "$ROOT_PASS" ]] || { usage; exit 1; }
[[ -n "${LINODE_TOKEN:-}" ]] || { echo "ERROR: export LINODE_TOKEN=..."; exit 1; }
require_cmd curl jq
[[ "$DO_DEPLOY" -eq 1 ]] && require_cmd rsync ssh

SSH_KEYS_JSON="[]"
PUB_CONTENT=""
if [[ -n "$SSH_PUB" ]]; then
  PUB_CONTENT="$(tr -d '\n' < "$SSH_PUB")"
fi

echo "==> Creating Linode $LABEL ($TYPE in $REGION) ..."
if [[ -n "$PUB_CONTENT" ]]; then
  CREATE_PAYLOAD="$(jq -nc \
    --arg region "$REGION" \
    --arg type "$TYPE" \
    --arg label "$LABEL" \
    --arg image "$IMAGE" \
    --arg root "$ROOT_PASS" \
    --arg pubkey "$PUB_CONTENT" \
    '{
      region: $region,
      type: $type,
      label: $label,
      image: $image,
      root_pass: $root,
      authorized_keys: [$pubkey],
      tags: ["mock-server"],
      booted: true
    }')"
else
  CREATE_PAYLOAD="$(jq -nc \
    --arg region "$REGION" \
    --arg type "$TYPE" \
    --arg label "$LABEL" \
    --arg image "$IMAGE" \
    --arg root "$ROOT_PASS" \
    '{
      region: $region,
      type: $type,
      label: $label,
      image: $image,
      root_pass: $root,
      tags: ["mock-server"],
      booted: true
    }')"
fi

RESP="$(linode_api POST /linode/instances "$CREATE_PAYLOAD")"
LINODE_ID="$(echo "$RESP" | jq -r '.id // empty')"
if [[ -z "$LINODE_ID" ]]; then
  echo "ERROR creating Linode: $RESP"
  exit 1
fi
echo "==> Linode id: $LINODE_ID"

echo "==> Waiting for running status ..."
for _ in $(seq 1 60); do
  ST="$(linode_api GET "/linode/instances/$LINODE_ID" | jq -r '.status')"
  [[ "$ST" == "running" ]] && break
  sleep 5
done

PUBLIC_IP="$(linode_api GET "/linode/instances/$LINODE_ID" | jq -r '.ipv4[0]')"
echo "==> Public IP: $PUBLIC_IP"

# Firewall (Linode Cloud Firewall)
echo "==> Creating / attaching firewall mock-server-fw ..."
FW_PAYLOAD="$(jq -nc \
  --argjson ids "[$LINODE_ID]" \
  '{
    label: ("mock-server-fw-" + ($ids[0]|tostring)),
    rules: {
      inbound_policy: "DROP",
      outbound_policy: "ACCEPT",
      inbound: [
        {protocol:"TCP", ports:"22", addresses:{ipv4:["0.0.0.0/0"], ipv6:["::/0"]}, action:"ACCEPT", label:"ssh"},
        {protocol:"TCP", ports:"80", addresses:{ipv4:["0.0.0.0/0"], ipv6:["::/0"]}, action:"ACCEPT", label:"http"},
        {protocol:"TCP", ports:"443", addresses:{ipv4:["0.0.0.0/0"], ipv6:["::/0"]}, action:"ACCEPT", label:"https"},
        {protocol:"TCP", ports:"50051", addresses:{ipv4:["0.0.0.0/0"], ipv6:["::/0"]}, action:"ACCEPT", label:"grpc"},
        {protocol:"TCP", ports:"8883", addresses:{ipv4:["0.0.0.0/0"], ipv6:["::/0"]}, action:"ACCEPT", label:"mqtt-tls"}
      ]
    },
    devices: { linodes: $ids }
  }')"
linode_api POST /networking/firewalls "$FW_PAYLOAD" >/dev/null || echo "WARN: firewall create skipped/failed (may already exist)"

USER=root

wait_for_ssh "$PUBLIC_IP" "$USER" "$SSH_KEY"

if [[ "$DO_DEPLOY" -eq 1 ]]; then
  remote_deploy "$PUBLIC_IP" "$USER" "$SSH_KEY" "$DOMAIN" "$EMAIL"
fi

print_next_steps "$PUBLIC_IP" "$USER" "$SSH_KEY" "$DOMAIN"
echo "Linode id: $LINODE_ID (region $REGION)"
echo "Remember: create DNS A record $DOMAIN → $PUBLIC_IP"
echo "Delete later: curl -X DELETE -H \"Authorization: Bearer \$LINODE_TOKEN\" $API/linode/instances/$LINODE_ID"
