#!/usr/bin/env bash
# Shared helpers for cloud VM provisioning scripts.
# shellcheck disable=SC2034

set -euo pipefail

CLOUD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$CLOUD_SCRIPT_DIR/../.." && pwd)"

require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "ERROR: required command not found: $c"
      exit 1
    fi
  done
}

wait_for_ssh() {
  local host="$1"
  local user="${2:-ubuntu}"
  local key="${3:-}"
  local tries=60
  local i
  echo "==> Waiting for SSH on ${user}@${host} ..."
  for ((i = 1; i <= tries; i++)); do
    local ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes)
    if [[ -n "$key" ]]; then
      ssh_opts+=(-i "$key")
    fi
    if ssh "${ssh_opts[@]}" "${user}@${host}" "echo ok" >/dev/null 2>&1; then
      echo "==> SSH ready"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: SSH not ready after ${tries} attempts"
  return 1
}

remote_deploy() {
  local host="$1"
  local user="$2"
  local key="$3"
  local domain="$4"
  local email="${5:-}"

  local ssh_opts=(-o StrictHostKeyChecking=accept-new)
  local scp_opts=(-o StrictHostKeyChecking=accept-new)
  if [[ -n "$key" ]]; then
    ssh_opts+=(-i "$key")
    scp_opts+=(-i "$key")
  fi

  echo "==> Syncing repo to ${user}@${host}:~/mock_server"
  ssh "${ssh_opts[@]}" "${user}@${host}" "rm -rf ~/mock_server && mkdir -p ~/mock_server"
  rsync -az -e "ssh ${ssh_opts[*]}" \
    --exclude node_modules --exclude dist --exclude .git --exclude certs \
    "$REPO_ROOT/" "${user}@${host}:~/mock_server/"

  local email_arg=()
  if [[ -n "$email" ]]; then
    email_arg=(--email "$email")
  fi

  echo "==> Running deploy/deploy.sh on remote host"
  ssh "${ssh_opts[@]}" -t "${user}@${host}" \
    "sudo bash ~/mock_server/deploy/deploy.sh --domain '$domain' ${email_arg[*]:-}"
}

print_next_steps() {
  local host="$1"
  local user="$2"
  local key="$3"
  local domain="$4"

  local key_opt=""
  if [[ -n "$key" ]]; then
    key_opt=" -i $key"
  fi

  cat <<EOF

============================================================
 VM is ready

 SSH:
   ssh${key_opt} ${user}@${host}

 Deploy mock-server (if not already run with --deploy):
   rsync -az --exclude node_modules --exclude dist --exclude .git \\
     ./ ${user}@${host}:~/mock_server/
   ssh${key_opt} ${user}@${host}
   cd ~/mock_server && sudo ./deploy/deploy.sh --domain ${domain}

 After DNS A record ${domain} → ${host}:
   curl -sS https://${domain}/health
   curl -sS -N https://${domain}/http-stream/demo
   ./deploy/validate.sh --base https://${domain}
============================================================
EOF
}
