# Jenkins CI/CD

This directory contains all Jenkins-related configuration and infrastructure.

## Directory Structure

```
jenkins/
├── 00-README.md                 # This file - start here
├── infrastructure/              # Terraform configuration for Jenkins server
│   ├── 00-README.md            # Infrastructure deployment guide
│   ├── 01-provider.tf          # AWS provider configuration
│   ├── 02-variables.tf         # Configurable parameters
│   ├── 03-terraform.tfvars     # Variable values
│   ├── 04-data.tf              # Data sources (AMI, VPC)
│   ├── 05-iam.tf               # IAM roles and policies
│   ├── 06-security-groups.tf   # Firewall rules
│   ├── 07-ec2.tf               # Jenkins EC2 instance
│   ├── 08-alb.tf               # Application Load Balancer
│   ├── 09-user-data.sh         # Automated Jenkins installation
│   ├── 10-jobs.groovy          # Job DSL - creates 4 CI/CD jobs
│   └── 11-outputs.tf           # Outputs (URL, password command)
└── pipelines/                   # Jenkins pipeline definitions
    ├── Jenkinsfile-CI-Service1  # CI for Service 1 (REST API)
    ├── Jenkinsfile-CI-Service2  # CI for Service 2 (SQS Consumer)
    ├── Jenkinsfile-CD-Service1  # CD for Service 1 (REST API)
    └── Jenkinsfile-CD-Service2  # CD for Service 2 (SQS Consumer)
```

## Infrastructure

Jenkins runs on AWS EC2 in a private subnet, accessible through an Application Load Balancer.

**Architecture:**
- EC2 t3.small instance (2 vCPU, 2GB RAM)
- Private subnet (secure, no direct internet access)
- Application Load Balancer (public access to Jenkins UI)
- IAM role with ECR and ECS permissions
- Automatic installation via user-data script

**Deploy Jenkins:**
```bash
cd infrastructure/
terraform init
terraform apply
```

See [infrastructure/README.md](infrastructure/README.md) for detailed deployment instructions.

## CI/CD Pipelines

The project includes **4 separate pipelines** - one CI and one CD for each service.

### CI Pipelines (Build and Push to ECR)

**CI-Service1** ([Jenkinsfile-CI-Service1](Jenkinsfile-CI-Service1)):
- Checks out code from Git
- Builds Service 1 (REST API) Docker image
- Pushes image to ECR with build number tag and 'latest' tag
- Cleans up local images

**CI-Service2** ([Jenkinsfile-CI-Service2](Jenkinsfile-CI-Service2)):
- Checks out code from Git
- Builds Service 2 (SQS Consumer) Docker image
- Pushes image to ECR with build number tag and 'latest' tag
- Cleans up local images

### CD Pipelines (Deploy to ECS)

**CD-Service1** ([Jenkinsfile-CD-Service1](Jenkinsfile-CD-Service1)):
- Accepts IMAGE_VERSION parameter (build number or 'latest')
- Verifies image exists in ECR
- Updates Service 1 in ECS cluster
- Waits for deployment to stabilize
- Verifies deployment status

**CD-Service2** ([Jenkinsfile-CD-Service2](Jenkinsfile-CD-Service2)):
- Accepts IMAGE_VERSION parameter (build number or 'latest')
- Verifies image exists in ECR
- Updates Service 2 in ECS cluster
- Waits for deployment to stabilize
- Verifies deployment status

### Automated Workflow

**Once configured, everything is automatic:**

1. Developer pushes code changes to `microservices/service1-api/`
2. Jenkins polls Git every 5 minutes, detects changes
3. **CI-Service1** automatically runs:
   - Builds Docker image with version (build #42)
   - Pushes to ECR
4. **CD-Service1** automatically triggered by CI:
   - Deploys version 42 to ECS
   - Waits for deployment to stabilize
5. Service 1 is now running version 42 in production!

**Same process for Service 2** - completely independent pipelines.

## Automated Job Creation

Jenkins is configured with **Job DSL** for automatic job creation. All 4 CI/CD jobs are created automatically!

### Setup Process

1. **Get Jenkins URL:**
   ```bash
   cd infrastructure/
   terraform output jenkins_url
   ```

2. **Get initial admin password:**
   ```bash
   aws ssm get-parameter --name /jenkins/initial-admin-password --with-decryption --query 'Parameter.Value' --output text --region us-east-1
   ```

3. **Access Jenkins UI** and complete the setup wizard (install suggested plugins, create admin user)

4. **Configure Git Repository:**
   - Open the `seed-job` in Jenkins
   - Click "Configure"
   - Update `jobs.groovy` in the workspace
   - Replace `YOUR_GIT_REPO_URL` with your actual Git repository URL
   - Save

5. **Run seed-job:**
   - Click "Build Now" on the seed-job
   - This will automatically create all 4 jobs:
     - CI-Service1
     - CI-Service2
     - CD-Service1
     - CD-Service2

6. **Done!** The jobs are now configured with:
   - ✅ Git polling (checks for changes every 5 minutes)
   - ✅ Automatic CI → CD trigger
   - ✅ Path-based filtering (only builds if relevant service changed)

## Security

- Jenkins instance has NO public IP
- Access only through ALB
- IAM role with least-privilege permissions
- Private Docker registry (ECR)
