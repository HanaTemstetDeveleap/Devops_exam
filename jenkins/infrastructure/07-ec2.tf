# =============================================================================
# Jenkins EC2 Instance
# =============================================================================

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.jenkins_instance_type
  subnet_id              = var.private_subnet_ids[0] # First private subnet
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name

  # User data script to install Jenkins
  user_data = file("${path.module}/user-data.sh")

  # Root volume configuration
  root_block_device {
    volume_size           = var.jenkins_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-jenkins-volume"
    }
  }

  # Enable detailed monitoring (for better visibility)
  monitoring = false # Free tier doesn't include detailed monitoring

  # Instance metadata service v2 (more secure)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.project_name}-jenkins"
    Description = "Jenkins CI/CD server"
  }

  # Wait for user data to complete
  lifecycle {
    create_before_destroy = false
  }
}
