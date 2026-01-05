# =============================================================================
# Outputs for Jenkins Infrastructure
# =============================================================================

output "jenkins_alb_dns" {
  description = "DNS name of Jenkins ALB - USE THIS TO ACCESS JENKINS"
  value       = aws_lb.jenkins.dns_name
}

output "jenkins_url" {
  description = "Full URL to access Jenkins"
  value       = "http://${aws_lb.jenkins.dns_name}"
}

output "jenkins_instance_id" {
  description = "EC2 instance ID of Jenkins server"
  value       = aws_instance.jenkins.id
}

output "jenkins_private_ip" {
  description = "Private IP of Jenkins instance"
  value       = aws_instance.jenkins.private_ip
}

output "jenkins_initial_password_command" {
  description = "Command to get Jenkins initial admin password from SSM"
  value       = "aws ssm get-parameter --name /jenkins/initial-admin-password --with-decryption --query 'Parameter.Value' --output text --region us-east-1"
}

output "jenkins_setup_instructions" {
  description = "Instructions to complete Jenkins setup"
  value       = <<-EOT

    ============================================================================
    JENKINS SETUP INSTRUCTIONS
    ============================================================================

    1. Wait 3-5 minutes for Jenkins to install and start

    2. Access Jenkins at: http://${aws_lb.jenkins.dns_name}

    3. Get initial admin password from SSM Parameter Store:
       aws ssm get-parameter --name /jenkins/initial-admin-password --with-decryption --query 'Parameter.Value' --output text --region us-east-1

    4. Complete the Jenkins setup wizard:
       - Install suggested plugins
       - Create admin user
       - Configure Jenkins URL

    5. Install additional plugins (Manage Jenkins -> Plugins):
       - Docker Pipeline
       - Amazon ECR
       - CloudBees AWS Credentials

    6. Add AWS credentials in Jenkins (Manage Jenkins -> Credentials)
       - The instance already has IAM role for ECR and ECS

    ============================================================================
  EOT
}
