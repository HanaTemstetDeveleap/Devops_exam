# Infrastructure - AWS Microservices Platform

### First deployment

On the first `terraform apply`, ECR repositories are created but container images do not exist yet.
Therefore, ECS services are created with `desired_count = 0`.

After CI builds and pushes the images to ECR, run the CD workflow and then set `desired_count = 1` and apply Terraform again.


This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete microservices platform on AWS.

## Architecture Overview

The infrastructure provisions two microservices that communicate asynchronously:

```
┌──────────────┐      ┌─────────────┐      ┌─────────────┐      ┌──────────────┐
│   Internet   │─────▶│     ALB     │─────▶│  Service 1  │─────▶│  SQS Queue   │
└──────────────┘      └─────────────┘      │  (REST API) │      └──────┬───────┘
                                            └─────────────┘             │
                                                                        │
                      ┌──────────────┐      ┌─────────────┐            │
                      │  S3 Bucket   │◀─────│  Service 2  │◀───────────┘
                      └──────────────┘      │ (Consumer)  │
                                            └─────────────┘
```

### Components

- **Service 1 (REST API)**: Receives HTTP POST requests, validates tokens, sends messages to SQS
- **Service 2 (SQS Consumer)**: Polls SQS, processes messages, saves them to S3
- **Application Load Balancer (ALB)**: Public-facing entry point for Service 1
- **SQS Queue**: Decouples services with reliable message passing
- **S3 Bucket**: Persistent storage for processed messages
- **VPC**: Isolated network with public and private subnets
- **ECS Fargate**: Serverless container orchestration

## File Organization

Files are numbered in logical reading order based on dependencies:

| File | Description |
|------|-------------|
| `01-provider.tf` | AWS provider configuration and required Terraform version |
| `02-variables.tf` | Input variables with descriptions and default values |
| `03-vpc.tf` | VPC, subnets, NAT gateway, VPC endpoints, security groups |
| `04-iam.tf` | IAM roles and policies for ECS tasks |
| `05-ecr.tf` | Docker image repositories for both services |
| `06-s3.tf` | S3 bucket for message storage with versioning |
| `07-sqs.tf` | SQS queue with dead-letter queue (DLQ) |
| `08-ssm.tf` | SSM Parameter Store for secure API token storage |
| `09-alb.tf` | Application Load Balancer with target group |
| `10-ecs.tf` | ECS cluster, task definitions, and services |
| `11-outputs.tf` | Output values (URLs, ARNs, IDs) |

## Prerequisites

### Required Tools

- **Terraform**: v1.0+ ([Install Guide](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI**: v2.0+ ([Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **Docker**: v20.0+ ([Install Guide](https://docs.docker.com/get-docker/))

### AWS Account Setup

1. **AWS Account**: Free Tier eligible account
2. **AWS Credentials**: Configure credentials with required permissions
   ```bash
   aws configure
   ```
3. **Required IAM Permissions**:
   - VPC, EC2, ECS, ECR, S3, SQS, SSM, IAM, CloudWatch Logs

## Deployment Guide

### Step 1: Build and Push Docker Images

Before deploying infrastructure, build and push the microservice images to ECR:

```bash
# Navigate to project root
cd ..

# Build Service 1 (REST API)
cd microservices/service1-api
docker build -t devops-exam-service1:latest .

# Build Service 2 (SQS Consumer)
cd ../service2-consumer
docker build -t devops-exam-service2:latest .

# Return to infrastructure directory
cd ../../infrastructure
```

### Step 2: Initialize Terraform

```bash
terraform init
```

This downloads required providers and initializes the backend.

### Step 3: Review Variables

Check [02-variables.tf](02-variables.tf:1) for configurable parameters:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region | `us-east-1` | No |
| `environment` | Environment name | `dev` | No |
| `project_name` | Project prefix | `devops-exam` | No |
| `api_token` | API authentication token | - | **Yes** |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` | No |
| `availability_zones` | AZs for HA | `["us-east-1a", "us-east-1b"]` | No |

### Step 4: Set API Token

The `api_token` variable is **required** and has no default for security:

```bash
# Option 1: Export as environment variable
export TF_VAR_api_token='XXXXXXXXXXXXX'

# Option 2: Pass via command line
terraform plan -var='api_token=XXXXXXXXXXXXX'

# Option 3: Create terraform.tfvars (DO NOT COMMIT)
echo 'api_token = "XXXXXXXXXXXXX"' > terraform.tfvars
```

**Security Note**: Never commit tokens to Git. The token is stored encrypted in SSM Parameter Store.

### Step 5: Review Deployment Plan

```bash
terraform plan
```

Review the resources to be created (~40-50 resources).

### Step 6: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 5-10 minutes.

### Step 7: Push Docker Images to ECR

After infrastructure is deployed, get ECR repository URLs and push images:

```bash
# Get ECR URLs from Terraform outputs
ECR_SERVICE1=$(terraform output -raw ecr_service1_repository_url)
ECR_SERVICE2=$(terraform output -raw ecr_service2_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${ECR_SERVICE1%%/*}

# Tag and push Service 1
docker tag devops-exam-service1:latest $ECR_SERVICE1:latest
docker push $ECR_SERVICE1:latest

# Tag and push Service 2
docker tag devops-exam-service2:latest $ECR_SERVICE2:latest
docker push $ECR_SERVICE2:latest
```

### Step 8: Update ECS Services

Force ECS services to pull the new images:

```bash
aws ecs update-service \
  --cluster devops-exam-cluster-dev \
  --service devops-exam-service1-dev \
  --force-new-deployment \
  --region us-east-1

aws ecs update-service \
  --cluster devops-exam-cluster-dev \
  --service devops-exam-service2-dev \
  --force-new-deployment \
  --region us-east-1
```

### Step 9: Verify Deployment

```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_dns_name)

# Check health endpoint
curl http://$ALB_URL/health

# Expected output: {"status":"healthy"}
```

## Testing the Platform

### Test 1: Valid Request

```bash
ALB_URL=$(terraform output -raw alb_dns_name)

curl -X POST "http://${ALB_URL}/api/message" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test Message",
      "email_sender": "test@example.com",
      "email_timestream": "2026-01-05T12:00:00Z",
      "email_content": "This is a test message"
    },
    "token": "XXXXXXXXXXXXX"  # PUT RIGHT_TOKEN
  }'
```

**Expected Response** (200 OK):
```json
{
  "message": "Message sent to queue",
  "message_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "status": "success"
}
```

### Test 2: Invalid Token

```bash
curl -X POST "http://${ALB_URL}/api/message" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test Message",
      "email_sender": "test@example.com",
      "email_timestream": "2026-01-05T12:00:00Z",
      "email_content": "This should fail"
    },
    "token": "WRONG_TOKEN"
  }'
```

**Expected Response** (401 Unauthorized):
```json
{
  "error": "Invalid token"
}
```

### Test 3: Verify Message in S3

```bash
# Get bucket name
BUCKET=$(terraform output -raw s3_bucket_name)

# List messages from today
aws s3 ls s3://$BUCKET/messages/$(date +%Y/%m/%d)/ --recursive

# Download a specific message
aws s3 cp s3://$BUCKET/messages/2026/01/05/<message_id>.json -
```

### Test 4: Check ECS Services

```bash
# View Service 1 status
aws ecs describe-services \
  --cluster devops-exam-cluster-dev \
  --services devops-exam-service1-dev \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# View Service 2 status
aws ecs describe-services \
  --cluster devops-exam-cluster-dev \
  --services devops-exam-service2-dev \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

### Test 5: Monitor SQS Queue

```bash
# Get queue metrics
QUEUE_URL=$(terraform output -raw sqs_queue_url)

aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names All \
  --query 'Attributes.{Available:ApproximateNumberOfMessages,InFlight:ApproximateNumberOfMessagesNotVisible}'
```

## Monitoring and Logs

### CloudWatch Logs

View logs for both services:

```bash
# Service 1 logs (REST API)
aws logs tail /ecs/devops-exam/service1 --follow

# Service 2 logs (SQS Consumer)
aws logs tail /ecs/devops-exam/service2 --follow

# Filter logs for specific patterns
aws logs tail /ecs/devops-exam/service1 --since 10m --filter-pattern "POST"
```

### ECS Task Health

```bash
# List running tasks
aws ecs list-tasks \
  --cluster devops-exam-cluster-dev \
  --service-name devops-exam-service1-dev

# Describe specific task (replace TASK_ID)
aws ecs describe-tasks \
  --cluster devops-exam-cluster-dev \
  --tasks <TASK_ID>
```

## Network Architecture

### VPC Configuration

- **CIDR Block**: 10.0.0.0/16 (65,536 IPs)
- **Subnets**:
  - Public Subnets: 10.0.0.0/24, 10.0.1.0/24 (ALB, NAT Gateway)
  - Private Subnets: 10.0.10.0/24, 10.0.11.0/24 (ECS tasks)

### Security Groups

| Security Group | Purpose | Inbound Rules |
|----------------|---------|---------------|
| ALB SG | Load balancer | 80 (HTTP) from 0.0.0.0/0 |
| Service 1 SG | REST API containers | 5000 from ALB SG |
| Service 2 SG | Consumer containers | None (outbound only) |

### VPC Endpoints (Cost Optimization)

Instead of routing through NAT Gateway, these services use VPC endpoints:

- **S3 Gateway Endpoint**: Free, for S3 access
- **SQS Interface Endpoint**: $0.01/hour, for SQS access
- **ECR API Interface Endpoint**: $0.01/hour, for pulling images
- **ECR DKR Interface Endpoint**: $0.01/hour, for Docker registry
- **SSM Interface Endpoint**: $0.01/hour, for parameter access

**Cost Savings**: Eliminates NAT Gateway data transfer charges (~$0.045/GB).

## Cost Breakdown (Estimated)

Based on AWS Free Tier and minimal usage:

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| ECS Fargate | $0-5 | 2 tasks × 0.25 vCPU × 0.5 GB RAM |
| ALB | $16.20 | ~$0.0225/hour + minimal LCU charges |
| NAT Gateway | $32.40 | ~$0.045/hour + data transfer |
| VPC Endpoints | $3.60 | 4 endpoints × $0.01/hour |
| S3 | $0-1 | Free Tier: 5GB storage, 20k GET, 2k PUT |
| SQS | $0 | Free Tier: 1M requests/month |
| ECR | $0-1 | Free Tier: 500MB storage |
| CloudWatch Logs | $0-2 | Free Tier: 5GB ingestion |

**Total**: ~$55-60/month (mostly ALB + NAT Gateway)

**Free Tier Optimizations**:
- Use VPC endpoints instead of NAT for supported services
- Consider disabling NAT Gateway and using VPC endpoints only
- Delete ALB when not actively testing

## Cleanup

To avoid ongoing charges, destroy all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm by typing: yes

# Optionally delete ECR images
aws ecr batch-delete-image \
  --repository-name devops-exam-service1-dev \
  --image-ids imageTag=latest

aws ecr batch-delete-image \
  --repository-name devops-exam-service2-dev \
  --image-ids imageTag=latest
```

**Warning**: This permanently deletes:
- All ECS tasks and services
- S3 bucket and all stored messages
- SQS queue and messages
- VPC and networking components
- ECR repositories

## Troubleshooting

### Issue: ECS Tasks Not Starting

```bash
# Check task status
aws ecs describe-tasks \
  --cluster devops-exam-cluster-dev \
  --tasks $(aws ecs list-tasks --cluster devops-exam-cluster-dev --service-name devops-exam-service1-dev --query 'taskArns[0]' --output text)

# Common causes:
# - Image not pushed to ECR
# - IAM role missing permissions
# - Security group blocking traffic
```

### Issue: 502 Bad Gateway from ALB

```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw alb_target_group_arn 2>/dev/null || \
    aws elbv2 describe-target-groups --names devops-exam-tg-dev --query 'TargetGroups[0].TargetGroupArn' --output text)

# Common causes:
# - Tasks not running
# - Health check failing (check /health endpoint)
# - Security group not allowing ALB → ECS traffic
```

### Issue: Messages Not Appearing in S3

```bash
# Check Service 2 logs
aws logs tail /ecs/devops-exam/service2 --since 5m

# Check SQS queue for stuck messages
QUEUE_URL=$(terraform output -raw sqs_queue_url)
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All

# Common causes:
# - Service 2 not running
# - IAM role missing S3 write permissions
# - S3 bucket policy blocking writes
```

### Issue: Terraform Apply Fails

```bash
# Check for AWS quota limits
aws service-quotas list-service-quotas \
  --service-code vpc \
  --query 'Quotas[?QuotaName==`VPCs per Region`]'

# Common causes:
# - AWS quota limits reached
# - Invalid credentials
# - Region-specific resource availability
```

## Outputs Reference

After successful deployment, Terraform provides these outputs:

| Output | Description | Example |
|--------|-------------|---------|
| `alb_url` | Service 1 API endpoint | http://devops-exam-alb-123.us-east-1.elb.amazonaws.com |
| `ecr_service1_repository_url` | Service 1 image registry | 123456789.dkr.ecr.us-east-1.amazonaws.com/service1 |
| `ecr_service2_repository_url` | Service 2 image registry | 123456789.dkr.ecr.us-east-1.amazonaws.com/service2 |
| `s3_bucket_name` | Message storage bucket | devops-exam-messages-dev |
| `sqs_queue_url` | Message queue URL | https://sqs.us-east-1.amazonaws.com/123/queue |
| `vpc_id` | VPC identifier | vpc-0abc123def456 |

View all outputs:
```bash
terraform output
```

## Security Best Practices

This infrastructure implements several security best practices:

1. **No Hardcoded Secrets**: API token stored in SSM Parameter Store (encrypted)
2. **Private Subnets**: Microservices run in private subnets with no direct internet access
3. **Least Privilege IAM**: Task roles have minimal required permissions
4. **Security Groups**: Strict firewall rules, only necessary ports open
5. **VPC Endpoints**: Internal AWS service communication (no internet traversal)
6. **Encrypted Storage**: S3 bucket uses SSE-S3 encryption
7. **Sensitive Variables**: `api_token` marked as sensitive in Terraform

## License

This infrastructure code is part of a DevOps home exam assignment.

## Support

For issues or questions:
1. Check CloudWatch Logs for service errors
2. Review [Troubleshooting](#troubleshooting) section
3. Verify AWS service quotas and limits
4. Ensure Docker images are pushed to ECR
