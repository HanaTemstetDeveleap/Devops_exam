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

output "ecr_prometheus_repository_url" {
  description = "URL of ECR repository for Prometheus (Custom image with scrape config)"
  value       = aws_ecr_repository.prometheus.repository_url
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

# =============================================================================
# VPC Outputs - Network information
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

# =============================================================================
# ALB Outputs - Load balancer information
# =============================================================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer - USE THIS TO ACCESS SERVICE 1"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "Full URL to access Service 1 API"
  value       = "http://${aws_lb.main.dns_name}"
}

# =============================================================================
# ECS Outputs - Cluster and service information
# =============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service1_name" {
  description = "Name of Service 1 ECS service"
  value       = aws_ecs_service.service1.name
}

output "ecs_service2_name" {
  description = "Name of Service 2 ECS service"
  value       = aws_ecs_service.service2.name
}

# =============================================================================
# Monitoring Outputs - Prometheus and Grafana access (for exam reviewers)
# =============================================================================

output "grafana_public_ip" {
  description = "Public IP of Grafana - Access at http://<IP>:3000 (admin/admin)"
  value       = "Check ECS console for Grafana task's public IP"
}

output "grafana_instructions" {
  description = "Instructions to access Grafana dashboard"
  value       = <<-EOT
    1. Go to AWS ECS Console -> Clusters -> devops-exam-cluster
    2. Find the task running 'devops-exam-grafana' service
    3. Click on the task and find the Public IP
    4. Access Grafana at: http://<PUBLIC_IP>:3000
    5. Default credentials: admin / admin
    6. Add Prometheus data source: http://prometheus.local:9090
  EOT
}

output "prometheus_service_discovery" {
  description = "Service discovery DNS names for monitoring"
  value = {
    namespace   = aws_service_discovery_private_dns_namespace.main.name
    service1    = "service1.local:8080"
    service2    = "service2.local:8000"
    prometheus  = "prometheus accessible only within VPC"
  }
}
