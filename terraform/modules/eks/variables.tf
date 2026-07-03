# variables.tf - eks module
# Defines input variables for the EKS module.

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

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Defaults to petclinic-<environment>."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs where the EKS cluster will be deployed"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}


variable "node_instance_types" {
  description = "List of instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the managed nodes"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk size in GB for node instances"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}