# =============================================================================
# ECS Task Execution Role - Required for ECS to pull images and write logs
# =============================================================================

# Trust policy - allows ECS to assume this role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-execution-role"
    Description = "Allows ECS to pull images from ECR and write logs"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch read permissions for Grafana (monitoring dashboards)
resource "aws_iam_role_policy" "grafana_cloudwatch_read" {
  name = "${var.project_name}-grafana-cloudwatch-read"
  role = aws_iam_role.ecs_task_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["tag:GetResources"]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# Service 1 Task Role - Permissions for the REST API application
# =============================================================================

resource "aws_iam_role" "service1_task" {
  name = "${var.project_name}-service1-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-service1-task-role"
    Description = "Permissions for Service 1 REST API"
  }
}

# Service 1 Policy - ONLY what it needs
resource "aws_iam_role_policy" "service1_task" {
  name = "${var.project_name}-service1-policy"
  role = aws_iam_role.service1_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",           # Send messages to SQS
          "sqs:GetQueueUrl"            # Get queue URL
        ]
        Resource = aws_sqs_queue.messages.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"           # Read token from SSM
        ]
        Resource = aws_ssm_parameter.api_token.arn
      }
    ]
  })
}

# =============================================================================
# Service 2 Task Role - Permissions for the SQS Consumer application
# =============================================================================

resource "aws_iam_role" "service2_task" {
  name = "${var.project_name}-service2-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-service2-task-role"
    Description = "Permissions for Service 2 SQS Consumer"
  }
}

# Service 2 Policy - ONLY what it needs
resource "aws_iam_role_policy" "service2_task" {
  name = "${var.project_name}-service2-policy"
  role = aws_iam_role.service2_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",        # Receive messages from SQS
          "sqs:DeleteMessage",         # Delete processed messages
          "sqs:GetQueueUrl",           # Get queue URL
          "sqs:GetQueueAttributes"     # Get queue attributes
        ]
        Resource = aws_sqs_queue.messages.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",              # Upload files to S3
          "s3:PutObjectAcl"            # Set object ACL
        ]
        Resource = "${aws_s3_bucket.messages.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"              # List bucket contents
        ]
        Resource = aws_s3_bucket.messages.arn
      }
    ]
  })
}
