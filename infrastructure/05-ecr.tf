# =============================================================================
# ECR Repository for Service 1 - REST API
# =============================================================================

resource "aws_ecr_repository" "service1" {
  name                 = "${var.project_name}-service1-api"
  image_tag_mutability = "MUTABLE" # Allow overwriting tags (useful for dev)

  # Enable image scanning for security vulnerabilities
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project_name}-service1-api"
    Description = "Docker images for REST API microservice"
  }
}

# Lifecycle policy - keep only last 5 images to save storage (Free tier: 500 MB)
resource "aws_ecr_lifecycle_policy" "service1" {
  repository = aws_ecr_repository.service1.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images only"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# =============================================================================
# ECR Repository for Service 2 - SQS Consumer
# =============================================================================

resource "aws_ecr_repository" "service2" {
  name                 = "${var.project_name}-service2-consumer"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project_name}-service2-consumer"
    Description = "Docker images for SQS consumer microservice"
  }
}

resource "aws_ecr_lifecycle_policy" "service2" {
  repository = aws_ecr_repository.service2.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images only"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}
