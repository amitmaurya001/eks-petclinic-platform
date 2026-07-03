# outputs.tf - eks module
# Defines outputs for the EKS module.

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.cluster_oidc.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "ARN of the node IAM role"
  value       = aws_iam_role.node_role.arn
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = aws_iam_role.ebs_csi_role.arn
}

output "eks_kms_key_arn" {
  description = "ARN of the KMS key used for EKS encryption"
  value       = aws_kms_key.eks.arn
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID created by EKS for the cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}