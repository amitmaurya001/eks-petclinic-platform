# outputs.tf - secrets module
# Defines outputs for the Secrets module.

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key"
  value       = aws_secretsmanager_secret.openai_api_key.arn
  sensitive   = true
}

output "config_server_git_username_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git username (empty if not created)"
  value       = length(aws_secretsmanager_secret.config_server_git_username) > 0 ? aws_secretsmanager_secret.config_server_git_username[0].arn : ""
  sensitive   = true
}

output "config_server_git_password_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git password (empty if not created)"
  value       = length(aws_secretsmanager_secret.config_server_git_password) > 0 ? aws_secretsmanager_secret.config_server_git_password[0].arn : ""
  sensitive   = true
}

output "eso_role_arn" {
  description = "ARN of the External Secrets Operator IRSA role"
  value       = aws_iam_role.eso.arn
  sensitive   = true
}

output "eso_role_name" {
  description = "Name of the External Secrets Operator IRSA role"
  value       = aws_iam_role.eso.name
  sensitive   = true
}
