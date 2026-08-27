#!/usr/bin/env bash
# List Compute Engine machine types on Google Cloud.
#
# Prerequisites: gcloud authenticated + project set
#
# Usage:
#   ./deploy/cloud/gcp-list-machine-types.sh [--zone us-central1-a] [--filter e2] 
#
set -euo pipefail

ZONE="${CLOUDSDK_COMPUTE_ZONE:-us-central1-a}"
FILTER=""

usage() {
  cat <<EOF
Usage: $0 [--zone ZONE] [--filter TEXT]

Options:
  --zone ZONE       Default: $ZONE
  --filter TEXT     Substring on machine type name (e.g. e2, n2, n1-standard)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zone) ZONE="${2:-}"; shift 2 ;;
    --filter) FILTER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found"
  exit 1
fi

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set project: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

echo "==> Project: $PROJECT  zone: $ZONE"
echo ""
printf "%-28s  %6s  %12s  %s\n" "MACHINE_TYPE" "VCPUS" "MEMORY_MB" "DESCRIPTION"
printf "%-28s  %6s  %12s  %s\n" "----------------------------" "------" "------------" "-----------"

gcloud compute machine-types list \
  --project "$PROJECT" \
  --zones "$ZONE" \
  --format="csv[no-heading](name,guestCpus,memoryMb,description)" \
  | while IFS=, read -r name cpus mem desc; do
      [[ -z "${name:-}" ]] && continue
      if [[ -n "$FILTER" ]] && ! echo "$name" | grep -qi -- "$FILTER"; then
        continue
      fi
      printf "%-28s  %6s  %12s  %s\n" "$name" "$cpus" "$mem" "$desc"
    done

echo ""
echo "Tip: gcp-create-vm.sh defaults to --machine-type e2-small"
echo "     Example: $0 --zone $ZONE --filter e2"
