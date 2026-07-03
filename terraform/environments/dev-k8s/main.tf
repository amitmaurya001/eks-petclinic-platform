# main.tf - dev-k8s environment
# Deploys Kubernetes add-ons (ACM, ALB controller, ingress, namespaces)
# for the existing dev EKS cluster.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "petclinic"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Read the existing EKS cluster from the infrastructure root module's state.
# This avoids hardcoding the cluster name — it is derived from the dev/prod
# root module output so there is no possibility of drift.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "petclinic-terraform-state-${data.aws_caller_identity.current.account_id}"
    key    = "petclinic/${var.environment}/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Derive the cluster name from the infra root module state.
  # Fall back to the conventional name so the module can be applied in isolation.
  cluster_name = coalesce(
    try(data.terraform_remote_state.infra.outputs.eks_cluster_name, null),
    "pet-${var.environment}-clinicc"
  )
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# DNS / ACM Module and k8s add-ons
module "dns" {
  source = "../../modules/dns"

  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  environment               = var.environment
  domain_name               = "*.amitwebsite.online"
  subject_alternative_names = []
  eks_cluster_name          = local.cluster_name
  aws_region                = var.aws_region
  common_tags = {
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
