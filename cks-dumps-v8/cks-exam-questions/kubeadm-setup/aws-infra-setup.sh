#!/bin/bash
# ============================================================
# Kubeadm Lab Infrastructure — Create Script
# Idempotent: safe to re-run, only creates what's missing
# Usage:
#   ./create_infra.sh              → 1 worker (default)
#   ./create_infra.sh --workers 2  → 2 workers
#   ./create_infra.sh --workers 3  → 3 workers
# ============================================================

set -euo pipefail
export AWS_PAGER=""

# ── Variables ─────────────────────────────────────────────────
REGION="ap-south-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"

VPC_NAME="kubeadm-vpc"
SUBNET_NAME="kubeadm-subnet"
SG_NAME="kubeadm-sg"

KEY_NAME="aws-new"
AMI_ID="ami-0f58b397bc5c1f2e8"   # Ubuntu 24.04 Mumbai

CP_NAME="controlplane"
CP_TYPE="t3.medium"               
WK_TYPE="t3.micro"               

# ── Parse --workers flag ───────────────────────────────────────
WORKER_COUNT=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workers)
            WORKER_COUNT="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--workers N]"
            exit 1
            ;;
    esac
done

echo ""
echo "==========================================="
echo " Kubeadm Lab — Creating Infrastructure"
echo " Workers requested: $WORKER_COUNT"
echo "==========================================="
echo ""

# ── Step 1: VPC (idempotent) ──────────────────────────────────
echo "[1/6] Checking VPC..."

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query "Vpcs[0].VpcId" \
    --output text 2>/dev/null || echo "None")

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "  Creating VPC..."
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "$VPC_CIDR" \
        --region "$REGION" \
        --query 'Vpc.VpcId' \
        --output text)
    aws ec2 create-tags \
        --resources "$VPC_ID" \
        --tags Key=Name,Value="$VPC_NAME"
    aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-support
    aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-hostnames
    echo "  VPC created: $VPC_ID"
else
    echo "  VPC already exists: $VPC_ID — skipping."
fi

# ── Step 2: Subnet (idempotent) ───────────────────────────────
echo "[2/6] Checking Subnet..."

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$SUBNET_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0].SubnetId" \
    --output text 2>/dev/null || echo "None")

if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
    echo "  Creating Subnet..."
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$SUBNET_CIDR" \
        --availability-zone "${REGION}a" \
        --query 'Subnet.SubnetId' \
        --output text)
    aws ec2 create-tags \
        --resources "$SUBNET_ID" \
        --tags Key=Name,Value="$SUBNET_NAME"
    aws ec2 modify-subnet-attribute \
        --subnet-id "$SUBNET_ID" \
        --map-public-ip-on-launch
    echo "  Subnet created: $SUBNET_ID"
else
    echo "  Subnet already exists: $SUBNET_ID — skipping."
fi

# ── Step 3: Internet Gateway + Route Table (idempotent) ───────
echo "[3/6] Checking Internet Gateway..."

IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[0].InternetGatewayId" \
    --output text 2>/dev/null || echo "None")

if [ "$IGW_ID" == "None" ] || [ -z "$IGW_ID" ]; then
    echo "  Creating Internet Gateway..."
    IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"

    RT_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    aws ec2 create-route \
        --route-table-id "$RT_ID" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID"
    aws ec2 associate-route-table \
        --route-table-id "$RT_ID" \
        --subnet-id "$SUBNET_ID"
    echo "  IGW + Route Table created: $IGW_ID"
else
    echo "  IGW already exists: $IGW_ID — skipping."
fi

# ── Step 4: Security Group (idempotent) ───────────────────────
echo "[4/6] Checking Security Group..."

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
    echo "  Creating Security Group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Allow all inbound - lab only" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol -1 \
        --cidr 0.0.0.0/0
    echo "  Security Group created: $SG_ID"
else
    echo "  Security Group already exists: $SG_ID — skipping."
fi

# ── Step 5: Control Plane (idempotent) ────────────────────────
echo "[5/6] Checking Control Plane node..."

CP_STATE=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$CP_NAME" "Name=instance-state-name,Values=running,pending,stopped" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text 2>/dev/null || echo "None")

if [ "$CP_STATE" == "None" ] || [ -z "$CP_STATE" ]; then
    echo "  Launching Control Plane ($CP_TYPE)..."
    aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$CP_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CP_NAME}]" \
        --count 1 > /dev/null
    echo "  Control Plane launched."
else
    echo "  Control Plane already exists (state: $CP_STATE) — skipping."
fi

# ── Step 6: Worker Nodes (idempotent, creates only missing) ───
echo "[6/6] Checking Worker Nodes (requested: $WORKER_COUNT)..."

for i in $(seq 1 "$WORKER_COUNT"); do
    WK_NAME="node0${i}"

    WK_STATE=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$WK_NAME" "Name=instance-state-name,Values=running,pending,stopped" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null || echo "None")

    if [ "$WK_STATE" == "None" ] || [ -z "$WK_STATE" ]; then
        echo "  Launching $WK_NAME ($WK_TYPE)..."
        aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type "$WK_TYPE" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SG_ID" \
            --subnet-id "$SUBNET_ID" \
            --associate-public-ip-address \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$WK_NAME}]" \
            --count 1 > /dev/null
        echo "  $WK_NAME launched."
    else
        echo "  $WK_NAME already exists (state: $WK_STATE) — skipping."
    fi
done

# ── Scale down: terminate worker nodes beyond requested count ──
echo "  Checking for extra worker nodes to terminate..."

MAX_WORKERS=5  # script supports up to node05

for i in $(seq $(( WORKER_COUNT + 1 )) "$MAX_WORKERS"); do
    EXTRA_NAME="node0${i}"

    EXTRA_ID=$(aws ec2 describe-instances \
        --filters \
            "Name=tag:Name,Values=$EXTRA_NAME" \
            "Name=instance-state-name,Values=running,pending,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null || echo "None")

    if [ "$EXTRA_ID" != "None" ] && [ -n "$EXTRA_ID" ]; then
        echo "  Terminating extra node $EXTRA_NAME ($EXTRA_ID)..."
        aws ec2 terminate-instances --instance-ids "$EXTRA_ID" > /dev/null
        aws ec2 wait instance-terminated --instance-ids "$EXTRA_ID"
        echo "  $EXTRA_NAME terminated."
    fi
done

# ── Wait + Print IPs ──────────────────────────────────────────
echo ""
echo "⏳ Waiting for all instances to reach running state..."

# Collect instance IDs by name individually (avoids comma-filter bug)
ALL_IDS=""

CP_ID=$(aws ec2 describe-instances \
    --filters \
        "Name=tag:Name,Values=$CP_NAME" \
        "Name=instance-state-name,Values=running,pending" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)
ALL_IDS="$CP_ID"

for i in $(seq 1 "$WORKER_COUNT"); do
    WK_ID=$(aws ec2 describe-instances \
        --filters \
            "Name=tag:Name,Values=node0${i}" \
            "Name=instance-state-name,Values=running,pending" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text)
    ALL_IDS="$ALL_IDS $WK_ID"
done

# Wait using instance IDs — reliable, no tag filter issues
aws ec2 wait instance-running \
    --instance-ids $ALL_IDS \
    --region "$REGION"

echo ""
echo "======================================"
echo " KUBEADM LAB — NODES READY"
echo "======================================"

CP_IP=$(aws ec2 describe-instances \
    --instance-ids "$CP_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "Control Plane : $CP_NAME  →  $CP_IP"
echo "SSH: ssh -i ${KEY_NAME}.pem ubuntu@${CP_IP}"
echo ""

for i in $(seq 1 "$WORKER_COUNT"); do
    WK_ID=$(aws ec2 describe-instances \
        --filters \
            "Name=tag:Name,Values=node0${i}" \
            "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text)
    WK_IP=$(aws ec2 describe-instances \
        --instance-ids "$WK_ID" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)
    echo "Worker Node   : node0${i}  →  $WK_IP"
    echo "SSH: ssh -i ${KEY_NAME}.pem ubuntu@${WK_IP}"
done

echo "======================================"
echo ""