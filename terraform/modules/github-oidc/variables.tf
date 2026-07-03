# GitHub OIDC Module — Variables
# ===============================

variable "environment" {
  description = "Environment name (dev or prod) — used for tagging"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "app_repo" {
  description = "GitHub repository name (owner/repo) where the CI build workflow runs"
  type        = string
  default     = "amitmaurya001/eks-spring-petclinic"
}

variable "app_repo_branch" {
  description = "Branch in the app repo that is allowed to assume the OIDC role"
  type        = string
  default     = "main"
}