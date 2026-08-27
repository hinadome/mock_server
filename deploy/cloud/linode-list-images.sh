#!/usr/bin/env bash
# List Linode images available for new instances.
#
# Prerequisites:
#   export LINODE_TOKEN="..."
#
# Usage:
#   ./deploy/cloud/linode-list-images.sh [--filter TEXT] [--vendor ubuntu|debian|all]
#
set -euo pipefail

API="https://api.linode.com/v4"
FILTER=""
VENDOR="ubuntu"

usage() {
  cat <<EOF
Usage: $0 [--filter TEXT] [--vendor ubuntu|debian|fedora|all]

Environment:
  LINODE_TOKEN     Required Personal Access Token

Options:
  --filter TEXT    Substring match on id/label (e.g. 22.04, ubuntu24)
  --vendor VENDOR  ubuntu (default), debian, fedora, or all
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) FILTER="${2:-}"; shift 2 ;;
    --vendor) VENDOR="${2:-}"; shift 2 ;;
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

echo "==> Fetching Linode images ..."
echo ""
printf "%-28s  %-10s  %-12s  %s\n" "IMAGE_ID" "VENDOR" "SIZE_MB" "LABEL"
printf "%-28s  %-10s  %-12s  %s\n" "----------------------------" "----------" "------------" "-----"

PAGE=1
PAGE_SIZE=100
while true; do
  RESP="$(curl -sS -H "Authorization: Bearer $LINODE_TOKEN" \
    "${API}/images?page=${PAGE}&page_size=${PAGE_SIZE}")"

  if echo "$RESP" | jq -e '.errors' >/dev/null 2>&1; then
    echo "ERROR: $RESP"
    exit 1
  fi

  echo "$RESP" | jq -r --arg f "$FILTER" --arg v "$VENDOR" '
    .data[]
    | select(.is_public == true)
    | select(
        ($v == "all")
        or ((.vendor // "") | ascii_downcase | test($v; "i"))
        or ((.id // "") | test($v; "i"))
      )
    | select(
        $f == ""
        or ((.id // "") | test($f; "i"))
        or ((.label // "") | test($f; "i"))
      )
    | [.id, (.vendor // "-"), ((.size // 0)|tostring), (.label // "")]
    | @tsv
  ' | while IFS=$'\t' read -r id vendor size label; do
      printf "%-28s  %-10s  %-12s  %s\n" "$id" "$vendor" "$size" "$label"
    done

  PAGES="$(echo "$RESP" | jq -r '.pages // 1')"
  if [[ "$PAGE" -ge "$PAGES" ]]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

echo ""
echo "Tip: linode-create-vm.sh defaults to --image linode/ubuntu22.04"
echo "     Example: $0 --vendor ubuntu --filter 24.04"
