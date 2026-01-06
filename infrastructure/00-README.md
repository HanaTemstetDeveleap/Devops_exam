# Infrastructure - Terraform IaC for AWS Microservices Platform

Complete Infrastructure as Code implementation using Terraform for a production-grade microservices platform on AWS.

---

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [File Organization](#file-organization)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Testing](#testing)
- [Security Features](#security-features)
- [Network Architecture](#network-architecture)
- [Cost Breakdown](#cost-breakdown)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌──────────────┐      ┌─────────────┐      ┌─────────────┐      ┌──────────────┐
│   Internet   │─────▶│     ALB     │─────▶│  Service 1  │─────▶│  SQS Queue   │
└──────────────┘      └─────────────┘      │  (REST API) │      └──────┬───────┘
                                            └─────────────┘             │
                                                   ↓                    │
                                            ┌─────────────┐             │
                                            │  SSM Store  │             │
                                            │  (Token)    │             │
                                            └─────────────┘             │
                                                                        │
                      ┌──────────────┐      ┌─────────────┐            │
                      │  S3 Bucket   │◀─────│  Service 2  │◀───────────┘
                      │ (Encrypted)  │      │ (Consumer)  │
                      └──────────────┘      └─────────────┘
```

### Components

| Component | Purpose | Security Features |
|-----------|---------|-------------------|
| **VPC** | Isolated network (10.0.0.0/16) | Public & private subnets, security groups |
| **ALB** | Load balancer for Service 1 | Public-facing, HTTP→Service 1 only |
| **Service 1** | REST API with token validation | Private subnet, SSM token, payload validation |
| **Service 2** | SQS consumer, S3 uploader | Private subnet, IAM least privilege |
| **SQS** | Message queue with DLQ | Encrypted, 7-day retention |
| **S3** | Message storage | SSE-S3 encryption, versioning |
| **SSM** | Secure token storage | Encrypted at rest, IAM-based access |
| **ECR** | Docker image repositories | Private, lifecycle policies |
| **ECS Fargate** | Container orchestration | No EC2 management, auto-scaling ready |
| **VPC Endpoints** | Private AWS API access | No NAT Gateway needed for some services |

---

## File Organization

Files are numbered in **logical dependency order** for easy reading:

| File | Description | Key Resources |
|------|-------------|---------------|
| [01-provider.tf](01-provider.tf) | AWS provider, Terraform version | Provider config, backend |
| [02-variables.tf](02-variables.tf) | Input variables with defaults | Region, environment, tokens |
| [03-vpc.tf](03-vpc.tf) | VPC, subnets, routing, security | VPC, subnets, NAT, VPC endpoints, security groups |
| [04-iam.tf](04-iam.tf) | IAM roles and policies | ECS task roles, execution roles |
| [05-ecr.tf](05-ecr.tf) | Docker registries | Service 1, Service 2, Prometheus repos |
| [06-s3.tf](06-s3.tf) | S3 bucket for messages | Encryption, versioning, lifecycle |
| [07-sqs.tf](07-sqs.tf) | SQS queue and DLQ | Main queue, dead letter queue |
| [08-ssm.tf](08-ssm.tf) | Secure API token storage | Encrypted parameter |
| [09-alb.tf](09-alb.tf) | Application Load Balancer | ALB, listener, target group |
| [10-ecs.tf](10-ecs.tf) | ECS cluster, tasks, services | Cluster, task definitions, services |
| [11-outputs.tf](11-outputs.tf) | Terraform outputs | URLs, ARNs, names for testing |
| [12-monitoring.tf](12-monitoring.tf) | Prometheus + Grafana | Monitoring infrastructure |

---

## Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| **Terraform** | v1.0+ | [Install Guide](https://developer.hashicorp.com/terraform/downloads) |
| **AWS CLI** | v2.0+ | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| **Docker** | v20.0+ | [Install Guide](https://docs.docker.com/get-docker/) |

### AWS Account Setup

1. **AWS Account**: Free Tier eligible recommended
2. **AWS Credentials**: Configure with required permissions
   ```bash
   aws configure
   # Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)
   ```

3. **Verify credentials**:
   ```bash
   aws sts get-caller-identity
   # Should display your AWS account ID and user ARN
   ```

### Required IAM Permissions

The AWS user/role needs permissions for:
- VPC, EC2 (subnets, security groups, VPC endpoints)
- ECS, ECR (clusters, services, repositories)
- S3, SQS, SSM (buckets, queues, parameters)
- IAM (roles, policies)
- CloudWatch Logs, CloudWatch (logging, metrics)
- Elastic Load Balancing (ALB, target groups)

**Recommended**: Use `AdministratorAccess` for exam, or create custom policy with scoped permissions for production.

---

## Deployment Guide

### Important: First Deployment Note

**ECS services start with `desired_count=0`** because Docker images don't exist in ECR yet.

After deploying infrastructure and pushing images (via CI or manually), you'll need to scale services to `desired_count=1`.

---

### Step 1: Initialize Terraform

```bash
cd infrastructure

# Initialize Terraform (downloads providers)
terraform init
```

**Expected output**: "Terraform has been successfully initialized!"

---

### Step 2: Set Required Variables

The **`api_token`** variable is **required** (no default for security):

```bash
# Option 1: Environment variable (recommended)
export TF_VAR_api_token='your-secure-token-here'

# Option 2: Command line
terraform apply -var='api_token=your-secure-token-here'

# Option 3: terraform.tfvars file (DO NOT COMMIT)
echo 'api_token = "your-secure-token-here"' > terraform.tfvars
```

**Security Note**: Never commit secrets to Git. Add `terraform.tfvars` to `.gitignore`.

---

### Step 3: Review Infrastructure Plan

```bash
terraform plan
```

**Review**:
- Resources to create (~45-55 resources)
- Estimated costs
- No unexpected deletions/modifications

---

### Step 4: Deploy Infrastructure

```bash
terraform apply

# Review the plan, then type: yes
```

**Deployment time**: ~5-10 minutes

**What's created**:
- VPC with 2 public + 2 private subnets
- Internet Gateway (no NAT Gateway - using VPC endpoints instead)
- VPC endpoints for S3, SQS, ECR (API & DKR), SSM, CloudWatch Logs
- Security groups for ALB, services (Service 1, Service 2), monitoring, and VPC endpoints
- ECS cluster with Container Insights enabled
- AWS Cloud Map namespace (`local`) with service discovery for Service 1, Service 2, and Prometheus
- ECR repositories for Service 1, Service 2, and Prometheus (with lifecycle policies)
- S3 bucket with versioning, encryption, and lifecycle configuration
- SQS queue with DLQ and redrive policy
- SSM parameter with encrypted API token
- ALB with HTTP listener and target group for Service 1
- ECS task definitions and services for Service 1, Service 2, Prometheus, and Grafana
- CloudWatch log groups for all services (7-day retention)
- IAM roles and policies for ECS task execution and service-specific permissions

---

### Step 5: Build and Push Docker Images

**Option A - Automated (Recommended)**:
Push code to GitHub → CI workflows automatically build and push to ECR

**Option B - Manual**:

```bash
# Get ECR repository URLs from Terraform outputs
ECR_SERVICE1=$(terraform output -raw ecr_service1_repository_url)
ECR_SERVICE2=$(terraform output -raw ecr_service2_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${ECR_SERVICE1%%/*}

# Build and push Service 1
cd ../microservices/service1-api
docker build -t $ECR_SERVICE1:latest .
docker push $ECR_SERVICE1:latest

# Build and push Service 2
cd ../service2-consumer
docker build -t $ECR_SERVICE2:latest .
docker push $ECR_SERVICE2:latest

# Return to infrastructure directory
cd ../../infrastructure
```

---

### Step 6: Update ECS Services to Deploy Containers

After images are in ECR, deploy them to ECS:

```bash
# Update Service 1
aws ecs update-service \
  --cluster devops-exam-cluster-dev \
  --service devops-exam-service1-dev \
  --desired-count 1 \
  --force-new-deployment

# Update Service 2
aws ecs update-service \
  --cluster devops-exam-cluster-dev \
  --service devops-exam-service2-dev \
  --desired-count 1 \
  --force-new-deployment

# Wait for services to stabilize (takes ~2-3 minutes)
aws ecs wait services-stable \
  --cluster devops-exam-cluster-dev \
  --services devops-exam-service1-dev devops-exam-service2-dev
```

**Alternative**: Update `desired_count` in `10-ecs.tf` from `0` to `1` and run `terraform apply` again.

---

### Step 7: Verify Deployment

```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_dns_name)

# Get API token from SSM
API_TOKEN=$(aws ssm get-parameter \
  --name /devops-exam/dev/api-token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Test health endpoint
curl http://$ALB_URL/health

# Expected: {"status":"healthy"}

# Test API with valid token
curl -X POST "http://${ALB_URL}/api/message" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test Message",
      "email_sender": "test@example.com",
      "email_timestream": "1693561101",
      "email_content": "Hello from deployment test"
    },
    "token": "'$API_TOKEN'"
  }'

# Expected: {"message": "Message sent to queue", "message_id": "...", "status": "success"}
```

---

## Testing

### Test 1: Valid Request (Success Flow)

```bash
ALB_URL=$(terraform output -raw alb_dns_name)
API_TOKEN=$(aws ssm get-parameter --name /devops-exam/dev/api-token --with-decryption --query 'Parameter.Value' --output text)

curl -X POST "http://${ALB_URL}/api/message" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test Email",
      "email_sender": "user@example.com",
      "email_timestream": "1693561101",
      "email_content": "This is a valid test message"
    },
    "token": "'$API_TOKEN'"
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

---

### Test 2: Invalid Token (Security Test)

```bash
curl -X POST "http://${ALB_URL}/api/message" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test",
      "email_sender": "test@example.com",
      "email_timestream": "1693561101",
      "email_content": "Should fail"
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

---

### Test 3: Verify Message in S3

```bash
# Get bucket name
BUCKET=$(terraform output -raw s3_bucket_name)

# List messages from today
aws s3 ls s3://$BUCKET/messages/$(date +%Y/%m/%d)/ --recursive

# Download a specific message
aws s3 cp s3://$BUCKET/messages/$(date +%Y/%m/%d)/<message_id>.json - | jq .
```

**Expected**: JSON file with email data

---

### Test 4: Monitor ECS Services

```bash
# View Service 1 status
aws ecs describe-services \
  --cluster devops-exam-cluster-dev \
  --services devops-exam-service1-dev \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Events:events[:3]}'

# View Service 2 status
aws ecs describe-services \
  --cluster devops-exam-cluster-dev \
  --services devops-exam-service2-dev \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Events:events[:3]}'
```

**Expected**: `Running = Desired = 1`, Status = ACTIVE

---

### Test 5: Check CloudWatch Logs

```bash
# Service 1 logs (REST API)
aws logs tail /ecs/devops-exam/service1 --follow

# Service 2 logs (SQS Consumer)
aws logs tail /ecs/devops-exam/service2 --follow

# Filter for POST requests
aws logs tail /ecs/devops-exam/service1 --since 10m --filter-pattern "POST"
```

---

## Security Features

This infrastructure implements **defense-in-depth** security:

### 1. Network Security

✅ **Private Subnets**: Microservices run in private subnets (10.0.10.0/24, 10.0.11.0/24) with no direct internet access

✅ **Security Groups**: Strict firewall rules
- ALB SG: Port 80 from 0.0.0.0/0
- Service 1 SG: Port 8080 from ALB SG only
- Service 2 SG: No inbound, outbound to AWS services only

✅ **VPC Endpoints**: Private connections to AWS services (S3, SQS, ECR, SSM)
- **No NAT Gateway needed** - all AWS traffic via private VPC endpoints
- No traffic traverses public internet
- Significant cost savings ($32/month) vs NAT Gateway approach
- Improved security posture (no internet gateway route for private subnets)

### 2. Secrets Management

✅ **No Hardcoded Credentials**: API token stored in AWS SSM Parameter Store

✅ **Encryption at Rest**: SSM parameter encrypted with AWS-managed key

✅ **IAM-Based Access**: Service 1 retrieves token using task IAM role, not access keys

✅ **Terraform Sensitive Variables**: `api_token` marked as sensitive (never logged)

### 3. IAM Least Privilege

✅ **Task-Specific Roles**:
- **Service 1 Task Role**:
  - `ssm:GetParameter` (read-only, specific parameter)
  - `sqs:SendMessage` (specific queue only)
- **Service 2 Task Role**:
  - `sqs:ReceiveMessage`, `sqs:DeleteMessage` (specific queue)
  - `s3:PutObject` (specific bucket only)

✅ **No Wildcard Permissions**: All policies scoped to specific resource ARNs

✅ **Separate Execution Role**: ECS task execution role for pulling images (separate from task role)

### 4. Data Protection

✅ **S3 Encryption**: Server-side encryption (SSE-S3) enabled by default

✅ **S3 Versioning**: Enabled to protect against accidental deletions

✅ **SQS Encryption**: Messages encrypted in transit and at rest

✅ **Payload Validation**: Service 1 validates all 4 required fields before processing

### 5. Monitoring & Auditing

✅ **Container Insights**: Enabled for ECS cluster (see `10-ecs.tf` line 6)

✅ **CloudWatch Logs**: All services log to CloudWatch with 7-day retention

✅ **VPC Flow Logs** (Optional): Can be enabled for network traffic analysis

---

## Network Architecture

### VPC Configuration

- **CIDR Block**: 10.0.0.0/16 (65,536 IP addresses)
- **Availability Zones**: us-east-1a, us-east-1b (high availability)

### Subnets

| Type | CIDR | AZ | Purpose |
|------|------|-----|---------|
| Public 1 | 10.0.0.0/24 | us-east-1a | ALB |
| Public 2 | 10.0.1.0/24 | us-east-1b | ALB (HA) |
| Private 1 | 10.0.10.0/24 | us-east-1a | ECS tasks (Service 1, Service 2) |
| Private 2 | 10.0.11.0/24 | us-east-1b | ECS tasks (HA) |

### Routing

**Public Subnets**:
- Route to Internet Gateway (0.0.0.0/0 → igw)
- Used for ALB only

**Private Subnets**:
- **No NAT Gateway** - all AWS service access via VPC endpoints
- No direct internet access (maximum security)
- Cost optimization: Saves ~$32/month by using VPC endpoints instead of NAT

### VPC Endpoints

| Endpoint | Type | Purpose | Cost |
|----------|------|---------|------|
| **S3** | Gateway | S3 access from private subnets | Free |
| **SQS** | Interface | SQS access without NAT | $7/month |
| **ECR API** | Interface | Pull image manifests | $7/month |
| **ECR DKR** | Interface | Pull Docker layers | $7/month |
| **SSM** | Interface | Retrieve SSM parameters | $7/month |

**Cost & Security Benefits**:
- ✅ **No NAT Gateway**: Saves $32/month + data transfer costs (~$0.045/GB)
- ✅ **Better Security**: Private subnets have no route to internet (even via NAT)
- ✅ **Lower Latency**: Direct AWS PrivateLink connections to services

---

## Cost Breakdown

### Monthly Cost Estimate (Free Tier)

| Service | Specs | Monthly Cost | Free Tier |
|---------|-------|--------------|-----------|
| **ECS Fargate** | 2 tasks × 0.25 vCPU × 0.5 GB RAM | $0-5 | First 20 GB-hrs/month free |
| **ALB** | Standard, minimal traffic | $16 | None |
| **VPC Endpoints** | 4 interface endpoints | $28 | **No NAT Gateway!** |
| **S3** | <5 GB storage, <20k requests | $0 | 5 GB, 20k GET, 2k PUT free |
| **SQS** | <1M requests/month | $0 | 1M requests free |
| **ECR** | <500 MB storage | $0 | 500 MB free |
| **CloudWatch Logs** | <5 GB ingestion | $0 | 5 GB free |

**Total Estimated Cost**: **$44-49/month**

**Breakdown**:
- **Mandatory**: ALB ($16) + VPC Endpoints ($28) = $44/month
- **NAT Gateway**: $0 (not used - VPC endpoints instead!)
- **Negligible**: ECS, S3, SQS, ECR, CloudWatch (covered by free tier)

**Architecture Highlights**:
- ✅ **No NAT Gateway**: Saves $32/month by using VPC endpoints for all AWS service access
- ✅ **Better Security**: No internet gateway route for private subnets
- ✅ **Lower Latency**: Direct private connections to AWS services

### Cost Optimization Tips

1. ✅ **Already Optimized**: No NAT Gateway (saves $32/month vs typical architectures)
2. **Delete ALB when not testing**: Destroy/recreate for demos (saves $16/month when idle)
3. **Reduce CloudWatch retention**: Change from 7 days to 1 day
4. **Disable Container Insights**: Set `containerInsights = "disabled"` in `10-ecs.tf`
5. **Stop ECS services**: Scale `desired_count` to 0 when not actively testing

---

## Troubleshooting

### Issue: ECS Tasks Not Starting

**Symptoms**: Service shows `RUNNING` tasks = 0

**Diagnosis**:
```bash
# List tasks (may be empty)
aws ecs list-tasks --cluster devops-exam-cluster-dev --service-name devops-exam-service1-dev

# If task exists, describe it
aws ecs describe-tasks --cluster devops-exam-cluster-dev --tasks <TASK_ARN>

# Check stopped tasks (for error messages)
aws ecs list-tasks --cluster devops-exam-cluster-dev --desired-status STOPPED
aws ecs describe-tasks --cluster devops-exam-cluster-dev --tasks <STOPPED_TASK_ARN>
```

**Common Causes**:
1. **Image not in ECR**: Push Docker images first
2. **IAM role missing permissions**: Check `04-iam.tf`
3. **Security group blocking traffic**: Verify security group rules
4. **Task definition invalid**: Check CPU/memory limits (must be Fargate-compatible)

---

### Issue: 502 Bad Gateway from ALB

**Symptoms**: `curl` returns HTTP 502 instead of 200

**Diagnosis**:
```bash
# Check target group health
TG_ARN=$(terraform output -raw alb_target_group_arn)
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# Status should be "healthy", not "unhealthy" or "draining"
```

**Common Causes**:
1. **Service 1 not running**: Check ECS service status
2. **Health check failing**: Service 1 must respond to `/health` endpoint
3. **Security group blocking ALB→Service 1**: Port 8080 must be open
4. **Service 1 not listening on port 8080**: Check app logs

---

### Issue: Messages Not Appearing in S3

**Symptoms**: API returns success but S3 bucket is empty

**Diagnosis**:
```bash
# Check Service 2 logs for errors
aws logs tail /ecs/devops-exam/service2 --since 5m

# Check SQS queue for stuck messages
QUEUE_URL=$(terraform output -raw sqs_queue_url)
aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible

# Check DLQ for failed messages
DLQ_URL=$(terraform output -raw sqs_dlq_url)
aws sqs receive-message --queue-url "$DLQ_URL" --max-number-of-messages 10
```

**Common Causes**:
1. **Service 2 not running**: Scale service to `desired_count=1`
2. **IAM role missing S3 permissions**: Check `04-iam.tf` Service 2 task role
3. **S3 bucket policy blocking writes**: Review `06-s3.tf`
4. **Service 2 polling interval too long**: Default is 10 seconds

---

### Issue: Terraform Apply Fails

**Symptoms**: `terraform apply` errors during resource creation

**Common Errors**:

**Error**: `InvalidParameter: VPC CIDR overlaps`
**Solution**: Change `vpc_cidr` variable or destroy existing VPC

**Error**: `LimitExceededException: Cannot exceed quota for PoliciesPerRole`
**Solution**: Consolidate IAM policies or request quota increase

**Error**: `AccessDenied: User is not authorized`
**Solution**: Add required IAM permissions to AWS user

**Error**: `AlreadyExists: LoadBalancer already exists`
**Solution**: Check for conflicting ALB names, run `terraform destroy` first

---

### Issue: Can't Access SSM Parameter

**Symptoms**: Service 1 logs show "Access Denied" for SSM

**Solution**:
```bash
# Verify parameter exists
aws ssm get-parameter --name /devops-exam/dev/api-token

# Check IAM role policy
aws iam get-policy-version \
  --policy-arn $(terraform output -raw service1_task_role_policy_arn) \
  --version-id v1

# Should include ssm:GetParameter action
```

---

## Terraform Outputs Reference

After successful deployment, use these outputs:

| Output | Description | Example |
|--------|-------------|---------|
| `alb_dns_name` | Service 1 API URL | `devops-exam-alb-123.us-east-1.elb.amazonaws.com` |
| `ecr_service1_repository_url` | Service 1 ECR | `123456.dkr.ecr.us-east-1.amazonaws.com/service1` |
| `ecr_service2_repository_url` | Service 2 ECR | `123456.dkr.ecr.us-east-1.amazonaws.com/service2` |
| `s3_bucket_name` | Message storage | `devops-exam-messages-dev-abc123` |
| `sqs_queue_url` | Main queue URL | `https://sqs.us-east-1.amazonaws.com/123/queue` |
| `vpc_id` | VPC ID | `vpc-0abc123def456` |

**View all outputs**:
```bash
terraform output
```

---

## Cleanup

To destroy all infrastructure and avoid ongoing charges:

```bash
# Empty S3 bucket first (Terraform can't delete non-empty buckets)
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 rm s3://$BUCKET --recursive

# Destroy all resources
terraform destroy

# Confirm by typing: yes
```

**What gets deleted**:
- All ECS tasks and services (immediate shutdown)
- S3 bucket (after manual emptying)
- SQS queue and DLQ (messages lost)
- VPC, subnets, VPC endpoints
- ECR repositories (images remain unless explicitly deleted)
- ALB and target groups
- IAM roles and policies
- SSM parameters
- CloudWatch log groups

**Warning**: This is **permanent** and cannot be undone.

---

## Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [AWS Free Tier Details](https://aws.amazon.com/free/)
- [VPC Endpoints Guide](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)

---

**Related Documentation**:
- [Main README](../README.md) - Project overview
- [Microservices README](../microservices/README.md) - Service details and testing
- [Workflows README](../.github/workflows/README.md) - CI/CD pipeline
- [Monitoring README](monitoring/README.md) - Prometheus + Grafana setup
