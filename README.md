# DevOps Exam — Quick Overview

Summary: This repository contains two microservices (API and consumer), Terraform infrastructure, CI/CD pipelines, and unit and E2E tests.

Structure
- `infrastructure/` — Terraform code (provider, VPC, IAM, ECR, S3, SQS, ALB, ECS).
- `microservices/` — Two Python services, unit tests and E2E test.

Key docs
- Infrastructure README: [infrastructure/00-README.md](infrastructure/00-README.md#L1)
- Microservices README: [microservices/README.md](microservices/README.md#L1)
 - Workflows overview: [.github/workflows/README.md](.github/workflows/README.md#L1)

Assignment summary
- Two containerized Python microservices:
	- `service1-api` — REST API behind ALB, validates token (SSM) and pushes messages to SQS.
	- `service2-consumer` — polls SQS and writes messages to S3 (date-based path).
- Infrastructure is defined with Terraform in `infrastructure/` (VPC, IAM, ECR, S3, SQS, ALB, ECS).
- CI (build & test) and CD (deploy) are implemented with GitHub Actions in `.github/workflows/`.

Quick Start

1) Prepare

```bash
# From repo root
cd Devops_exam

# Ensure AWS CLI configured with credentials that have permissions for the exam
aws sts get-caller-identity
```

2) Deploy infrastructure (creates ALB, S3, SQS, ECR, ECS)

```bash
cd infrastructure
terraform init
terraform apply -auto-approve
```

3) Build & push images (optional local build — CI also builds on push)

```bash
# Build locally and push to ECR (or let CI do this)
cd ../microservices/service1-api
docker build -t service1-api:local .
# (login/push steps depend on your registry)

cd ../service2-consumer
docker build -t service2-consumer:local .
```

4) Get runtime values

```bash
cd ../infrastructure
export ALB_DNS=$(terraform output -raw alb_dns_name)
export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
export API_TOKEN=$(aws ssm get-parameter --name /devops-exam/dev/api-token --with-decryption --query 'Parameter.Value' --output text)
export AWS_REGION=${AWS_REGION:-us-east-1}
```

5) Run E2E test (verifies API → SQS → Consumer → S3)

```bash
cd ../microservices
chmod +x e2e_test/run_e2e.sh
./e2e_test/run_e2e.sh
```

6) Run unit tests (mocked AWS)

```bash
cd microservices/service1-api
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v

cd ../service2-consumer
pip install -r requirements.txt -r test-requirements.txt
pytest test_app.py -v
```

Notes & grading checklist
- The repo includes Terraform IaC for required AWS resources (SQS, S3, ALB, ECS).
- CI workflows build images and push to ECR; CD workflows deploy to ECS.
- Tests exist (unit + E2E). E2E uses real AWS resources — avoid running on every CI build.
- Bonus: monitoring/alerts (if implemented) are documented in `.github/workflows/README.md` or respective README files.

If you want, I can produce a single checklist for the reviewer matching the task file.

Quick Start (all steps minimal)
1. Deploy infra (creates ALB, S3, SQS, ECR, ECS):

```bash
cd infrastructure
terraform init
terraform apply
```

2. Get runtime values and credentials:

```bash
cd ../infrastructure
export ALB_DNS=$(terraform output -raw alb_dns_name)
export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
export API_TOKEN=$(aws ssm get-parameter --name /devops-exam/dev/api-token --with-decryption --query 'Parameter.Value' --output text)
```

3. Run E2E tests (manual step — uses real AWS resources):

```bash
cd ../microservices
chmod +x e2e_test/run_e2e.sh
./e2e_test/run_e2e.sh
```

Notes
- E2E tests use real AWS resources and incur small costs — do not run on every CI build. Run them manually or in a pre-deploy pipeline.
- Unit tests are in each service folder (`service1-api/test_app.py`, `service2-consumer/test_app.py`) and run with `pytest`.

Contact
- If anything is unclear, open an issue in the repo or ask for steps to reproduce locally.
