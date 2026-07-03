# outputs.tf - rds module
# Defines outputs for the RDS module.

output "endpoint" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "port" {
  description = "RDS port (3306)"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.identifier
}

output "secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}

output "jdbc_connection_template" {
  description = "Template for JDBC connection string"
  value       = "jdbc:mysql://${aws_db_instance.main.endpoint}/petclinic"
  sensitive   = true
}