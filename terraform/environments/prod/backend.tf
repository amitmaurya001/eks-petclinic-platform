# backend.tf - prod environment
# Configures the S3 backend for storing Terraform state.
# To deploy in a different account, override the bucket at init time:
#   terraform init -backend-config="bucket=petclinic-terraform-state-<account-id>"

terraform {
  backend "s3" {
    bucket       = "petclinic-terraform-state-478468080326"
    key          = "petclinic/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
