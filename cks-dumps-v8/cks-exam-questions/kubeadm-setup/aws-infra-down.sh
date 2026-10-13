#!/bin/bash
# ============================================================
# Kubeadm Lab Infrastructure — Destroy Script
# Discovers and terminates ALL nodes (controlplane + node0*)
# ============================================================

set -euo pipefail
export AWS_PAGER=""

REGION="ap-south-1"
VPC_NAME="kubeadm-vpc"
SUBNET_NAME="kubeadm-subnet"
SG_NAME="kubeadm-sg"

echo ""
echo "==========================================="
echo " Kubeadm Lab — Destroying Infrastructure"
echo "==========================================="
echo ""

# ── Step 1: Discover and terminate ALL lab instances ──────────
echo "[1/5] Finding all lab instances (controlplane + node0*)..."

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
        "Name=tag:Name,Values=controlplane,node01,node02,node03,node04,node05" \
        "Name=instance-state-name,Values=running,pending,stopped,stopping" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -n "$INSTANCE_IDS" ]; then
    echo "  Terminating instances: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION" > /dev/null
    echo "  Waiting for termination..."
    aws ec2 wait instance-terminated \
        --instance-ids $INSTANCE_IDS \
        --region "$REGION"
    echo "  All instances terminated."
else
    echo "  No lab instances found — skipping."
fi

# ── Step 2: Get VPC ID ────────────────────────────────────────
echo "[2/5] Looking up VPC..."

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query "Vpcs[0].VpcId" \
    --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "  VPC not found — nothing more to clean up."
    exit 0
fi
echo "  Found VPC: $VPC_ID"

# ── Step 3: Delete Security Group ────────────────────────────
echo "[3/5] Deleting Security Group..."

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    aws ec2 delete-security-group --group-id "$SG_ID"
    echo "  Security Group deleted: $SG_ID"
else
    echo "  Security Group not found — skipping."
fi

# ── Step 4: Delete Route Tables, IGW, Subnet ─────────────────
echo "[4/5] Deleting Route Tables, IGW, Subnet..."

# Non-main route tables
RT_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" \
    --output text)

for RT in $RT_IDS; do
    ASSOC_ID=$(aws ec2 describe-route-tables \
        --route-table-ids "$RT" \
        --query "RouteTables[0].Associations[0].RouteTableAssociationId" \
        --output text)
    [ "$ASSOC_ID" != "None" ] && [ -n "$ASSOC_ID" ] && \
        aws ec2 disassociate-route-table --association-id "$ASSOC_ID"
    aws ec2 delete-route-table --route-table-id "$RT"
    echo "  Route Table deleted: $RT"
done

# IGW
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[0].InternetGatewayId" \
    --output text)

if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
    aws ec2 detach-internet-gateway \
        --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
    echo "  IGW deleted: $IGW_ID"
fi

# Subnet
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$SUBNET_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0].SubnetId" \
    --output text)

if [ "$SUBNET_ID" != "None" ] && [ -n "$SUBNET_ID" ]; then
    aws ec2 delete-subnet --subnet-id "$SUBNET_ID"
    echo "  Subnet deleted: $SUBNET_ID"
fi

# ── Step 5: Delete VPC ────────────────────────────────────────
echo "[5/5] Deleting VPC..."
aws ec2 delete-vpc --vpc-id "$VPC_ID"
echo "  VPC deleted: $VPC_ID"

echo ""
echo "✅ All lab infrastructure destroyed successfully."
echo ""