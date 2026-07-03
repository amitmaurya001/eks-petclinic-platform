# variables.tf - secrets module
# Defines input variables for the Secrets module.

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
    error_message = "Environment must be either 'dev' or 'prod'."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key value for the GenAI service. Defaults to a placeholder that must be replaced."
  type        = string
  sensitive   = true
  default     = "REPLACE_ME"
}

variable "config_server_git_username" {
  description = "Optional Git username for the Spring Cloud Config Server"
  type        = string
  sensitive   = true
  default     = ""
}

variable "config_server_git_password" {
  description = "Optional Git password or personal access token for the Spring Cloud Config Server"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider used for the ESO IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider used for the ESO IRSA trust policy"
  type        = string
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN used to encrypt Secrets Manager secrets. If provided, the ESO IRSA role receives kms:Decrypt."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
