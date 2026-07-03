# main.tf - ecr module
# Creates ECR repositories for Petclinic services.

resource "aws_ecr_repository" "repo" {
  for_each = toset(var.service_names)
  name     = "petclinic-${var.environment}/${each.key}"

  image_tag_mutability = var.environment == "prod" ? "IMMUTABLE" : "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Configure lifecycle policy to keep last 10 images and expire untagged after 7 days
resource "aws_ecr_lifecycle_policy" "repo_policy" {
  for_each   = toset(var.service_names)
  repository = aws_ecr_repository.repo[each.key].name

  policy = <<POLICY
{
  "rules": [
    {
      "rulePriority": 2,
      "description": "Expire all tagged images when count exceeds 10",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 1,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
POLICY
}