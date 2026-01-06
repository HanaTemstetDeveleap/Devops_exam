# =============================================================================
# Monitoring - Prometheus + Grafana on ECS (minimal example)
# =============================================================================

# CloudWatch log groups for monitoring containers
resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/${var.project_name}/prometheus"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project_name}/grafana"
  retention_in_days = 7
}

# Security group for monitoring services
resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Security group for Prometheus and Grafana"
  vpc_id      = aws_vpc.main.id

  # Grafana (port 3000) - allow from internet for exam access
  ingress {
    description = "Grafana HTTP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus (port 9090) - allow from internet (optionally restrict)
  ingress {
    description = "Prometheus HTTP"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-monitoring-sg"
  }
}

# =============================================================================
# Prometheus - Task definition and service
# NOTE: This is a minimal deployment. To configure scrape jobs, upload a
# `prometheus.yml` configuration and mount it via EFS or a custom image.
# =============================================================================

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.project_name}-prometheus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "prometheus"
    image = "${aws_ecr_repository.prometheus.repository_url}:latest"

    portMappings = [{
      containerPort = 9090
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.prometheus.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "prometheus"
      }
    }

    essential = true
  }])

  tags = {
    Name = "${var.project_name}-prometheus-task"
  }
}

resource "aws_ecs_service" "prometheus" {
  name            = "${var.project_name}-prometheus"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.monitoring.id]
    assign_public_ip = false
  }

  # Service Discovery - Register with Cloud Map
  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }

  tags = {
    Name = "${var.project_name}-prometheus-svc"
  }
}

# =============================================================================
# Grafana - Task definition and service
# Grafana will be reachable publicly on port 3000 (for the exam reviewer)
# =============================================================================

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "grafana"
    image = "grafana/grafana:latest"

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "GF_SECURITY_ADMIN_PASSWORD"
        value = "admin"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "grafana"
      }
    }

    essential = true
  }])

  tags = {
    Name = "${var.project_name}-grafana-task"
  }
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.monitoring.id]
    assign_public_ip = true
  }

  tags = {
    Name = "${var.project_name}-grafana-svc"
  }
}

# =============================================================================
# Notes
# - Prometheus requires a scrape config (`prometheus.yml`) to scrape the
#   services' `/metrics` endpoints. For a production setup, add an EFS volume
#   or custom image that contains the config, and mount it into the Prometheus
#   container. For the exam, Prometheus will run but needs a config to scrape.
# - Grafana uses default credentials `admin:admin` (admin password set to "admin").
#   Change in production.
# - We open Grafana and Prometheus ports to the internet for reviewer access.
#   To restrict access, replace `cidr_blocks = ["0.0.0.0/0"]` with your office IPs.
# =============================================================================
