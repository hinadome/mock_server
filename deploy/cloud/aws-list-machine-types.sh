#!/usr/bin/env bash
# List EC2 instance types (machine sizes) on AWS.
#
# Prerequisites: AWS CLI configured
#
# Usage:
#   ./deploy/cloud/aws-list-machine-types.sh [--region us-east-1] [--filter t3] [--arch x86_64|arm64|all]
#
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
FILTER=""
ARCH="x86_64"

usage() {
  cat <<EOF
Usage: $0 [--region REGION] [--filter TEXT] [--arch x86_64|arm64|all]

Options:
  --region REGION   Default: $REGION
  --filter TEXT     Substring on type name (e.g. t3, m5, c6i)
  --arch ARCH       x86_64 (default), arm64, or all
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2:-}"; shift 2 ;;
    --filter) FILTER="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if ! command -v aws >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: aws and jq are required"
  exit 1
fi

echo "==> Region: $REGION  arch: $ARCH"
echo ""
printf "%-20s  %6s  %10s  %12s  %s\n" "INSTANCE_TYPE" "VCPUS" "MEMORY_MB" "ARCH" "NETWORK"
printf "%-20s  %6s  %10s  %12s  %s\n" "--------------------" "------" "----------" "------------" "-------"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
: >"$TMP"

NEXT=""
while true; do
  if [[ -n "$NEXT" ]]; then
    PAGE="$(aws ec2 describe-instance-types --region "$REGION" --max-items 100 --starting-token "$NEXT" --output json)"
  else
    PAGE="$(aws ec2 describe-instance-types --region "$REGION" --max-items 100 --output json)"
  fi
  echo "$PAGE" | jq -c '.InstanceTypes[]' >>"$TMP"
  NEXT="$(echo "$PAGE" | jq -r '.NextToken // empty')"
  [[ -z "$NEXT" ]] && break
done

jq -s -r --arg f "$FILTER" --arg a "$ARCH" '
  map(select($f == "" or (.InstanceType | test($f; "i"))))
  | map(select(
      $a == "all"
      or ((.ProcessorInfo.SupportedArchitectures // []) | index($a) != null)
    ))
  | sort_by(.InstanceType)
  | .[]
  | [
      .InstanceType,
      (.VCpuInfo.DefaultVCpus // 0 | tostring),
      (.MemoryInfo.SizeInMiB // 0 | tostring),
      ((.ProcessorInfo.SupportedArchitectures // []) | join(",")),
      (.NetworkInfo.NetworkPerformance // "-")
    ]
  | @tsv
' "$TMP" | while IFS=$'\t' read -r itype vcpus mem arch net; do
  printf "%-20s  %6s  %10s  %12s  %s\n" "$itype" "$vcpus" "$mem" "$arch" "$net"
done

echo ""
echo "Tip: aws-create-vm.sh defaults to --instance-type t3.small"
echo "     Example: $0 --region $REGION --filter t3"
