#!/usr/bin/env bash
# List Linode instance types (plans).
#
# Prerequisites:
#   export LINODE_TOKEN="..."
#
# Usage:
#   ./deploy/cloud/linode-list-machine-types.sh [--filter standard] [--class standard|nanode|dedicated|gpu|all]
#
set -euo pipefail

API="https://api.linode.com/v4"
FILTER=""
CLASS="all"

usage() {
  cat <<EOF
Usage: $0 [--filter TEXT] [--class standard|nanode|dedicated|gpu|all]

Environment:
  LINODE_TOKEN     Required Personal Access Token

Options:
  --filter TEXT    Substring on id/label (e.g. g6-standard, 2gb)
  --class CLASS    standard, nanode, dedicated, gpu, or all (default)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) FILTER="${2:-}"; shift 2 ;;
    --class) CLASS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${LINODE_TOKEN:-}" ]]; then
  echo "ERROR: export LINODE_TOKEN=..."
  exit 1
fi
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: curl and jq are required"
  exit 1
fi

echo "==> Fetching Linode types ..."
echo ""
printf "%-22s  %6s  %8s  %8s  %10s  %s\n" "TYPE_ID" "VCPUS" "RAM_MB" "DISK_MB" "\$/MO" "LABEL"
printf "%-22s  %6s  %8s  %8s  %10s  %s\n" "----------------------" "------" "--------" "--------" "----------" "-----"

PAGE=1
PAGE_SIZE=100
while true; do
  RESP="$(curl -sS -H "Authorization: Bearer $LINODE_TOKEN" \
    "${API}/linode/types?page=${PAGE}&page_size=${PAGE_SIZE}")"

  if echo "$RESP" | jq -e '.errors' >/dev/null 2>&1; then
    echo "ERROR: $RESP"
    exit 1
  fi

  echo "$RESP" | jq -r --arg f "$FILTER" --arg c "$CLASS" '
    .data[]
    | select($c == "all" or (.class // "") == $c)
    | select(
        $f == ""
        or ((.id // "") | test($f; "i"))
        or ((.label // "") | test($f; "i"))
      )
    | [
        .id,
        (.vcpus|tostring),
        (.memory|tostring),
        (.disk|tostring),
        ((.price.monthly // 0)|tostring),
        (.label // "")
      ]
    | @tsv
  ' | while IFS=$'\t' read -r id vcpus mem disk price label; do
      printf "%-22s  %6s  %8s  %8s  %10s  %s\n" "$id" "$vcpus" "$mem" "$disk" "$price" "$label"
    done

  PAGES="$(echo "$RESP" | jq -r '.pages // 1')"
  if [[ "$PAGE" -ge "$PAGES" ]]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

echo ""
echo "Tip: linode-create-vm.sh defaults to --type g6-standard-1"
echo "     Example: $0 --class standard --filter g6-standard"
