#!/bin/bash
# ecr-login.sh - Authenticate Docker to ECR private registry
# Usage: ./ecr-login.sh [--region us-east-1]
# Default region: us-east-1

set -e

REGION="us-east-1"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--region us-east-1]"
      exit 1
      ;;
  esac
done

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# ECR registry URL
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Login to ECR
echo "Authenticating to ECR registry: ${REGISTRY}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

echo "Successfully authenticated to ECR"
