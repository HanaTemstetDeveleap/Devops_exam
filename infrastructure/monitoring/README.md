# Monitoring Setup - Prometheus + Grafana

This directory contains the monitoring configuration for the DevOps Exam microservices.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet (Reviewers)                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ Port 3000 (Grafana UI)
                     ▼
         ┌────────────────────────┐
         │   Public Subnet        │
         │  ┌──────────────────┐  │
         │  │   Grafana ECS    │  │
         │  │  (Public IP)     │  │
         │  └──────────────────┘  │
         └────────────────────────┘
                     │
                     │ Query metrics
                     ▼
         ┌────────────────────────┐
         │  Private Subnet        │
         │  ┌──────────────────┐  │
         │  │ Prometheus ECS   │◄─┼─ service1.local:8080/metrics
         │  │ (No Public IP)   │  │   (Service 1 - REST API)
         │  └──────────────────┘  │
         │           ▲            │
         │           └────────────┼─ service2.local:8000/metrics
         │                        │   (Service 2 - Consumer)
         └────────────────────────┘
```

## Components

### 1. Prometheus (Custom Docker Image)

**Location**: `prometheus/`

- **Dockerfile**: Based on `prom/prometheus:latest` with custom configuration
- **prometheus.yml**: Scrape configuration using AWS Cloud Map service discovery
- **Scrape Targets**:
  - Service 1 (REST API): `service1.local:8080/metrics`
  - Service 2 (Consumer): `service2.local:8000/metrics`
  - Prometheus itself: `localhost:9090/metrics`

**Deployment**:
- Runs on ECS Fargate in **private subnet** (no public IP)
- Uses VPC endpoints for AWS API calls
- Accessible only within VPC

**DNS Service Discovery**:
- Uses AWS Cloud Map (Route 53 private DNS)
- Namespace: `local`
- Automatic discovery of ECS tasks

### 2. Grafana (Official Image)

**Location**: `grafana/dashboards/`

- **Image**: `grafana/grafana:latest` (no customization needed)
- **Deployment**: ECS Fargate in **public subnet** with public IP
- **Access**: `http://<GRAFANA_PUBLIC_IP>:3000`
- **Credentials**: `admin` / `admin` (change after first login)

**Pre-built Dashboard**:
- **File**: `grafana/dashboards/microservices-metrics.json`
- **Import**: Configuration → Data Sources → Add Prometheus → Dashboards → Import JSON

## Metrics Exposed

### Service 1 (REST API) Metrics

Available at: `http://service1.local:8080/metrics`

| Metric | Type | Description |
|--------|------|-------------|
| `service1_requests_total` | Counter | Total HTTP requests received |
| `service1_request_latency_seconds` | Histogram | Request latency in seconds |
| `service1_messages_sent_total` | Counter | Total messages sent to SQS |
| `service1_messages_send_errors_total` | Counter | Failed SQS message sends |

### Service 2 (Consumer) Metrics

Available at: `http://service2.local:8000/metrics`

| Metric | Type | Description |
|--------|------|-------------|
| `service2_polls_total` | Counter | Total SQS poll attempts |
| `service2_messages_received_total` | Counter | Messages received from SQS |
| `service2_messages_processed_total` | Counter | Messages successfully processed |
| `service2_s3_uploads_total` | Counter | Successful S3 uploads |
| `service2_s3_upload_errors_total` | Counter | Failed S3 upload attempts |

## Deployment Instructions

### 1. Build and Push Prometheus Image

The GitHub Actions workflow (`.github/workflows/ci-monitoring.yml`) automatically builds and pushes the Prometheus image when changes are detected in `infrastructure/monitoring/prometheus/`.

**Manual build**:
```bash
cd infrastructure/monitoring/prometheus

# Build the image
docker build -t devops-exam-prometheus .

# Tag for ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
docker tag devops-exam-prometheus:latest <ECR_REPO_URL>:latest

# Push to ECR
docker push <ECR_REPO_URL>:latest
```

### 2. Deploy Infrastructure

The monitoring infrastructure is defined in `infrastructure/12-monitoring.tf` and will be deployed with the main Terraform apply:

```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

### 3. Access Grafana

After deployment:

1. Get Grafana's public IP:
```bash
aws ecs list-tasks --cluster devops-exam-cluster --service-name devops-exam-grafana
aws ecs describe-tasks --cluster devops-exam-cluster --tasks <TASK_ARN> | jq '.tasks[0].attachments[0].details[] | select(.name=="networkInterfaceId") | .value'
aws ec2 describe-network-interfaces --network-interface-ids <ENI_ID> | jq '.NetworkInterfaces[0].Association.PublicIp'
```

2. Access Grafana: `http://<PUBLIC_IP>:3000`

3. Login with credentials: `admin` / `admin`

4. Add Prometheus data source:
   - Go to: Configuration → Data Sources → Add data source
   - Select: Prometheus
   - URL: `http://prometheus.local:9090`
   - Click: Save & Test

5. Import dashboard:
   - Go to: Dashboards → Import
   - Upload the JSON file from: `grafana/dashboards/microservices-metrics.json`
   - Select Prometheus data source
   - Click: Import

### 4. Verify Metrics Collection

Check if Prometheus is scraping targets:

```bash
# Port-forward to Prometheus (requires AWS Session Manager)
aws ecs execute-command \
  --cluster devops-exam-cluster \
  --task <PROMETHEUS_TASK_ID> \
  --container prometheus \
  --interactive \
  --command "/bin/sh"

# Or check from Grafana's data source test
```

## Security Considerations

✅ **Implemented**:
- Prometheus runs in **private subnet** (no public IP)
- Service-to-service communication within VPC only
- Security group rules:
  - Prometheus can scrape Service 1 (port 8080) and Service 2 (port 8000)
  - Services accept connections only from Prometheus security group
- VPC endpoints for ECR, CloudWatch (no internet egress needed)

⚠️ **For Exam Only** (production hardening needed):
- Grafana is publicly accessible (port 3000 open to 0.0.0.0/0)
  - For production: Restrict to office IPs or use VPN/bastion
- Default Grafana credentials (`admin/admin`)
  - For production: Use SSM Parameter Store or Secrets Manager
- No HTTPS/TLS on Grafana
  - For production: Add ALB with ACM certificate

## Troubleshooting

### Prometheus not scraping services

1. Check service discovery:
```bash
# DNS resolution should work from Prometheus container
nslookup service1.local
nslookup service2.local
```

2. Verify security group rules allow Prometheus → Services

3. Check CloudWatch Logs for errors:
```bash
aws logs tail /ecs/devops-exam/prometheus --follow
```

### Grafana can't connect to Prometheus

1. Verify DNS name: `prometheus.local:9090`
2. Check if Grafana and Prometheus are in same VPC
3. Verify Cloud Map namespace is `local`

### No metrics data in Grafana

1. Check if services are exposing `/metrics` endpoints
2. Verify Service 1 and Service 2 are running (ECS console)
3. Send test requests to Service 1 to generate metrics:
```bash
curl -X POST http://<ALB_DNS>/process \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Test",
      "email_sender": "Test User",
      "email_timestream": "1693561101",
      "email_content": "Test message"
    },
    "token": "<YOUR_TOKEN>"
  }'
```

## Cost Optimization

The monitoring setup is designed for **AWS Free Tier eligibility**:

- **ECS Fargate**: 2 tasks × 0.25 vCPU × 0.5 GB RAM (within free tier)
- **CloudWatch Logs**: 7-day retention, ~5 GB/month (within free tier)
- **VPC Endpoints**: Interface endpoints cost ~$7/month (no data transfer charges with VPC endpoints)
- **Cloud Map**: No additional cost for service discovery

**Total estimated cost**: ~$7-10/month (mostly VPC endpoints)

## Exam Bonus Completion ✅

This monitoring implementation fulfills **Bonus #2** from the exam requirements:

> "Add some monitor tool for the CI/CD process and the microservices activity (Grafana or Prometheus or similar tool)"

**What's implemented**:
- ✅ Prometheus for metrics collection
- ✅ Grafana for visualization
- ✅ Microservices instrumented with Prometheus client libraries
- ✅ Pre-built dashboard with key metrics
- ✅ Automated deployment via Terraform
- ✅ CI/CD pipeline for Prometheus image
- ✅ Secure VPC-based architecture

**Future enhancements** (optional):
- [ ] Alerting rules (Prometheus AlertManager)
- [ ] CI/CD pipeline metrics (GitHub Actions → Prometheus)
- [ ] Application-level tracing (Jaeger/Zipkin)
- [ ] Log aggregation (Loki + Promtail)
