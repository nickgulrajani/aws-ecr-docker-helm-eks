#############################################
# Scenario 4 — Microservices Dry Run Setup
# Focus: ECR + lifecycle policy + CI/CD simulation
#############################################

locals {
  repo_prefix = "${var.name_prefix}-${var.environment}"
}

# --------------------------------------------------
# ECR Repositories for Microservices
# --------------------------------------------------
resource "aws_ecr_repository" "svc" {
  for_each = toset(var.ecr_repos)

  name                 = "${local.repo_prefix}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true # Plan-safe; deletes images if applied (no costs in dry-run)

  tags = {
    Name = "${local.repo_prefix}-${each.key}"
  }
}

# --------------------------------------------------
# ECR Lifecycle Policy
# --------------------------------------------------
resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --------------------------------------------------
# Optional: EKS Cluster (disabled in dry-run)
# --------------------------------------------------
# resource "aws_eks_cluster" "this" {
#   count    = var.enable_eks ? 1 : 0
#   name     = "${var.name_prefix}-eks-${var.environment}"
#   role_arn = "arn:aws:iam::111111111111:role/placeholder-eks-role"
#   vpc_config {
#     subnet_ids = ["subnet-aaaa1111", "subnet-bbbb2222"]
#   }
#   tags = {
#     Name = "${var.name_prefix}-eks-${var.environment}"
#   }
# }
