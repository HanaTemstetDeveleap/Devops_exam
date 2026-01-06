# DevOps Home Exam - Microservices Platform on AWS

Two microservices architecture on AWS with complete CI/CD pipeline on GitHub Actions, comprehensive testing (unit tests & E2E), and monitoring (Grafana + Prometheus) with custom dashboards (JSON).

---

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Security Implementation](#security-implementation)
- [Assignment Requirements Checklist](#assignment-requirements-checklist)
- [Quick Start Guide](#quick-start-guide)
- [Testing](#testing)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring](#monitoring)
- [Documentation](#documentation)

---

## Architecture Overview

```
Internet → ALB → Service 1 (REST API) → SQS Queue → Service 2 (Consumer) → S3 Bucket
                      ↓
                  SSM Token Validation
```

### Components
- **Service 1 (REST API)**: Flask application that validates tokens via SSM and publishes messages to SQS
- **Service 2 (Consumer)**: Background worker that polls SQS and uploads messages to S3 with date-based hierarchy
- **Infrastructure**: VPC, ECS Fargate, ALB, SQS, S3, ECR - all defined in Terraform IaC
- **CI/CD**: GitHub Actions workflows for automated build, test, and deployment
- **Monitoring**: Prometheus + Grafana for metrics visualization

---

## Security Implementation

**This project implements security best practices critical for high-security environments:**

### 1. Secrets Management
- **No hardcoded credentials** - API token stored in AWS SSM Parameter Store with encryption at rest
- **Secure token retrieval** - Service 1 fetches token from SSM with IAM-based authentication
- **Token caching** - In-memory caching to minimize SSM API calls (reduces exposure)
- **Sensitive variables** - Terraform marks `api_token` as sensitive (never logged)

### 2. Network Security
- **Private subnets** - All microservices run in private subnets with no direct internet access
- **Security groups** - Strict ingress/egress rules (ALB → Service 1 on port 8080 only)
- **VPC endpoints** - AWS service communication via private endpoints (S3, SQS, ECR, SSM)
- **No NAT traversal** - AWS API calls don't traverse public internet

### 3. IAM Least Privilege
- **Task-specific roles** - Each ECS task has minimal required permissions
  - Service 1: SSM read-only + SQS send message
  - Service 2: SQS receive/delete + S3 write to specific bucket
- **No wildcard permissions** - All policies scoped to specific resources

### 4. Data Protection
- **Encryption at rest** - S3 bucket uses SSE-S3 encryption
- **Encryption in transit** - TLS for all AWS service communication via VPC endpoints
- **Message validation** - Strict payload validation before processing (prevents injection attacks)

### 5. CI/CD Security
- **Managed credentials** - GitHub Actions uses AWS IAM user with scoped permissions
- **No secrets in code** - All sensitive values stored in GitHub Secrets
- **Image scanning** - ECR images can be scanned for vulnerabilities (optional)


---

## Assignment Requirements Checklist

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **1. CI/CD Tool** | GitHub Actions (5 workflows) | ✅ |
| **2. IaC** | Terraform (12 modular files) | ✅ |
| **3. SQS + S3** | Created via Terraform with DLQ and encryption | ✅ |
| **4. Microservice 1** | Flask REST API with token validation (SSM) | ✅ |
| **4a. Request Handling** | Listens on port 8080 behind ALB | ✅ |
| **4b. Token Validation** | Token stored in SSM Parameter Store | ✅ |
| **4c. Payload Validation** | Validates 4 required fields (email_subject, email_sender, email_timestream, email_content) | ✅ |
| **4d. SQS Publishing** | Publishes validated messages to SQS | ✅ |
| **5. Microservice 2** | Python consumer with configurable polling interval | ✅ |
| **5a. SQS Polling** | Polls every X seconds (configurable via env var) | ✅ |
| **5b. S3 Upload** | Uploads to date-based path: `messages/YYYY/MM/DD/<id>.json` | ✅ |
| **6. CI Jobs** | Separate workflows for Service 1 & 2 (build, test, push to ECR) | ✅ |
| **7. CD Jobs** | Automated deployment to ECS Fargate after CI success | ✅ |
| **Bonus 1: Tests** | Unit tests (25 total) + E2E tests | ✅ |
| **Bonus 2: Monitoring** | Prometheus + Grafana with custom dashboards | ✅ |

---

## Quick Start Guide

### Prerequisites
- AWS CLI v2+ configured with credentials
- Terraform v1.0+
- Docker v20.0+
- Git

### 1. Deploy Infrastructure

```bash
cd infrastructure

# Initialize Terraform
terraform init

# Set API token (REQUIRED - no default for security)
export TF_VAR_api_token='your-secure-token-here'

# Deploy (creates VPC, ECS, ALB, S3, SQS, ECR, SSM)
terraform apply
```

**First deployment note**: ECS services start with `desired_count=0` because Docker images don't exist yet. After CI builds and pushes images, update to `desired_count=1`.

### 2. Build and Push Images (CI Alternative)

**Option A - Automated (Recommended)**:
Push code to GitHub → CI workflows automatically build and push to ECR

**Option B - Manual**:
```bash
# Get ECR URLs from Terraform
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
```

### 3. Deploy Services to ECS

```bash
# Update Service 1
aws ecs update-service \
  --cluster devops-exam-cluster-dev \
  --service devops-exam-service1-dev \
  --force-new-deployment

# Update Service 2
aws ecs update-service \
  --cluster devops-exam-cluster-dev \
  --service devops-exam-service2-dev \
  --force-new-deployment
```

### 4. Verify Deployment

```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_dns_name)

# Get API token from SSM
API_TOKEN=$(aws ssm get-parameter \
  --name /devops-exam/dev/api-token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Test API
curl -X POST "http://${ALB_URL}/api/message" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test Message",
      "email_sender": "test@example.com",
      "email_timestream": "1693561101",
      "email_content": "Hello World"
    },
    "token": "'$API_TOKEN'"
  }'
```

**Expected response**: `{"message": "Message sent to queue", "message_id": "...", "status": "success"}`

---

## Testing

### Unit Tests (Automated - Runs in CI)

Both services have comprehensive unit tests with **mocked AWS services** (no real AWS costs):

```bash
# Service 1 - 15 tests (74% coverage)
cd microservices/service1-api
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v --cov=app

# Service 2 - 10 tests (75% coverage)
cd ../service2-consumer
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v --cov=app
```

**What's tested**:
- Token validation and caching (Service 1)
- Payload validation (missing fields, invalid structure)
- SQS message sending and receiving
- S3 upload with date-based hierarchy
- Error handling and edge cases

### E2E Tests (Manual - Real AWS)

End-to-end test verifies complete message flow: API → SQS → Consumer → S3

```bash
cd microservices

# Set environment variables
export ALB_DNS=$(terraform output -raw alb_dns_name)
export API_TOKEN=$(aws ssm get-parameter --name /devops-exam/dev/api-token --with-decryption --query 'Parameter.Value' --output text)
export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Run E2E test
chmod +x e2e_test/run_e2e.sh
./e2e_test/run_e2e.sh
```

**Test flow**:
1. Sends HTTP POST to Service 1
2. Verifies message in SQS
3. Waits for Service 2 to process (up to 60s)
4. Validates message in S3 with correct content
5. Cleans up test data

**Cost warning**: Uses real AWS resources (~$0.01 per run). Run before releases, not on every commit.

---

## CI/CD Pipeline

### GitHub Actions Workflows

**CI Workflows** (`.github/workflows/ci-service*.yml`):
1. Triggered on push to `microservices/service*/**` paths
2. Run unit tests with pytest
3. Build Docker image
4. Push to ECR with commit SHA tag
5. Trigger CD workflow

**CD Workflows** (`.github/workflows/cd-service*.yml`):
1. Validate image in ECR
2. Update ECS task definition
3. Deploy to ECS Fargate
4. Wait for service stability
5. Verify deployment

### Setup Requirements

**GitHub Secrets** (Settings → Secrets → Actions):
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Note**: For simplicity, this project uses an IAM user with managed policies. In production, use GitHub OIDC with a dedicated IAM role and scoped permissions (least privilege).

See [.github/workflows/README.md](.github/workflows/README.md) for detailed documentation.

---

## Monitoring

### Prometheus + Grafana (Bonus #2)

**Metrics Collected**:
- **Service 1**: Request rate, latency (p95), SQS messages sent, token validation failures
- **Service 2**: SQS polling activity, messages processed, S3 uploads (success/failures)

**Access Grafana**:

```bash
# Get Grafana public IP
TASK_ARN=$(aws ecs list-tasks --cluster devops-exam-cluster --service-name devops-exam-grafana --query 'taskArns[0]' --output text)
ENI=$(aws ecs describe-tasks --cluster devops-exam-cluster --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
GRAFANA_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "Grafana: http://$GRAFANA_IP:3000"
```

**Default credentials**: `admin` / `admin`

**Import dashboard**: Upload `infrastructure/monitoring/grafana/dashboards/microservices-metrics.json`

See [infrastructure/monitoring/README.md](infrastructure/monitoring/README.md) for full documentation.

---

## Documentation

Detailed documentation is available in subdirectories:

| Document | Description |
|----------|-------------|
| [infrastructure/00-README.md](infrastructure/00-README.md) | Terraform IaC setup, deployment guide, troubleshooting |
| [microservices/README.md](microservices/README.md) | Service architecture, local development, testing details |
| [.github/workflows/README.md](.github/workflows/README.md) | CI/CD pipeline configuration and best practices |
| [infrastructure/monitoring/README.md](infrastructure/monitoring/README.md) | Monitoring setup with Prometheus + Grafana |

---

## Cleanup

To destroy all resources and avoid ongoing AWS charges:

```bash
cd infrastructure
terraform destroy
```


---

## Project Structure

```
.
├── infrastructure/          # Terraform IaC (VPC, ECS, ALB, S3, SQS)
│   ├── 01-provider.tf
│   ├── 02-variables.tf
│   ├── 03-vpc.tf           # VPC, subnets, security groups
│   ├── 04-iam.tf           # IAM roles with least privilege
│   ├── 05-ecr.tf           # Docker registries
│   ├── 06-s3.tf            # Encrypted S3 bucket
│   ├── 07-sqs.tf           # SQS with DLQ
│   ├── 08-ssm.tf           # Secure token storage
│   ├── 09-alb.tf           # Application Load Balancer
│   ├── 10-ecs.tf           # ECS Fargate services
│   ├── 11-outputs.tf
│   └── monitoring/         # Prometheus + Grafana
├── microservices/
│   ├── service1-api/       # Flask REST API
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   └── test_app.py     # 15 unit tests
│   ├── service2-consumer/  # SQS to S3 worker
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   └── test_app.py     # 10 unit tests
│   └── e2e_test/           # End-to-end test suite
└── .github/workflows/      # CI/CD pipelines
    ├── ci-service1.yml
    ├── ci-service2.yml
    ├── cd-service1.yml
    └── cd-service2.yml
```

