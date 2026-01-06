# Monitoring Setup - Prometheus + Grafana

**Bonus #2 Implementation**: Complete monitoring solution for microservices and CI/CD pipeline.

---

## Table of Contents
- [Architecture](#architecture)
- [Components](#components)
- [Metrics Collected](#metrics-collected)
- [Quick Access Guide](#quick-access-guide)
- [Deployment](#deployment)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

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
         └────────────┬───────────┘
                      │
                      │ Query metrics (http://prometheus.local:9090)
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

**Key Design Decisions**:
- **Prometheus in private subnet**: No public access, metrics stay internal
- **AWS Cloud Map service discovery**: Automatic discovery via DNS (`*.local`)
- **Grafana in public subnet**: Accessible for reviewers without VPN
- **VPC endpoints**: No internet egress needed for AWS API calls

---

## Components

### 1. Prometheus (Custom Docker Image)

**Location**: `prometheus/`

**Configuration**:
- **Base Image**: `prom/prometheus:latest`
- **Config File**: `prometheus.yml` with scrape targets
- **Scrape Interval**: 15 seconds
- **Retention**: 15 days

**Scrape Targets**:
```yaml
- Service 1 (REST API):    service1.local:8080/metrics
- Service 2 (Consumer):    service2.local:8000/metrics
- Prometheus (self):       localhost:9090/metrics
```

**DNS Service Discovery**:
- Uses **AWS Cloud Map** (Route 53 private hosted zone)
- Namespace: `local`
- Automatic registration when ECS tasks start
- No manual configuration needed

**Deployment**:
- ECS Fargate task in **private subnet**
- 0.25 vCPU, 0.5 GB RAM
- No public IP
- Accessible only within VPC

### 2. Grafana (Official Image)

**Configuration**:
- **Image**: `grafana/grafana:latest` (no customization)
- **Port**: 3000
- **Default Credentials**: `admin` / `admin`
- **Data Sources**: Prometheus + CloudWatch

**Pre-built Dashboards**:

| Dashboard | File | Description |
|-----------|------|-------------|
| **Microservices Metrics** | `grafana/dashboards/microservices-metrics.json` | Service 1 & 2 application metrics |
| **CI/CD Monitoring** | `grafana/dashboards/ci-cd-monitoring.json` | ECS deployment activity, task health |

**Deployment**:
- ECS Fargate task in **public subnet**
- 0.25 vCPU, 0.5 GB RAM
- Public IP assigned (for reviewer access)
- Security group allows port 3000 from 0.0.0.0/0

---

## Metrics Collected

### Service 1 (REST API) Metrics

**Endpoint**: `http://service1.local:8080/metrics`

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `service1_requests_total` | Counter | Total HTTP requests received | `method`, `endpoint`, `status` |
| `service1_request_latency_seconds` | Histogram | Request processing time | `endpoint` |
| `service1_messages_sent_total` | Counter | Messages successfully sent to SQS | - |
| `service1_messages_send_errors_total` | Counter | Failed SQS send attempts | `error_type` |
| `service1_token_validation_failures_total` | Counter | Invalid token attempts | - |

**Example Queries**:
```promql
# Request rate (requests per second)
rate(service1_requests_total[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(service1_request_latency_seconds_bucket[5m]))

# Error rate percentage
(rate(service1_messages_send_errors_total[5m]) / rate(service1_messages_sent_total[5m])) * 100
```

### Service 2 (Consumer) Metrics

**Endpoint**: `http://service2.local:8000/metrics`

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `service2_polls_total` | Counter | Total SQS poll attempts | - |
| `service2_messages_received_total` | Counter | Messages received from SQS | - |
| `service2_messages_processed_total` | Counter | Messages successfully processed | - |
| `service2_s3_uploads_total` | Counter | Successful S3 uploads | - |
| `service2_s3_upload_errors_total` | Counter | Failed S3 upload attempts | `error_type` |
| `service2_processing_duration_seconds` | Histogram | Message processing time | - |

**Example Queries**:
```promql
# Messages processed per minute
rate(service2_messages_processed_total[1m]) * 60

# S3 upload success rate
(service2_s3_uploads_total / service2_messages_processed_total) * 100

# Processing lag (messages in queue vs processed)
service2_messages_received_total - service2_messages_processed_total
```

### CI/CD Metrics (CloudWatch)

**Source**: AWS CloudWatch Container Insights + ECS Metrics

| Metric | Description |
|--------|-------------|
| `RunningTaskCount` | Current number of running ECS tasks |
| `DesiredTaskCount` | Expected number of tasks (target) |
| `CPUUtilization` | Task CPU usage percentage |
| `MemoryUtilization` | Task memory usage percentage |

**CloudWatch Logs**:
- `/ecs/devops-exam/service1` - Service 1 application logs
- `/ecs/devops-exam/service2` - Service 2 application logs
- `/ecs/devops-exam/prometheus` - Prometheus logs
- `/ecs/devops-exam/grafana` - Grafana logs

---

## Quick Access Guide

### Access Grafana UI

```bash
# Get Grafana public IP
TASK_ARN=$(aws ecs list-tasks \
  --cluster devops-exam-cluster \
  --service-name devops-exam-grafana \
  --query 'taskArns[0]' \
  --output text)

ENI=$(aws ecs describe-tasks \
  --cluster devops-exam-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text)

GRAFANA_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)

echo "Grafana URL: http://$GRAFANA_IP:3000"
echo "Username: admin"
echo "Password: admin"
```

**Quick one-liner**:
```bash
aws ecs describe-tasks --cluster devops-exam-cluster --tasks $(aws ecs list-tasks --cluster devops-exam-cluster --service-name devops-exam-grafana --query 'taskArns[0]' --output text) --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text | xargs -I {} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text
```

### Setup Grafana (First Time)

1. **Login**: Navigate to `http://<GRAFANA_IP>:3000`, login with `admin`/`admin`

2. **Add Prometheus Data Source**:
   - Go to: **Configuration** → **Data Sources** → **Add data source**
   - Select: **Prometheus**
   - URL: `http://prometheus.local:9090`
   - Click: **Save & Test** (should show green checkmark)

3. **Add CloudWatch Data Source** (for CI/CD dashboard):
   - Go to: **Configuration** → **Data Sources** → **Add data source**
   - Select: **CloudWatch**
   - Authentication Provider: **AWS SDK Default** (uses task IAM role)
   - Default Region: `us-east-1`
   - Click: **Save & Test**

4. **Import Microservices Dashboard**:
   - Go to: **Dashboards** → **Import**
   - Click: **Upload JSON file**
   - Select: `infrastructure/monitoring/grafana/dashboards/microservices-metrics.json`
   - Data source: Select the Prometheus source
   - Click: **Import**

5. **Import CI/CD Dashboard**:
   - Go to: **Dashboards** → **Import**
   - Upload: `infrastructure/monitoring/grafana/dashboards/ci-cd-monitoring.json`
   - Data source: Select the CloudWatch source
   - Click: **Import**

### Generate Test Data for Metrics

To populate dashboards with real data:

```bash
# Get required values
cd infrastructure
export ALB_URL=$(terraform output -raw alb_dns_name)
export API_TOKEN=$(aws ssm get-parameter \
  --name /devops-exam/dev/api-token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Send 20 test requests (generates ~1 minute of activity)
for i in {1..20}; do
  curl -X POST "http://${ALB_URL}/api/message" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "email_subject": "Test Message '$i'",
        "email_sender": "test@example.com",
        "email_timestream": "1693561101",
        "email_content": "Monitoring test message '$i'"
      },
      "token": "'$API_TOKEN'"
    }'
  echo " [$i/20]"
  sleep 3
done

echo "✅ Test data generated. Check Grafana dashboards in ~30 seconds."
```

**This will generate**:
- Service 1 request metrics (rate, latency, SQS sends)
- SQS messages for Service 2 to process
- Service 2 processing and S3 upload metrics

---

## Deployment

### Option 1: Automatic (via Terraform)

Monitoring infrastructure is deployed automatically with main infrastructure:

```bash
cd infrastructure
terraform init
terraform apply
```

The following resources are created by `12-monitoring.tf`:
- ECR repository for custom Prometheus image
- ECS task definitions for Prometheus and Grafana
- ECS services with desired_count=1
- Security groups for monitoring traffic
- Cloud Map namespace and service discovery

### Option 2: Build Prometheus Image Manually

If you need to rebuild the Prometheus image:

```bash
cd infrastructure/monitoring/prometheus

# Build image
docker build -t devops-exam-prometheus .

# Get ECR repository URL
ECR_REPO=$(cd ../../ && terraform output -raw ecr_prometheus_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${ECR_REPO%%/*}

# Tag and push
docker tag devops-exam-prometheus:latest $ECR_REPO:latest
docker push $ECR_REPO:latest

# Force ECS to pull new image
aws ecs update-service \
  --cluster devops-exam-cluster \
  --service devops-exam-prometheus \
  --force-new-deployment
```

### CI/CD for Monitoring

**GitHub Actions workflow** (`.github/workflows/ci-monitoring.yml`):
- Triggered on changes to `infrastructure/monitoring/prometheus/**`
- Builds Prometheus Docker image
- Pushes to ECR
- Updates ECS service

---

## Security

### Implemented Security Measures

✅ **Network Isolation**:
- Prometheus runs in **private subnet** (no public IP, no internet access)
- Only Grafana can query Prometheus (security group rules)
- Services expose metrics only within VPC

✅ **IAM Least Privilege**:
- Prometheus task role: Read-only access to Cloud Map for service discovery
- Grafana task role: Read-only access to CloudWatch for CI/CD dashboard
- No write permissions to any AWS services

✅ **VPC Endpoints**:
- ECR, CloudWatch Logs accessed via private endpoints
- No NAT Gateway traversal for monitoring components

✅ **Service Discovery**:
- DNS-based discovery (Cloud Map) instead of hardcoded IPs
- Automatic updates when tasks are replaced

### Security Considerations for Production

⚠️ **Current Setup (Exam-Friendly)**:
- Grafana publicly accessible on port 3000 (0.0.0.0/0)
- Default credentials (`admin`/`admin`)
- No HTTPS/TLS encryption
- No authentication on Prometheus endpoints

🔒 **Production Recommendations**:
1. **Restrict Grafana Access**:
   - Use ALB with HTTPS (ACM certificate)
   - Restrict security group to office IPs or VPN
   - Or use AWS VPN/bastion host

2. **Secure Credentials**:
   - Store in AWS Secrets Manager or SSM Parameter Store
   - Rotate regularly
   - Enforce strong password policy

3. **Enable Authentication**:
   - Grafana: OAuth/SAML integration
   - Prometheus: Enable basic auth or mutual TLS

4. **Monitoring for Monitoring**:
   - CloudWatch alarms for Prometheus/Grafana task failures
   - Dead letter queue for failed metric scrapes

---

## Troubleshooting

### Issue: Grafana Shows "No Data" for Prometheus

**Symptoms**: Dashboards load but panels show "No data"

**Diagnosis**:
```bash
# 1. Check if Prometheus service is running
aws ecs describe-services \
  --cluster devops-exam-cluster \
  --services devops-exam-prometheus \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# 2. Check Prometheus logs
aws logs tail /ecs/devops-exam/prometheus --follow

# 3. Verify DNS resolution (from Grafana container)
aws ecs execute-command \
  --cluster devops-exam-cluster \
  --task <GRAFANA_TASK_ARN> \
  --container grafana \
  --interactive \
  --command "nslookup prometheus.local"
```

**Solutions**:
- Ensure Prometheus task is running (`runningCount = 1`)
- Verify Cloud Map namespace is `local` (check `12-monitoring.tf`)
- Check security group allows Grafana → Prometheus on port 9090

---

### Issue: Prometheus Not Scraping Service Metrics

**Symptoms**: Prometheus is running but service metrics are missing

**Diagnosis**:
```bash
# 1. Check if services are registered in Cloud Map
aws servicediscovery list-instances \
  --service-id <SERVICE_DISCOVERY_ID>

# 2. Check service logs for metrics endpoint errors
aws logs tail /ecs/devops-exam/service1 --follow | grep metrics
aws logs tail /ecs/devops-exam/service2 --follow | grep metrics

# 3. Verify services expose /metrics endpoint
curl http://<ALB_URL>/metrics  # Should return 404 (not exposed via ALB)
# Metrics are only accessible within VPC via Cloud Map DNS
```

**Solutions**:
- Ensure Service 1 and Service 2 are running
- Verify `prometheus-client` library is installed in services
- Check security groups allow Prometheus SG → Services SG on ports 8080/8000

---

### Issue: CloudWatch Data Not Showing in CI/CD Dashboard

**Symptoms**: Grafana CloudWatch data source test succeeds but no data in dashboard

**Diagnosis**:
```bash
# 1. Check if Container Insights is enabled
aws ecs describe-clusters \
  --clusters devops-exam-cluster \
  --query 'clusters[0].settings'
# Should show: containerInsights = enabled

# 2. Verify CloudWatch metrics exist
aws cloudwatch list-metrics \
  --namespace ECS/ContainerInsights \
  --dimensions Name=ClusterName,Value=devops-exam-cluster
```

**Solutions**:
- Enable Container Insights in `10-ecs.tf` (see line 10: `value = "enabled"`)
- Wait 5-10 minutes for metrics to appear after enabling
- Check Grafana task IAM role has `cloudwatch:GetMetricData` permission

---

### Issue: Grafana Public IP Keeps Changing

**Symptoms**: Need to lookup Grafana IP after every ECS deployment

**Why**: ECS Fargate tasks get new IPs when redeployed

**Solutions**:

**Option 1 - Use ALB** (Recommended for production):
```hcl
# Add to 09-alb.tf or create new file
resource "aws_lb_target_group" "grafana" {
  name     = "grafana-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana/*"]
    }
  }
}
```

**Option 2 - Elastic IP** (Not supported by Fargate directly, requires NAT Gateway workaround)

**Option 3 - CloudFormation Output** (Current approach):
Save the IP lookup command as an alias:
```bash
alias grafana-ip='aws ecs describe-tasks --cluster devops-exam-cluster --tasks $(aws ecs list-tasks --cluster devops-exam-cluster --service-name devops-exam-grafana --query "taskArns[0]" --output text) --query "tasks[0].attachments[0].details[?name==\`networkInterfaceId\`].value" --output text | xargs -I {} aws ec2 describe-network-interfaces --network-interface-ids {} --query "NetworkInterfaces[0].Association.PublicIp" --output text'
```

---

## Cost Breakdown

**Monthly Costs** (AWS Free Tier eligible components):

| Component | Specs | Monthly Cost | Notes |
|-----------|-------|--------------|-------|
| **Prometheus ECS Task** | 0.25 vCPU, 0.5 GB RAM | $0-3 | Within free tier (limited hours) |
| **Grafana ECS Task** | 0.25 vCPU, 0.5 GB RAM | $0-3 | Within free tier (limited hours) |
| **CloudWatch Logs** | ~5 GB ingestion, 7-day retention | $0 | Within 5 GB free tier |
| **Cloud Map** | Service discovery (2 services) | $0 | No charge for service discovery |
| **VPC Endpoints** | Interface endpoints (if used) | $7-10 | $0.01/hour per endpoint |

**Total Estimated Cost**: **$7-13/month** (mostly VPC endpoints if used)

**Cost Optimization**:
- Container Insights can be disabled to save costs (set `containerInsights = "disabled"` in `10-ecs.tf`)
- CloudWatch Logs retention can be reduced to 3 days
- Monitoring tasks can be scaled to 0 when not actively reviewing

---

## Exam Bonus Completion ✅

This implementation fulfills **Bonus #2** from the exam requirements:

> "Add some monitor tool for the CI/CD process and the microservices activity (Grafana or Prometheus or similar tool)"

### What's Delivered:

✅ **Prometheus** - Metrics collection from microservices
✅ **Grafana** - Visualization with pre-built dashboards
✅ **Microservices Instrumentation** - Custom metrics in both services
✅ **CI/CD Monitoring** - ECS task health via CloudWatch Container Insights
✅ **Infrastructure as Code** - All monitoring deployed via Terraform
✅ **CI/CD for Monitoring** - GitHub Actions workflow for Prometheus updates
✅ **Secure Architecture** - Private Prometheus, public Grafana with security groups
✅ **Documentation** - Complete setup and troubleshooting guide

### Dashboard Features:

**Microservices Dashboard**:
- Real-time request rates and latency (p50, p95, p99)
- SQS message throughput
- S3 upload success/failure rates
- Token validation failures
- Error rate trends

**CI/CD Dashboard**:
- Running vs Desired task counts
- Deployment events timeline
- Container CPU/Memory utilization
- ECS service health status

---

## Screenshots

### Grafana Dashboard

![Grafana Monitoring Dashboard](screenshots/Screenshot%20from%202026-01-06%2016-25-42.png)

---

## Next Steps (Optional Enhancements)

- [ ] **Alerting**: Set up Prometheus AlertManager for SLA violations
- [ ] **Log Aggregation**: Add Loki + Promtail for centralized logging
- [ ] **Distributed Tracing**: Integrate Jaeger/Zipkin for request tracing
- [ ] **Custom Metrics**: Add business-specific metrics (messages per customer, etc.)
- [ ] **Dashboard Automation**: Auto-provision Grafana dashboards via Terraform
- [ ] **HTTPS**: Add ALB with ACM certificate for Grafana
