# variables.tf - observability module
# Defines input variables for the Observability module.

variable "environment" {
  description = "Environment tag (dev or prod)"
  type        = string
}