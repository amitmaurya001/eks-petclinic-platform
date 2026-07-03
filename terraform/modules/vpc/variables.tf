# variables.tf - vpc module
# Defines input variables for the VPC module.

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "environment" {
  description = "Environment tag (dev or prod)"
  type        = string
}

variable "eks_cluster_security_group_id" {
  description = "Optional: EKS cluster security group ID for RDS access"
  type        = string
  default     = null
}