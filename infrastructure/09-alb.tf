# =============================================================================
# Application Load Balancer - Public entry point to Service 1
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false # Public-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # Must be in public subnets

  enable_deletion_protection = false # Allow deletion (for dev/testing)

  tags = {
    Name        = "${var.project_name}-alb"
    Description = "Load balancer for Service 1 REST API"
  }
}

# =============================================================================
# Target Group - Defines how ALB routes to Service 1
# =============================================================================

resource "aws_lb_target_group" "service1" {
  name        = "${var.project_name}-service1-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for Fargate

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2 # Number of consecutive successful checks
    unhealthy_threshold = 3 # Number of consecutive failed checks
    timeout             = 5
    interval            = 30
    path                = "/health" # Health check endpoint in Service 1
    protocol            = "HTTP"
    matcher             = "200" # Expected response code
  }

  # Deregistration delay - wait before removing unhealthy targets
  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-service1-tg"
    Description = "Target group for Service 1 containers"
  }
}

# =============================================================================
# Listener - Listens on port 80 and forwards to target group
# =============================================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action - forward all traffic to Service 1
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service1.arn
  }

  tags = {
    Name = "${var.project_name}-http-listener"
  }
}
