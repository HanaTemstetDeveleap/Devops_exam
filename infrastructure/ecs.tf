# =============================================================================
# ECS Cluster - Container orchestration platform
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # Disable to save costs (not in free tier)
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Description = "ECS Fargate cluster for microservices"
  }
}

# =============================================================================
# CloudWatch Log Groups - For container logs
# =============================================================================

resource "aws_cloudwatch_log_group" "service1" {
  name              = "/ecs/${var.project_name}/service1"
  retention_in_days = 7 # Keep logs for 7 days (free tier: 5GB)

  tags = {
    Name = "${var.project_name}-service1-logs"
  }
}

resource "aws_cloudwatch_log_group" "service2" {
  name              = "/ecs/${var.project_name}/service2"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-service2-logs"
  }
}

# =============================================================================
# Service 1 - Task Definition (REST API)
# =============================================================================

resource "aws_ecs_task_definition" "service1" {
  family                   = "${var.project_name}-service1"
  network_mode             = "awsvpc" # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU (Free tier eligible)
  memory                   = "512"  # 0.5 GB RAM (Free tier eligible)

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.service1_task.arn

  container_definitions = jsonencode([{
    name  = "service1-api"
    image = "${aws_ecr_repository.service1.repository_url}:latest"

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "SSM_PARAMETER_NAME"
        value = aws_ssm_parameter.api_token.name
      },
      {
        name  = "SQS_QUEUE_URL"
        value = aws_sqs_queue.messages.url
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service1.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    essential = true
  }])

  tags = {
    Name        = "${var.project_name}-service1-task"
    Description = "Task definition for REST API service"
  }
}

# =============================================================================
# Service 2 - Task Definition (SQS Consumer)
# =============================================================================

resource "aws_ecs_task_definition" "service2" {
  family                   = "${var.project_name}-service2"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 0.5 GB RAM

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.service2_task.arn

  container_definitions = jsonencode([{
    name  = "service2-consumer"
    image = "${aws_ecr_repository.service2.repository_url}:latest"

    environment = [
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "SQS_QUEUE_URL"
        value = aws_sqs_queue.messages.url
      },
      {
        name  = "S3_BUCKET_NAME"
        value = aws_s3_bucket.messages.id
      },
      {
        name  = "POLL_INTERVAL"
        value = "10"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service2.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    essential = true
  }])

  tags = {
    Name        = "${var.project_name}-service2-task"
    Description = "Task definition for SQS consumer service"
  }
}

# =============================================================================
# Service 1 - ECS Service (with ALB integration)
# =============================================================================

resource "aws_ecs_service" "service1" {
  name            = "${var.project_name}-service1"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.service1.arn
  desired_count   = 1 # Number of tasks to run
  launch_type     = "FARGATE"

  # Network configuration - private subnets with ALB
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.service1.id]
    assign_public_ip = false # No public IP - private subnet
  }

  # Load balancer configuration
  load_balancer {
    target_group_arn = aws_lb_target_group.service1.arn
    container_name   = "service1-api"
    container_port   = 8080
  }

  # Wait for ALB to be ready before creating service
  depends_on = [aws_lb_listener.http]

  tags = {
    Name        = "${var.project_name}-service1-svc"
    Description = "ECS service for REST API"
  }
}

# =============================================================================
# Service 2 - ECS Service (standalone, no ALB)
# =============================================================================

resource "aws_ecs_service" "service2" {
  name            = "${var.project_name}-service2"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.service2.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Network configuration - private subnets, no load balancer
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.service2.id]
    assign_public_ip = false
  }

  tags = {
    Name        = "${var.project_name}-service2-svc"
    Description = "ECS service for SQS consumer"
  }
}
