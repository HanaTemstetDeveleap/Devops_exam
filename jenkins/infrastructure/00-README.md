# Jenkins Infrastructure

This directory contains the Terraform configuration for deploying Jenkins CI/CD server on AWS.

## Architecture

- **Jenkins EC2 Instance**: Runs in private subnet for security
- **Application Load Balancer**: Provides public access to Jenkins UI
- **IAM Role**: Grants Jenkins permissions to push to ECR and update ECS services
- **Security Groups**: Restricts access appropriately

## Prerequisites

1. Main infrastructure must be deployed first (from `../infrastructure/`)
2. AWS credentials configured
3. Terraform installed

## Deployment

1. Initialize Terraform:
```bash
terraform init
```

2. Review the plan:
```bash
terraform plan
```

3. Deploy Jenkins:
```bash
terraform apply
```

4. Get Jenkins URL and initial password:
```bash
terraform output jenkins_url
terraform output jenkins_setup_instructions
```

## Accessing Jenkins

1. Wait 3-5 minutes for Jenkins to install
2. Access Jenkins at the URL from `terraform output jenkins_url`
3. Get initial admin password using Systems Manager Session Manager

## What Gets Installed

- Jenkins (latest LTS)
- Docker and Docker Compose
- AWS CLI v2
- Java 17
- Git

## Security

- Jenkins runs in private subnet (no direct internet access)
- Access only through ALB
- IAM role attached (no AWS credentials needed)
- Security groups restrict access

## Cleanup

To destroy the Jenkins infrastructure:
```bash
terraform destroy
```

**Note**: This does not affect the main infrastructure (microservices).
