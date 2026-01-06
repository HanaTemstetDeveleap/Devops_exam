#!/usr/bin/env bash
set -euo pipefail

# Run E2E test helper
# Creates a venv (if missing), installs deps, exports env vars from Terraform/SSM and runs pytest

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MICROSERVICES_DIR="$ROOT_DIR"
INFRA_DIR="$ROOT_DIR/../infrastructure"

echo "Running E2E helper from: $MICROSERVICES_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform CLI not found in PATH." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI not found in PATH." >&2
  exit 1
fi

cd "$MICROSERVICES_DIR"

# Create venv if missing
if [ ! -d .venv ]; then
  echo "Creating virtual environment .venv"
  python3 -m venv .venv
fi

# Activate
. .venv/bin/activate

echo "Upgrading pip and installing test dependencies..."
python -m pip install -U pip
pip install pytest boto3 requests

echo "Exporting environment variables from Terraform/SSM..."
export ALB_DNS=$(cd "$INFRA_DIR" && terraform output -raw alb_dns_name)
export S3_BUCKET_NAME=$(cd "$INFRA_DIR" && terraform output -raw s3_bucket_name)
export API_TOKEN=$(aws ssm get-parameter --name /devops-exam/dev/api-token --with-decryption --query 'Parameter.Value' --output text)
export AWS_REGION=${AWS_REGION:-us-east-1}

echo "ALB_DNS=$ALB_DNS"
echo "S3_BUCKET_NAME=$S3_BUCKET_NAME"
echo "AWS_REGION=$AWS_REGION"

echo "WARNING: This will run integration tests against real AWS resources and may incur costs."
read -r -p "Proceed? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted by user.";
  exit 0
fi

echo "Running pytest e2e_test/e2e_test.py..."
pytest e2e_test/e2e_test.py -v -s

echo "E2E run finished."
