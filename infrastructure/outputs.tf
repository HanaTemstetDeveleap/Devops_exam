# =============================================================================
# ECR Outputs - Docker image repositories
# =============================================================================

output "ecr_service1_repository_url" {
  description = "URL of ECR repository for service 1 (REST API)"
  value       = aws_ecr_repository.service1.repository_url
}

output "ecr_service2_repository_url" {
  description = "URL of ECR repository for service 2 (SQS Consumer)"
  value       = aws_ecr_repository.service2.repository_url
}

# =============================================================================
# S3 Outputs - Message storage
# =============================================================================

output "s3_bucket_name" {
  description = "Name of S3 bucket for storing messages"
  value       = aws_s3_bucket.messages.id
}

output "s3_bucket_arn" {
  description = "ARN of S3 bucket"
  value       = aws_s3_bucket.messages.arn
}

# =============================================================================
# SQS Outputs - Message queue
# =============================================================================

output "sqs_queue_url" {
  description = "URL of SQS queue for message passing"
  value       = aws_sqs_queue.messages.url
}

output "sqs_queue_arn" {
  description = "ARN of SQS queue"
  value       = aws_sqs_queue.messages.arn
}

# =============================================================================
# SSM Outputs - Token storage
# =============================================================================

output "ssm_parameter_name" {
  description = "Name of SSM parameter storing the API token"
  value       = aws_ssm_parameter.api_token.name
}
