# DevOps Exam — Quick Overview

Short instructions for the examiner to run the project and find detailed docs.

Structure
- `infrastructure/` — Terraform code (provider, VPC, IAM, ECR, S3, SQS, ALB, ECS).
- `microservices/` — Two Python services, unit tests and E2E test.

Key docs
- Infrastructure README: [infrastructure/00-README.md](infrastructure/00-README.md#L1)
- Microservices README: [microservices/README.md](microservices/README.md#L1)

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
