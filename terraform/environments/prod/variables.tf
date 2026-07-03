# variables.tf - prod environment
# Defines input variables for the prod environment.

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
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
  description = "Optional Git password or token for the Spring Cloud Config Server"
  type        = string
  sensitive   = true
  default     = ""
}