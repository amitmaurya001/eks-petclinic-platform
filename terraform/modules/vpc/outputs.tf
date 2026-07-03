# outputs.tf - vpc module
# Defines outputs for the VPC module.

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster security group"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "ID of the EKS node security group"
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}