# Monitoring Setup - Prometheus + Grafana

**Bonus #2 Implementation**: Monitoring solution for microservices and CI/CD pipeline.

---

## Architecture

```
Internet → Grafana (Public) → Prometheus (Private) → Service 1 & Service 2
                                                      (via Cloud Map DNS)
```

**Components**:
- **Prometheus**: Collects metrics from services via AWS Cloud Map service discovery
- **Grafana**: Visualization dashboard (publicly accessible for reviewers)
- **Cloud Map**: DNS-based service discovery (`service1.local`, `service2.local`)

---

## Quick Access

### Get Grafana URL

```bash
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

---

## Setup Grafana

1. **Login**: Navigate to `http://<GRAFANA_IP>:3000`
   - Username: `admin`
   - Password: `admin`

2. **Add Prometheus Data Source**:
   - Go to: **Configuration** → **Data Sources** → **Add data source**
   - Select: **Prometheus**
   - URL: `http://prometheus.local:9090`
   - Click: **Save & Test**

3. **Add CloudWatch Data Source** (for CI/CD metrics):
   - Go to: **Configuration** → **Data Sources** → **Add data source**
   - Select: **CloudWatch**
   - Authentication Provider: **AWS SDK Default**
   - Default Region: `us-east-1`
   - Click: **Save & Test**

4. **Import Dashboards**:
   - Go to: **Dashboards** → **Import**
   - Upload: `infrastructure/monitoring/grafana/dashboards/microservices-metrics.json`
   - Select Prometheus data source
   - Click: **Import**

   - Upload: `infrastructure/monitoring/grafana/dashboards/ci-cd-monitoring.json`
   - Select CloudWatch data source
   - Click: **Import**

---

## Metrics Collected

### Service 1 (REST API)
- Request rate and latency (p50, p95, p99)
- SQS messages sent/failed
- Token validation failures

### Service 2 (Consumer)
- SQS polling activity
- Messages processed
- S3 uploads (success/failures)

### CI/CD (CloudWatch)
- ECS running/desired task counts
- CPU/Memory utilization
- Deployment events

---

## Generate Test Data

```bash
cd infrastructure
export ALB_URL=$(terraform output -raw alb_dns_name)
export API_TOKEN=$(aws ssm get-parameter \
  --name /devops-exam/dev/api-token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Send 20 test requests
for i in {1..20}; do
  curl -X POST "http://${ALB_URL}/api/message" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "email_subject": "Test '$i'",
        "email_sender": "test@example.com",
        "email_timestream": "1693561101",
        "email_content": "Test message '$i'"
      },
      "token": "'$API_TOKEN'"
    }'
  echo " [$i/20]"
  sleep 3
done
```

Check Grafana dashboards in ~30 seconds for metrics.

---

## Deployment

Monitoring is deployed automatically with main infrastructure:

```bash
cd infrastructure
terraform init
terraform apply
```

**What's created**:
- Prometheus ECS service (private subnet)
- Grafana ECS service (public subnet with public IP)
- CloudWatch log groups
- Security groups
- Cloud Map service discovery

---

## Screenshots

### Grafana Dashboard

![Grafana Monitoring Dashboard](screenshots/Screenshot%20from%202026-01-06%2016-25-42.png)

---

## Troubleshooting

### Grafana Shows "No Data"

**Check Prometheus is running**:
```bash
aws ecs describe-services \
  --cluster devops-exam-cluster \
  --services devops-exam-prometheus \
  --query 'services[0].{Status:status,Running:runningCount}'
```

**Check Prometheus logs**:
```bash
aws logs tail /ecs/devops-exam/prometheus --follow
```

### Prometheus Not Scraping Services

**Verify services are running**:
```bash
aws ecs list-tasks --cluster devops-exam-cluster
```

**Check service logs**:
```bash
aws logs tail /ecs/devops-exam/service1 --follow | grep metrics
aws logs tail /ecs/devops-exam/service2 --follow | grep metrics
```

---

## Cost

**Monthly**: ~$3-5 (covered by AWS Free Tier for limited hours)
- Prometheus: 0.25 vCPU, 0.5 GB RAM
- Grafana: 0.25 vCPU, 0.5 GB RAM
- CloudWatch Logs: ~1 GB/month (within free tier)

---

## Security Notes

**Current setup** (exam-friendly):
- Grafana publicly accessible (0.0.0.0/0) on port 3000
- Default credentials
- No HTTPS

**For production**:
- Restrict Grafana access via ALB + security groups
- Use AWS Secrets Manager for credentials
- Enable HTTPS with ACM certificate
- Enable Prometheus authentication
