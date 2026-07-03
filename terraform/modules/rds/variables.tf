# variables.tf - rds module
# Defines input variables for the RDS module.

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment tag (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either 'dev' or 'prod'"
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for DB subnet group"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS security group ID. Must restrict access to port 3306 from EKS nodes only"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB (minimum 20 for MySQL gp3)"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "MySQL gp3 storage requires at least 20GB"
  }
}

variable "max_allocated_storage" {
  description = "Max autoscale storage in GB"
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention in days"
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 1
    error_message = "Backup retention must be between 0 and 1 days"
  }
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on delete"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Deletion protection"
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights (not supported on db.t4g.micro)"
  type        = bool
  default     = false
}

variable "secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window in days. 0 = immediate deletion."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}