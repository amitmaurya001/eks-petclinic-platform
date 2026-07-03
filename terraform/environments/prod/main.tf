# main.tf - prod environment
# Provides the root module for the prod environment.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

# Retrieve available AZs for the current region
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source              = "../../modules/vpc"
  vpc_cidr_block      = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = slice(data.aws_availability_zones.available.names, 0, 2)
  environment         = var.environment
}

locals {
  cluster_name = "pet-${var.environment}-clinicc"
}

# EKS Module
module "eks" {
  source        = "../../modules/eks"
  environment   = var.environment
  cluster_name  = local.cluster_name
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id

  # Prod-specific configuration
  node_instance_types = ["t4g.small"]
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2
  node_disk_size      = 20
}

# ECR Module
module "ecr" {
  source      = "../../modules/ecr"
  environment = var.environment
  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server"
  ]
}

# RDS Module for MySQL database
module "rds" {
  source = "../../modules/rds"

  project     = "petclinic"
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  # Prod-specific configuration
  secret_recovery_window_in_days = 7
  instance_class                 = "db.t4g.micro"
  allocated_storage              = 20
  max_allocated_storage          = 20
  multi_az                       = false # Note: in real production, enable Multi-AZ
  backup_retention_period        = 1
  skip_final_snapshot            = false
  deletion_protection            = false
}

# Secrets Module for non-RDS application secrets and ESO IRSA role
module "secrets" {
  source = "../../modules/secrets"

  project     = "petclinic"
  environment = var.environment

  openai_api_key             = var.openai_api_key
  config_server_git_username = var.config_server_git_username
  config_server_git_password = var.config_server_git_password

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

# GitHub OIDC Module — IAM OIDC provider + role for GitHub Actions CI
module "github-oidc" {
  source          = "../../modules/github-oidc"
  environment     = var.environment
  app_repo        = "amitmaurya001/eks-spring-petclinic"
  app_repo_branch = "main"
}

