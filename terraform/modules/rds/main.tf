# main.tf - rds module
# Creates an RDS MySQL instance with Secrets Manager credentials.

locals {
  name_prefix     = "${var.project}-${var.environment}"
  master_username = "petclinic"

  merged_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Generate random password for RDS master user
resource "random_password" "master_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}|;:,.<>?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Create Secrets Manager secret for RDS credentials
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "petclinic/${var.environment}/rds-credentials"
  description             = "RDS MySQL credentials for ${local.name_prefix}-mysql instance"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = local.merged_tags
}

# Store credentials in Secrets Manager
resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id

  secret_string = jsonencode({
    username = local.master_username
    password = random_password.master_password.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Create DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = local.merged_tags
}

# Create DB parameter group for MySQL 8.0
resource "aws_db_parameter_group" "main" {
  name   = "${local.name_prefix}-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = local.merged_tags
}

# Create RDS MySQL instance
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  db_name  = "petclinic"
  username = local.master_username
  password = random_password.master_password.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage

  storage_encrypted = true
  storage_type      = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [var.security_group_id]

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection

  # Security: RDS instance is not publicly accessible
  # Access controlled via security groups allowing only EKS node SG on port 3306
  publicly_accessible = false

  apply_immediately = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null # Free tier retention if enabled

  tags = local.merged_tags
}