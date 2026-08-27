#!/usr/bin/env bash
# List common Ubuntu (and optional Amazon Linux) AMIs on AWS EC2.
#
# Prerequisites: AWS CLI configured
#
# Usage:
#   ./deploy/cloud/aws-list-images.sh [--region us-east-1] [--owner canonical|amazon|all] [--filter TEXT]
#
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
OWNER="canonical"
FILTER=""

usage() {
  cat <<EOF
Usage: $0 [--region REGION] [--owner canonical|amazon|all] [--filter TEXT]

Options:
  --region REGION   Default: $REGION
  --owner OWNER     canonical (Ubuntu, default), amazon, or all
  --filter TEXT     Substring match on AMI name (e.g. jammy, 24.04, noble)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --filter) FILTER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found"; exit 1
fi

OWNERS=()
NAME_FILTERS=()
case "$OWNER" in
  canonical)
    OWNERS=(099720109477)
    NAME_FILTERS=("ubuntu/images/hvm-ssd/ubuntu-*" "ubuntu/images/hvm-ssd-gp3/ubuntu-*")
    ;;
  amazon)
    OWNERS=(137112412989 amazon)
    NAME_FILTERS=("al2023-ami-*" "amzn2-ami-hvm-*")
    ;;
  all)
    OWNERS=(099720109477 137112412989 amazon)
    NAME_FILTERS=("ubuntu/images/hvm-ssd/ubuntu-*" "ubuntu/images/hvm-ssd-gp3/ubuntu-*" "al2023-ami-*" "amzn2-ami-hvm-*")
    ;;
  *)
    echo "ERROR: --owner must be canonical, amazon, or all"; exit 1
    ;;
esac

echo "==> Region: $REGION  owner: $OWNER"
echo ""
printf "%-22s  %-12s  %-10s  %s\n" "AMI_ID" "ARCH" "CREATED" "NAME"
printf "%-22s  %-12s  %-10s  %s\n" "----------------------" "------------" "----------" "----"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

for pattern in "${NAME_FILTERS[@]}"; do
  aws ec2 describe-images --region "$REGION" --owners "${OWNERS[@]}" \
    --filters \
      "Name=name,Values=$pattern" \
      "Name=state,Values=available" \
      "Name=virtualization-type,Values=hvm" \
    --query 'Images[].{Id:ImageId,Name:Name,Arch:Architecture,Date:CreationDate}' \
    --output json 2>/dev/null >>"$TMP" || true
done

# Merge arrays from multiple queries
jq -s 'add | map(select(.Id != null)) | unique_by(.Id) | sort_by(.Date) | reverse' "$TMP" \
  | jq -r --arg f "$FILTER" '
      .[]
      | select($f == "" or (.Name | test($f; "i")))
      | [.Id, .Arch, (.Date | split("T")[0]), .Name]
      | @tsv
    ' \
  | while IFS=$'\t' read -r id arch date name; do
      printf "%-22s  %-12s  %-10s  %s\n" "$id" "$arch" "$date" "$name"
    done

echo ""
echo "Tip: use the AMI id with aws-create-vm (script currently auto-picks latest Ubuntu 22.04)."
echo "     Example filter: $0 --region $REGION --filter jammy"
