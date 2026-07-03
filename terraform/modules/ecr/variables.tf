# variables.tf - ecr module
# Defines input variables for the ECR module.

variable "service_names" {
  description = "List of Petclinic service names"
  type        = list(string)
}

variable "environment" {
  description = "Environment tag (dev or prod)"
  type        = string
}