# =============================================================================
# SSM Parameter Store - Secure storage for API token
# =============================================================================

resource "aws_ssm_parameter" "api_token" {
  name        = "/${var.project_name}/${var.environment}/api-token"
  description = "API token for validating incoming requests to service1"
  type        = "SecureString" # Encrypted at rest using AWS KMS
  value       = var.api_token

  tags = {
    Name        = "${var.project_name}-api-token"
    Description = "Secure token for API authentication"
  }
}
