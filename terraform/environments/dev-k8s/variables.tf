# variables.tf - dev-k8s environment
# Defines input variables for the dev-k8s add-ons root module.

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster to configure. Defaults to the cluster name from the dev Terraform state."
  type        = string
  default     = ""
}
