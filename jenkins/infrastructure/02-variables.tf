# =============================================================================
# Variables for Jenkins Infrastructure
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name - used for resource naming"
  type        = string
  default     = "devops-exam"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# VPC Configuration - imported from main infrastructure
variable "vpc_id" {
  description = "VPC ID from main infrastructure"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from main infrastructure"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from main infrastructure"
  type        = list(string)
}

# Jenkins Configuration
variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.small" # Jenkins needs more than t3.micro
}

variable "jenkins_volume_size" {
  description = "EBS volume size for Jenkins in GB"
  type        = number
  default     = 20 # Enough for Jenkins + Docker images
}

# ECR Configuration - needed for Jenkins to push images
variable "ecr_repository_urls" {
  description = "ECR repository URLs"
  type = object({
    service1 = string
    service2 = string
  })
}

# ECS Configuration - needed for Jenkins to update services
variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_names" {
  description = "ECS service names"
  type = object({
    service1 = string
    service2 = string
  })
}
