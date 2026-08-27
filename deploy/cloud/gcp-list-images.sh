#!/usr/bin/env bash
# List public Compute Engine OS images on Google Cloud.
#
# Prerequisites: gcloud authenticated
#
# Usage:
#   ./deploy/cloud/gcp-list-images.sh [--family ubuntu|debian|cos|all] [--filter TEXT]
#
set -euo pipefail

FAMILY="ubuntu"
FILTER=""

usage() {
  cat <<EOF_USAGE
Usage: $0 [--family ubuntu|debian|cos|all] [--filter TEXT]

Options:
  --family GROUP    ubuntu (default), debian, cos, or all
  --filter TEXT     Substring match on image name/family (e.g. 2204, jammy)
  -h, --help
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --family) FAMILY="${2:-}"; shift 2 ;;
    --filter) FILTER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found"; exit 1
fi

PROJECTS=()
case "$FAMILY" in
  ubuntu) PROJECTS=(ubuntu-os-cloud) ;;
  debian) PROJECTS=(debian-cloud) ;;
  cos) PROJECTS=(cos-cloud) ;;
  all) PROJECTS=(ubuntu-os-cloud debian-cloud cos-cloud) ;;
  *) echo "ERROR: --family must be ubuntu, debian, cos, or all"; exit 1 ;;
esac

echo "==> Image family group: $FAMILY"
echo ""
printf "%-48s  %-28s  %-10s  %s\n" "IMAGE" "FAMILY" "STATUS" "PROJECT"
printf "%-48s  %-28s  %-10s  %s\n" "------------------------------------------------" "----------------------------" "----------" "--------"

for img_project in "${PROJECTS[@]}"; do
  gcloud compute images list \
    --project "$img_project" \
    --filter="status=READY" \
    --format="csv[no-heading](name,family,status)" \
    2>/dev/null \
    | while IFS=, read -r name family status; do
        [[ -z "${name:-}" ]] && continue
        if [[ -n "$FILTER" ]] && ! echo "$name $family" | grep -qi -- "$FILTER"; then
          continue
        fi
        printf "%-48s  %-28s  %-10s  %s\n" "$name" "$family" "$status" "$img_project"
      done
done

echo ""
echo "Tip: gcp-create-vm.sh uses --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud"
echo "     Example: $0 --family ubuntu --filter 2204"
