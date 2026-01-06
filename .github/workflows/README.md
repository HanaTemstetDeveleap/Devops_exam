# CI/CD with GitHub Actions

Automated CI/CD pipelines for building, testing, and deploying microservices to AWS ECS using GitHub Actions.

---

## Table of Contents
- [Workflows Overview](#workflows-overview)
- [Setup Instructions](#setup-instructions)
- [Security Considerations](#security-considerations)
- [Testing](#testing)
- [Monitoring Workflows](#monitoring-workflows)
- [Troubleshooting](#troubleshooting)

---

## Workflows Overview

### CI Workflows (Continuous Integration)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci-service1.yml` | Push/PR to `microservices/service1-api/**` | Run tests, build and push Service 1 Docker image to ECR |
| `ci-service2.yml` | Push/PR to `microservices/service2-consumer/**` | Run tests, build and push Service 2 Docker image to ECR |

### CD Workflows (Continuous Deployment)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `cd-service1.yml` | Automatically triggered by CI | Deploy Service 1 to ECS Fargate |
| `cd-service2.yml` | Automatically triggered by CI | Deploy Service 2 to ECS Fargate |

---

## Setup Instructions

### 1. Configure GitHub Secrets

Add the following secrets to your repository (**Settings → Secrets and variables → Actions**):

| Secret Name | Description | Required |
|-------------|-------------|----------|
| `AWS_ACCESS_KEY_ID` | AWS access key for GitHub Actions | ✅ |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for GitHub Actions | ✅ |

---

## Security Considerations

### Current Setup (Exam-Friendly)

⚠️ **Simplified for exam purposes:**
- Uses IAM user with AWS managed policies (`AmazonEC2ContainerRegistryPowerUser`, `AmazonECS_FullAccess`)
- Credentials stored as GitHub Secrets
- Suitable for learning and demonstration

### Production Recommendations

🔒 **For production environments:**

1. **Use GitHub OIDC Provider** (no long-lived credentials):
   ```hcl
   # Terraform example
   resource "aws_iam_openid_connect_provider" "github" {
     url = "https://token.actions.githubusercontent.com"
     client_id_list = ["sts.amazonaws.com"]
     thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
   }

   resource "aws_iam_role" "github_actions" {
     name = "github-actions-deployer"
     assume_role_policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{
         Effect = "Allow"
         Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
         Action = "sts:AssumeRoleWithWebIdentity"
         Condition = {
           StringEquals = {
             "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
             "token.actions.githubusercontent.com:sub" = "repo:org/repo:ref:refs/heads/main"
           }
         }
       }]
     })
   }
   ```

2. **Least Privilege IAM Policy** (specific permissions only):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ecr:GetAuthorizationToken",
           "ecr:BatchCheckLayerAvailability",
           "ecr:PutImage",
           "ecr:InitiateLayerUpload",
           "ecr:UploadLayerPart",
           "ecr:CompleteLayerUpload"
         ],
         "Resource": "arn:aws:ecr:*:*:repository/devops-exam-*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "ecs:UpdateService",
           "ecs:DescribeServices"
         ],
         "Resource": "arn:aws:ecs:*:*:service/devops-exam-cluster/*"
       }
     ]
   }
   ```

3. **Credential Rotation**: If using IAM users, rotate access keys every 90 days

4. **Audit Logging**: Enable CloudTrail for GitHub Actions API calls

### Current Setup Instructions (Exam)

**How to create AWS credentials:**

```bash
# Create IAM user for GitHub Actions
aws iam create-user --user-name github-actions-deployer

# Attach required policies (simplified for exam)
aws iam attach-user-policy \
  --user-name github-actions-deployer \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

aws iam attach-user-policy \
  --user-name github-actions-deployer \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

# Create access keys
aws iam create-access-key --user-name github-actions-deployer
# Copy the AccessKeyId and SecretAccessKey to GitHub Secrets
```

### 2. How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Developer pushes code to microservices/service1-api/      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
          ┌────────────────────────┐
          │  CI Workflow Triggered │
          │  (ci-service1.yml)     │
          └────────────┬───────────┘
                       │
                       ├─► Checkout code
                       ├─► Set up Python 3.11
                       ├─► Install dependencies
                       ├─► Run pytest with coverage
                       ├─► Configure AWS credentials
                       ├─► Login to ECR
                       ├─► Build Docker image
                       ├─► Push to ECR (tag: commit SHA)
                       │
                       ▼
          ┌────────────────────────┐
          │  CD Workflow Triggered │
          │  (cd-service1.yml)     │
          └────────────┬───────────┘
                       │
                       ├─► Validate image in ECR
                       ├─► Update ECS task definition
                       ├─► Deploy to ECS Fargate
                       ├─► Wait for stability
                       └─► Verify deployment
```

## Workflow Features

### CI Workflows

- ✅ **Automatic Triggers**: Runs on push to main branch or pull requests
- ✅ **Path Filtering**: Only runs when relevant service code changes
- ✅ **Automated Testing**: Runs pytest with coverage before building
- ✅ **Test Coverage**: Reports code coverage for each service
- ✅ **Fail Fast**: Build only proceeds if all tests pass
- ✅ **Docker Build**: Builds optimized Docker images
- ✅ **ECR Push**: Pushes images with commit SHA tag + latest tag
- ✅ **Auto CD Trigger**: Automatically triggers deployment after successful build
- ✅ **Summary Output**: Shows test results and image details in GitHub Actions summary

### CD Workflows

- ✅ **Image Validation**: Verifies image exists in ECR before deployment
- ✅ **Rolling Deployment**: Updates ECS service with zero downtime
- ✅ **Health Checks**: Waits for service to stabilize
- ✅ **Deployment Verification**: Confirms running tasks match desired count
- ✅ **Manual Trigger**: Can also be triggered manually with custom image tag

## Manual Deployment

To manually deploy a specific image version:

1. Go to **Actions** tab in GitHub
2. Select the CD workflow (e.g., "CD - Service 1")
3. Click **Run workflow**
4. Enter the image tag (e.g., `abc1234` or `latest`)
5. Click **Run workflow**

## Testing

Both microservices include comprehensive automated tests that run in the CI pipeline:

### Test Structure

```
microservices/
├── service1-api/
│   ├── app.py
│   ├── requirements.txt
│   ├── test-requirements.txt       # Test dependencies (pytest, moto, etc.)
│   └── test_app.py                 # Unit and integration tests
└── service2-consumer/
    ├── app.py
    ├── requirements.txt
    ├── test-requirements.txt       # Test dependencies
    └── test_app.py                 # Unit and integration tests
```

### Service 1 Tests (REST API)

**15 tests covering:**
- Payload validation (missing fields, invalid structure)
- Token validation with SSM Parameter Store
- Token caching mechanism
- SQS message sending
- API endpoints (health check, success/error flows)

**Run locally:**
```bash
cd microservices/service1-api
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v --cov=app --cov-report=term-missing
```

### Service 2 Tests (SQS Consumer)

**10 tests covering:**
- S3 upload functionality
- Hierarchical path creation (date-based)
- SQS message processing
- Queue polling (empty queue, partial success)
- End-to-end message flow

**Run locally:**
```bash
cd microservices/service2-consumer
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v --cov=app --cov-report=term-missing
```

### Mocked AWS Services

Tests use the **moto** library to mock AWS services:
- SSM Parameter Store (for API tokens)
- SQS (for message queuing)
- S3 (for file storage)

This ensures:
- No actual AWS costs during testing
- Fast, isolated test execution
- Consistent, repeatable results

## Monitoring Workflows

### View Workflow Runs

- Navigate to the **Actions** tab in your repository
- Click on any workflow run to see detailed logs
- Each step shows real-time output

### GitHub Actions Summary

After each workflow run, you'll see a summary with:
- Docker image details (CI workflows)
- Deployment information (CD workflows)
- Links to AWS resources

## Troubleshooting

### CI Workflow Fails to Push to ECR

**Error**: `denied: Your authorization token has expired`

**Solution**: Check that AWS credentials in GitHub Secrets are valid

```bash
# Test credentials locally
aws sts get-caller-identity
```

### CD Workflow Fails During Deployment

**Error**: `Service cannot be deployed because task definition is invalid`

**Solution**: Check ECS task definition and ensure it's compatible with Fargate

```bash
# Describe the task definition
aws ecs describe-task-definition --task-definition devops-exam-service1
```

### Workflow Doesn't Trigger

**Check**:
1. Path filters in workflow file match your changes
2. Branch name is correct (default: `main`)
3. Workflow file is in `.github/workflows/` directory

### Tests Fail in CI

**Error**: `ModuleNotFoundError: No module named 'pytest'`

**Solution**: Ensure `test-requirements.txt` is present and being installed

```bash
# Verify test dependencies file exists
ls microservices/service1-api/test-requirements.txt
ls microservices/service2-consumer/test-requirements.txt
```

**Error**: `ImportError: cannot import name 'app'`

**Solution**: Check that `app.py` exists in the same directory as `test_app.py`

## Workflow File Structure

```yaml
name: Workflow Name

on:
  push:
    branches: [main]
    paths:
      - 'path/to/watch/**'
  workflow_dispatch:

env:
  AWS_REGION: us-east-1
  # ... other environment variables

jobs:
  job-name:
    runs-on: ubuntu-latest
    steps:
      - name: Step name
        uses: action@version
        # or
        run: |
          command
```

## Best Practices

1. **Use Specific Actions Versions**: Pin to specific versions (e.g., `@v4`) for reproducibility
2. **Minimize Secrets**: Only store sensitive data in GitHub Secrets
3. **Cache Dependencies**: Use caching for faster builds (if needed)
4. **Fail Fast**: Validate early in the pipeline to save time
5. **Clear Naming**: Use descriptive job and step names
6. **Summary Output**: Use `$GITHUB_STEP_SUMMARY` for important information

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS Actions for GitHub](https://github.com/aws-actions)
- [Docker Build Push Action](https://github.com/docker/build-push-action)
- [ECS Deploy Task Definition](https://github.com/aws-actions/amazon-ecs-deploy-task-definition)
