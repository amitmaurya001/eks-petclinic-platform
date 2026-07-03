#!/bin/bash
# bootstrap-state.sh - Provision S3 bucket and DynamoDB table for Terraform state
# 
# This script creates the S3 bucket and DynamoDB table used for Terraform state.
# It is idempotent and can be safely run multiple times.

# Parameters
REGION="us-east-1"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS credentials are configured
aws sts get-caller-identity > /dev/null 2>&1 || {
    echo "ERROR: AWS credentials are not configured. Run 'aws configure' and try again."
    exit 1
}

# Display AWS account and region

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "Region: $REGION"

# S3 Bucket

bucket_name="petclinic-terraform-state-$AWS_ACCOUNT_ID"

# Check if bucket exists
if aws s3api head-bucket --bucket "$bucket_name" --region "$REGION" 2>/dev/null; then
    echo "S3 bucket '$bucket_name' already exists."
else
    echo "Creating S3 bucket '$bucket_name' in region '$REGION'."
    
    # Create S3 bucket with versions and encryption
    aws s3api create-bucket \
        --bucket "$bucket_name" \
        --region "$REGION" \
        --object-lock-enabled-for-bucket
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled
    
    # Configure encryption (SSE-S3)
    aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration '{"BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": true, "RestrictPublicBuckets": true}'
    
    # Tag the bucket
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging '{"TagSet": [{"Key": "Project", "Value": "petclinic"}, {"Key": "Environment", "Value": "common"}, {"Key": "ManagedBy", "Value": "terraform"}, {"Key": "Name", "Value": "petclinic-terraform-state"}]}'
    
    echo "S3 bucket '$bucket_name' created successfully."
fi

# DynamoDB Table

table_name="petclinic-terraform-locks"

# Check if table exists
if aws dynamodb describe-table --table-name "$table_name" --region "$REGION" 2>/dev/null; then
    echo "DynamoDB table '$table_name' already exists."
else
    echo "Creating DynamoDB table '$table_name' in region '$REGION'."
    
    # Create DynamoDB table with key LockID
    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION" \
        --tags '[{"Key":"Project","Value":"petclinic"},{"Key":"Environment","Value":"common"},{"Key":"ManagedBy","Value":"terraform"},{"Key":"Name","Value":"petclinic-terraform-locks"}]'
    
    echo "DynamoDB table '$table_name' created successfully."
fi

echo "Bootstrap complete. S3 bucket and DynamoDB table are ready for Terraform."