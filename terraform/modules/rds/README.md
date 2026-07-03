# RDS Module

Terraform module to provision an RDS MySQL instance for the Petclinic Platform.

## Overview

This module creates a MySQL 8.0 RDS instance with:
- Automated Secrets Manager integration for credentials
- Secure configuration with encryption enabled
- Configurable backup and retention policies
- Subnet group and parameter group creation
- Performance Insights enabled with 7-day retention (free tier)

## Usage

```hcl
module "rds" {
  source = "../../modules/rds"
  
  project     = "petclinic"
  environment = "dev"  # or "prod"
  
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_id  = module.vpc.rds_sg_id
  
  # Configuration (override defaults as needed)
  instance_class             = "db.t4g.micro"
  allocated_storage         = 10
  max_allocated_storage     = 20
  multi_az                 = false
  backup_retention_period  = 1
  skip_final_snapshot      = true  # false for prod
  deletion_protection      = false
  
  tags = {
    # Additional tags (optional)
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project` | Project name | `string` | `"petclinic"` | yes |
| `environment` | Environment (dev or prod) | `string` | - | yes |
| `subnet_ids` | Subnet IDs for DB subnet group | `list(string)` | - | yes |
| `security_group_id` | RDS security group ID | `string` | - | yes |
| `instance_class` | RDS instance class | `string` | `"db.t4g.micro"` | no |
| `allocated_storage` | Initial storage in GB | `number` | `10` | no |
| `max_allocated_storage` | Max autoscale storage in GB | `number` | `20` | no |
| `multi_az` | Multi-AZ deployment | `bool` | `false` | no |
| `backup_retention_period` | Backup retention in days (0-1) | `number` | `1` | no |
| `skip_final_snapshot` | Skip final snapshot on delete | `bool` | `true` | no |
| `deletion_protection` | Deletion protection | `bool` | `false` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| `endpoint` | RDS endpoint hostname | `true` |
| `port` | RDS port (3306) | `false` |
| `db_instance_id` | RDS instance ID | `false` |
| `secret_arn` | Secrets Manager ARN for RDS credentials | `false` |
| `jdbc_connection_template` | Template for JDBC connection string | `true` |

## Database Details

### Shared Database
- Database name: `petclinic`
- Master username: `petclinic`
- Password: Auto-generated 16-character random password with special characters
- Character set: `utf8mb4`
- Collation: `utf8mb4_unicode_ci`

### Security
- Storage encrypted: `true` (AWS default KMS key)
- Publicly accessible: `false`
- Access controlled by security groups only
- Performance Insights: `true` with 7-day retention (free tier)

### Credentials Management
Credentials are managed via AWS Secrets Manager:
- Secret name: `petclinic/{env}/rds-credentials`
- Secret format: JSON with `username` and `password` keys
- Terraform generates random password and stores it in Secrets Manager
- No credentials stored in Terraform state

## Environment-Specific Configuration

### Development Environment
```hcl
backup_retention_period = 1
skip_final_snapshot    = true
```

### Production Environment
```hcl
backup_retention_period = 1
skip_final_snapshot    = false
```

## Cost Optimization

For learning projects (this configuration):
- Instance class: `db.t4g.micro` (RDS free tier eligible, 750 hrs/month for 12 months)
- Multi-AZ: `false` (single AZ to save cost)
- Storage: `gp3` (cost-effective)

For production deployments:
- Use larger instance class (e.g., `db.r7g.large`)
- Set `multi_az = true` for high availability
- Increase backup retention to 30+ days
- Enable deletion protection

## Dependencies

This module depends on:
- VPC module for subnets and security groups
- Security group must allow port 3306 from EKS nodes only
- IAM permissions for Secrets Manager operations

## Notes

1. The shared `petclinic` database is used by all three database-backed services (customers, visits, vets)
2. Foreign key dependencies exist between services (`visits.pet_id` → `pets.id`)
3. Database initialization order matters: customers → vets → visits
4. Performance Insights uses 7-day retention (free tier) and provides valuable monitoring
5. Always test `terraform plan` before applying changes to RDS