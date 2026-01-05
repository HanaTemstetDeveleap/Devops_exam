# =============================================================================
# General Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name - used as prefix for all resources"
  type        = string
  default     = "devops-exam"
}

# =============================================================================
# Security Variables
# =============================================================================

variable "api_token" {
  description = "API token for request validation - stored securely in SSM Parameter Store"
  type        = string
  # No default value - must be provided explicitly for security
  # This ensures tokens are never hardcoded and are properly managed
  sensitive   = true # Prevents token from appearing in logs
}

# =============================================================================
# Networking Variables
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC - private network range"
  type        = string
  default     = "10.0.0.0/16" # Provides 65,536 IP addresses
}

variable "availability_zones" {
  description = "AZs for high availability - resources spread across multiple data centers"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"] # Minimum 2 AZs for ELB
}
