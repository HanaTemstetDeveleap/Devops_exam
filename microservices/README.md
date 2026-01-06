# Microservices - Python Services for Message Processing

Two containerized Python microservices implementing asynchronous message processing pipeline with security best practices.

---

## Table of Contents
- [Services Overview](#services-overview)
- [Security Features](#security-features)
- [Testing](#testing)
- [Local Development](#local-development)
- [CI/CD Integration](#cicd-integration)

---

## Services Overview

### Service 1: REST API (`service1-api/`)

**Technology Stack**:
- **Framework**: Flask 2.x
- **Metrics**: Prometheus client for custom metrics
- **AWS SDK**: boto3 for SQS and SSM

**Purpose**: HTTP API endpoint that validates tokens and publishes messages to SQS

**Port**: 8080

**API Endpoints**:
| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/health` | GET | Health check (ALB target health) | None |
| `/api/message` | POST | Submit message for processing | Token required |
| `/metrics` | GET | Prometheus metrics (internal only) | None |

**Request Format**:
```json
{
  "data": {
    "email_subject": "string (required)",
    "email_sender": "string (required)",
    "email_timestream": "string (required)",
    "email_content": "string (required)"
  },
  "token": "string (validated against SSM)"
}
```

**Security Features**:
- Token validation against AWS SSM Parameter Store
- Token caching (in-memory, 5-minute TTL) to reduce SSM API calls
- Payload validation (all 4 fields required)
- IAM role-based authentication (no hardcoded credentials)

---

### Service 2: SQS Consumer (`service2-consumer/`)

**Technology Stack**:
- **Framework**: Python 3.11 background worker
- **Metrics**: Prometheus client for custom metrics
- **AWS SDK**: boto3 for SQS and S3

**Purpose**: Background worker that polls SQS and uploads messages to S3

**Polling Interval**: Configurable via `POLL_INTERVAL` env var (default: 10 seconds)

**Storage Pattern**: `messages/YYYY/MM/DD/<message-id>.json`
- Year/Month/Day hierarchy for easy browsing
- Message ID from SQS as filename
- JSON format with metadata

**Security Features**:
- IAM role-based access (no hardcoded credentials)
- Least privilege permissions (SQS receive/delete, S3 write only)
- S3 encryption at rest (SSE-S3)
- Message validation before upload

---

## Security Features

Both services implement security best practices:

### Service 1 Security
- ✅ **No Hardcoded Tokens**: Token retrieved from AWS SSM Parameter Store at runtime
- ✅ **Token Caching**: 5-minute TTL cache to reduce SSM API calls (performance + cost)
- ✅ **Payload Validation**: All 4 email fields required before processing
- ✅ **IAM Role Authentication**: Uses ECS task role, no access keys in code
- ✅ **Private Subnet Deployment**: No direct internet access
- ✅ **Input Sanitization**: Prevents injection attacks

### Service 2 Security
- ✅ **IAM Least Privilege**: Read/delete from SQS, write to S3 only
- ✅ **S3 Encryption**: Uploads to SSE-S3 encrypted bucket
- ✅ **Message Validation**: Validates message structure before S3 upload
- ✅ **Private Subnet Deployment**: All AWS API calls via VPC endpoints
- ✅ **Error Handling**: Failed messages logged, not lost

---

## Testing

### Unit Tests (Automated - Runs in CI)

Both services include comprehensive unit tests with mocked AWS services:

**Service 1 - 15 tests:**
```bash
cd service1-api
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v --cov=app
```

**Service 2 - 10 tests:**
```bash
cd service2-consumer
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v --cov=app
```

**Coverage**: Unit tests provide 74%+ code coverage and run in seconds using mocked AWS services (moto library).

### End-to-End Tests (Manual - Real AWS)

The E2E test (`e2e_test.py`) verifies the complete message flow using real AWS infrastructure.

**Prerequisites:**
1. AWS infrastructure deployed (`terraform apply` in `infrastructure/`)
2. Both ECS services running
3. AWS credentials configured
4. Environment variables set

**Setup:**
```bash
# Get ALB DNS from Terraform output
cd ../infrastructure
export ALB_DNS=$(terraform output -raw alb_dns_name)

# Get API token from SSM Parameter Store
export API_TOKEN=$(aws ssm get-parameter \
  --name /devops-exam/dev/api-token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Get S3 bucket name from Terraform output
export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Optional: Set region (defaults to us-east-1)
export AWS_REGION=us-east-1
```

**Run E2E Test:**
```bash
cd ../microservices
chmod +x e2e_test/run_e2e.sh
./e2e_test/run_e2e.sh
```

Note: The E2E test suite uses real AWS resources and may incur costs. These tests should NOT be triggered on every CI run (for example, not on every Docker image build). Run them manually or in a dedicated pre-deploy pipeline before production releases.

To remove the virtual environment when you're done:
```bash
# Warning: this deletes the .venv directory
rm -rf .venv
```

The helper script will prompt for confirmation before running tests against real AWS resources.

**What it tests:**
1. Sends real HTTP request to ALB → Service 1
2. Verifies message reaches SQS
3. Waits for Service 2 to process (up to 60s)
4. Verifies message stored in S3 with correct content
5. Cleans up test data

**Expected output:**
```
[1/5] Sending message to Service 1 API...
      Response status: 200
      Message ID: abc123...

[2/5] Message sent successfully to SQS

[3/5] Waiting for Service 2 to process message...
      Waiting... (5s / 60s)
      Waiting... (10s / 60s)

[4/5] Message found in S3!
      S3 Key: messages/2024/01/15/abc123....json
      Processing time: ~15 seconds

[5/5] Verifying S3 file content...
      Content verified successfully!

[Cleanup] Deleting test file from S3...
         Test file deleted

============================================================
E2E TEST PASSED
============================================================
Message traveled successfully:
  API (Service 1) → SQS → Service 2 → S3
Total processing time: ~15 seconds
============================================================
```

**Cost Warning**: E2E tests use real AWS resources and incur small costs (SQS requests, S3 storage, ALB requests). Run before major releases, not on every commit.

## Testing Strategy

| Test Type | When | Cost | Speed | AWS Resources |
|-----------|------|------|-------|---------------|
| **Unit Tests** | Every commit (CI) | Free | Seconds | Mocked |
| **E2E Tests** | Before releases (Manual) | ~$0.01 per run | ~60s | Real |

**Best Practice**: Run unit tests on every commit, run E2E tests before deploying to production.

## Local Development

### Run Service 1 Locally:
```bash
cd service1-api

# Set environment variables
export AWS_REGION=us-east-1
export SSM_PARAMETER_NAME=/devops-exam/dev/api-token
export SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456/devops-exam-queue

# Install dependencies
pip install -r requirements.txt

# Run
python app.py
```

### Run Service 2 Locally:
```bash
cd service2-consumer

# Set environment variables
export AWS_REGION=us-east-1
export SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456/devops-exam-queue
export S3_BUCKET_NAME=devops-exam-messages-bucket
export POLL_INTERVAL=10

# Install dependencies
pip install -r requirements.txt

# Run
python app.py
```

## CI/CD Integration

Tests are automatically run in GitHub Actions:

**CI Pipeline** (`.github/workflows/ci-service*.yml`):
1. Checkout code
2. Set up Python 3.11
3. Install dependencies (requirements.txt + test-requirements.txt)
4. **Run unit tests** with pytest
5. Build Docker image (only if tests pass)
6. Push to ECR
7. Trigger CD workflow

**CD Pipeline** (`.github/workflows/cd-service*.yml`):
1. Validate image in ECR
2. Update ECS task definition
3. Deploy to ECS Fargate
4. Wait for stability
5. Verify deployment

## Further Reading

- [Unit Tests Documentation](service1-api/test_app.py) - Detailed test implementation
- [GitHub Actions Workflows](../.github/workflows/README.md) - CI/CD pipeline details
- [Infrastructure](../infrastructure/README.md) - AWS infrastructure setup
