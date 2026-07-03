# variables.tf - dns module
# Defines input variables for ACM certificate, DNS/ingress, and provider configuration.

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name for the ACM certificate"
  type        = string
}

variable "subject_alternative_names" {
  description = "Subject alternative names for the ACM certificate"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to merge with default ACM certificate tags"
  type        = map(string)
  default     = {}
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster used by the ALB controller and Kubernetes/Helm providers"
  type        = string
}

variable "aws_region" {
  description = "AWS region for provider configuration and the AWS Load Balancer Controller"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  description = "Common tags to apply to resources created in this module"
  type        = map(string)
  default     = {}
}
