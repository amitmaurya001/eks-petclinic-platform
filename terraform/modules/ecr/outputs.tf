# outputs.tf - ecr module
# Defines outputs for the ECR module.

output "repository_urls" {
  description = "Map of service names to repository URLs"
  value       = { for k, v in aws_ecr_repository.repo : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of service names to repository ARNs"
  value       = { for k, v in aws_ecr_repository.repo : k => v.arn }
}