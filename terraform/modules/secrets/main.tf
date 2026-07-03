# main.tf - secrets module
# Creates non-RDS application secrets in AWS Secrets Manager and the
# IAM role (IRSA) used by the External Secrets Operator.

locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# -----------------------------------------------------------------------------
# OpenAI API key secret (used by genai-service)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "openai_api_key" {
  name                    = "petclinic/${var.environment}/openai-api-key"
  recovery_window_in_days = 0 # Add this line to force immediate deletion
  description             = "OpenAI API key for the GenAI service"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key

  lifecycle {
    # The real key is expected to be set outside Terraform (e.g. AWS Console).
    # Prevent Terraform from overwriting it on future applies.
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Optional Config Server Git credentials
# Only created when non-empty values are supplied.
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "config_server_git_username" {
  count = var.config_server_git_username != "" ? 1 : 0

  name        = "petclinic/${var.environment}/config-server/git-username"
  description = "Git username for the Spring Cloud Config Server"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "config_server_git_username" {
  count = var.config_server_git_username != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.config_server_git_username[0].id
  secret_string = var.config_server_git_username
}

resource "aws_secretsmanager_secret" "config_server_git_password" {
  count = var.config_server_git_password != "" ? 1 : 0

  name        = "petclinic/${var.environment}/config-server/git-password"
  description = "Git password or token for the Spring Cloud Config Server"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "config_server_git_password" {
  count = var.config_server_git_password != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.config_server_git_password[0].id
  secret_string = var.config_server_git_password
}

# -----------------------------------------------------------------------------
# IRSA role for External Secrets Operator
# Trust policy is scoped to the ESO service account in the external-secrets
# namespace. Permissions are limited to reading petclinic/* secrets.
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role" "eso" {
  name = "${local.name_prefix}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${trimprefix(var.oidc_provider_url, "https://")}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
            "${trimprefix(var.oidc_provider_url, "https://")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "eso" {
  name = "${local.name_prefix}-eso-policy"
  role = aws_iam_role.eso.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "AllowSecretsManagerRead"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret"
          ]
          Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:petclinic/*"
        }
      ],
      var.kms_key_arn != "" ? [
        {
          Sid      = "AllowKMSDecrypt"
          Effect   = "Allow"
          Action   = "kms:Decrypt"
          Resource = var.kms_key_arn
        }
      ] : []
    )
  })
}
