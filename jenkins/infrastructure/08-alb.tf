# =============================================================================
# Application Load Balancer for Jenkins
# =============================================================================

resource "aws_lb" "jenkins" {
  name               = "${var.project_name}-jenkins-alb"
  internal           = false # Public-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jenkins_alb.id]
  subnets            = var.public_subnet_ids # Must be in public subnets

  enable_deletion_protection = false # Allow deletion (for dev/testing)

  tags = {
    Name        = "${var.project_name}-jenkins-alb"
    Description = "Load balancer for Jenkins"
  }
}

# =============================================================================
# Target Group for Jenkins
# =============================================================================

resource "aws_lb_target_group" "jenkins" {
  name        = "${var.project_name}-jenkins-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/login" # Jenkins login page
    protocol            = "HTTP"
    matcher             = "200"
  }

  # Deregistration delay
  deregistration_delay = 30

  # Stickiness for Jenkins sessions
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours
    enabled         = true
  }

  tags = {
    Name        = "${var.project_name}-jenkins-tg"
    Description = "Target group for Jenkins"
  }
}

# =============================================================================
# Target Group Attachment
# =============================================================================

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
  port             = 8080
}

# =============================================================================
# Listener - HTTP on port 80
# =============================================================================

resource "aws_lb_listener" "jenkins_http" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  # Default action - forward to Jenkins
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  tags = {
    Name = "${var.project_name}-jenkins-http-listener"
  }
}
