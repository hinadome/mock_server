#!/usr/bin/env bash
# Create an Ubuntu VM on AWS EC2, open ports, optionally run deploy/deploy.sh.
#
# Prerequisites:
#   - AWS CLI v2 configured (aws configure / SSO)
#   - Permissions: ec2:RunInstances, CreateSecurityGroup, AuthorizeSecurityGroupIngress, Describe*
#
# Usage:
#   ./deploy/cloud/aws-create-vm.sh \
#     --domain api.example.com \
#     --key-name my-ec2-keypair \
#     [--region us-east-1] \
#     [--instance-type t3.small] \
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
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
INSTANCE_TYPE="t3.small"
KEY_NAME=""
SSH_KEY=""
DO_DEPLOY=0
NAME_TAG="mock-server"

usage() {
  cat <<EOF
Usage: $0 --domain HOST --key-name EC2_KEYPAIR [options]

Required:
  --domain HOST           DNS name you will point at the instance
  --key-name NAME         Existing EC2 key pair name (for SSH)

Options:
  --region REGION         Default: $REGION
  --instance-type TYPE    Default: $INSTANCE_TYPE
  --ssh-key PATH          Private key file for SSH/rsync (default: ssh-agent)
  --email EMAIL           Let's Encrypt email (with --deploy)
  --name TAG              Name tag (default: mock-server)
  --deploy                After SSH is up, sync repo and run deploy/deploy.sh
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="${2:-}"; shift 2 ;;
    --key-name) KEY_NAME="${2:-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --name) NAME_TAG="${2:-}"; shift 2 ;;
    --deploy) DO_DEPLOY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$DOMAIN" && -n "$KEY_NAME" ]] || { usage; exit 1; }
require_cmd aws jq curl
[[ "$DO_DEPLOY" -eq 1 ]] && require_cmd rsync ssh

echo "==> AWS region: $REGION"
echo "==> Resolving Ubuntu 22.04 AMI (Jammy) ..."
AMI_ID="$(aws ec2 describe-images --region "$REGION" --owners 099720109477 \
  --filters \
    "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
echo "==> AMI: $AMI_ID"

echo "==> Ensuring security group mock-server-sg ..."
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)"
SG_ID="$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=mock-server-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID="$(aws ec2 create-security-group --region "$REGION" \
    --group-name mock-server-sg \
    --description "mock-server nginx frontend" \
    --vpc-id "$VPC_ID" \
    --query GroupId --output text)"
  for SPEC in \
    "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0}]" \
    "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]" \
    "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]" \
    "IpProtocol=tcp,FromPort=50051,ToPort=50051,IpRanges=[{CidrIp=0.0.0.0/0}]" \
    "IpProtocol=tcp,FromPort=8883,ToPort=8883,IpRanges=[{CidrIp=0.0.0.0/0}]"; do
    aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" --ip-permissions "$SPEC" >/dev/null || true
  done
fi
echo "==> Security group: $SG_ID"

echo "==> Launching instance ..."
INSTANCE_ID="$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG},{Key=app,Value=mock-server}]" \
  --query 'Instances[0].InstanceId' --output text)"
echo "==> Instance: $INSTANCE_ID"

aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
echo "==> Public IP: $PUBLIC_IP"

USER=ubuntu
wait_for_ssh "$PUBLIC_IP" "$USER" "$SSH_KEY"

if [[ "$DO_DEPLOY" -eq 1 ]]; then
  remote_deploy "$PUBLIC_IP" "$USER" "$SSH_KEY" "$DOMAIN" "$EMAIL"
fi

print_next_steps "$PUBLIC_IP" "$USER" "$SSH_KEY" "$DOMAIN"
echo "AWS instance id: $INSTANCE_ID (region $REGION)"
echo "Remember: create DNS A record $DOMAIN → $PUBLIC_IP"
