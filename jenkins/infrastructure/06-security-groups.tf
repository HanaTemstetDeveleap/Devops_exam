# =============================================================================
# Security Groups for Jenkins
# =============================================================================

# Security Group for Jenkins ALB
resource "aws_security_group" "jenkins_alb" {
  name        = "${var.project_name}-jenkins-alb-sg"
  description = "Security group for Jenkins Application Load Balancer"
  vpc_id      = var.vpc_id

  # Allow HTTP from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS from anywhere (for future SSL)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound to Jenkins instance
  egress {
    description = "Allow outbound to Jenkins"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-jenkins-alb-sg"
    Description = "Allows HTTP/HTTPS from internet to Jenkins"
  }
}

# Security Group for Jenkins EC2 instance
resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins EC2 instance"
  vpc_id      = var.vpc_id

  # Allow Jenkins port from ALB only
  ingress {
    description     = "Jenkins UI from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_alb.id]
  }

  # Allow SSH from VPC (for debugging)
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  # Allow all outbound (for downloading packages, Docker images, AWS API calls)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-jenkins-sg"
    Description = "Allows traffic from ALB and SSH from VPC"
  }
}
