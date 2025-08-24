variable "project" {
  type        = string
  default     = "microservices-standard"
  description = "Name of the project"
}

variable "environment" {
  type        = string
  default     = "dryrun"
  description = "Environment name, e.g. dev, staging, prod"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region where dry-run resources would hypothetically be created"
}

variable "name_prefix" {
  type        = string
  default     = "ms"
  description = "Prefix for resource names"
}

variable "ecr_repos" {
  type        = list(string)
  default     = ["orders", "billing"]
  description = "List of ECR repositories for microservices"
}

variable "enable_eks" {
  type        = bool
  default     = false
  description = "EKS is disabled in dry-run mode to prevent costs"
}

