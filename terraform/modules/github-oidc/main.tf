# GitHub OIDC Federation — ECR-only IAM role for GitHub Actions CI
# ================================================================
#
# Creates:
#   1. IAM OIDC identity provider for GitHub Actions (token.actions.githubusercontent.com)
#   2. IAM role with OIDC trust policy — Action: sts:AssumeRoleWithWebIdentity
#      Subject: repo:amitmaurya001/eks-spring-petclinic:ref:refs/heads/main (app repo, main branch only)
#   3. ECR-only permission policy — just ecr:GetAuthorizationToken, BatchCheckLayerAvailability,
#      PutImage, layer upload/init/complete.  No ecr:*, no *, no ec2:*.
#
# The CI build workflow runs in the app repo context (eks-spring-petclinic).
# The update-image-tags workflow runs in the platform repo context (petclinic-platform).
# This role is assumed by the app repo's build workflow to push images to ECR.
# The platform repo's update-image-tags workflow uses a separate deployment
# identity for git operations.

# --- OIDC Identity Provider for GitHub Actions ---
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518bbe6f1801d1640c4e87c6e8cfabc2"
  ]

  tags = {
    Name      = "petclinic-github-actions-oidc"
    Project   = "petclinic"
    ManagedBy = "terraform"
  }
}

# --- IAM Role for GitHub Actions (assumed by app repo CI build workflow) ---
resource "aws_iam_role" "github_actions_build_role" {
  name        = "petclinic-github-actions-build-role"
  description = "IAM role assumed by GitHub Actions via OIDC to push ARM64 images to ECR"

  # Action MUST be sts:AssumeRoleWithWebIdentity — OIDC federation protocol
  # sees the JWT from GitHub's OIDC token endpoint, validates it against the
  # OIDC provider's public keys, then maps the 'sub' claim to the Condition below.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Scoped to the application repo (eks-spring-petclinic) on main branch only
            # NOT the platform repo.  The build workflow runs in the app repo context.
            "token.actions.githubusercontent.com:sub" : "repo:amitmaurya001/eks-spring-petclinic:ref:refs/heads/main"
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "petclinic-github-actions-build-role"
    Project   = "petclinic"
    ManagedBy = "terraform"
  }
}

# --- ECR-only permission policy (attached to the role above) ---
data "aws_iam_policy_document" "ecr_push_only" {
  statement {
    sid    = "EcrGetAuthToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    # GetAuthorizationToken is account-level — no resource ARN possible
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    # Per-env ECR repos — both dev and prod
    resources = [
      "arn:aws:ecr:us-east-1:*:repository/petclinic-dev/*",
      "arn:aws:ecr:us-east-1:*:repository/petclinic-prod/*"
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push_only_policy" {
  name   = "ecr-push-only"
  role   = aws_iam_role.github_actions_build_role.name
  policy = data.aws_iam_policy_document.ecr_push_only.json
}

# --- Outputs (for use in GitHub Actions workflows and other Terraform modules) ---
output "github_actions_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_actions_build_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes for ECR push"
  value       = aws_iam_role.github_actions_build_role.arn
}

output "github_actions_build_role_name" {
  description = "Name of the IAM role (for GitHub Actions workflow configuration)"
  value       = aws_iam_role.github_actions_build_role.name
}