# outputs.tf - prod environment
# Defines outputs for the prod environment.

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID for the environment"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster security group"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "ID of the EKS node security group"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = module.vpc.alb_sg_id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.internet_gateway_id
}

# EKS outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
  sensitive   = false
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "eks_cluster_ca_certificate" {
  description = "CA certificate for the EKS cluster"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = module.eks.oidc_provider_url
}

output "eks_node_group_name" {
  description = "Name of the managed node group"
  value       = module.eks.node_group_name
}

output "eks_node_role_arn" {
  description = "ARN of the node IAM role"
  value       = module.eks.node_role_arn
}

output "eks_kubeconfig_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "eks_ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = module.eks.ebs_csi_role_arn
}

# RDS outputs
output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = module.rds.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "RDS MySQL instance ID"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS credentials"
  value       = module.rds.secret_arn
}

# Secrets module outputs (used by prod-k8s add-on environment)
output "secrets_openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key"
  value       = module.secrets.openai_secret_arn
  sensitive   = true
}

output "secrets_config_server_git_username_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git username (empty if not created)"
  value       = module.secrets.config_server_git_username_secret_arn
  sensitive   = true
}

output "secrets_config_server_git_password_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git password (empty if not created)"
  value       = module.secrets.config_server_git_password_secret_arn
  sensitive   = true
}

output "secrets_eso_role_arn" {
  description = "ARN of the External Secrets Operator IRSA role"
  value       = module.secrets.eso_role_arn
  sensitive   = true
}

output "secrets_eso_role_name" {
  description = "Name of the External Secrets Operator IRSA role"
  value       = module.secrets.eso_role_name
  sensitive   = true
}

# GitHub OIDC outputs
output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = module.github-oidc.github_actions_oidc_provider_arn
}

output "github_actions_build_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes for ECR push"
  value       = module.github-oidc.github_actions_build_role_arn
}

output "github_actions_build_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = module.github-oidc.github_actions_build_role_name
}

