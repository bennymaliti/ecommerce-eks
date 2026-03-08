# 🛒 Multi-Tier E-Commerce Application on Amazon EKS

[![CI/CD Pipeline](https://github.com/YOUR_USERNAME/ecommerce-eks/actions/workflows/deploy.yml/badge.svg)](https://github.com/bennymaliti/ecommerce-eks/actions)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes-326CE5)](https://kubernetes.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900)](https://aws.amazon.com/)

A production-grade, highly available multi-tier e-commerce platform running on Amazon EKS. Demonstrates end-to-end cloud infrastructure skills including IaC, container orchestration, autoscaling, observability, and CI/CD.

---

## 📐 Architecture Overview

```
                          ┌─────────────────────────────────────────────────────┐
                          │                    AWS Cloud                         │
                          │                                                       │
  Users ──► Route 53 ──► │  CloudFront ──► ALB (AWS Load Balancer Controller)  │
                          │                        │                              │
                          │         ┌──────────────┴──────────────┐              │
                          │         │       EKS Cluster            │              │
                          │         │  ┌──────────┐ ┌──────────┐  │              │
                          │         │  │ Frontend │ │ Frontend │  │              │
                          │         │  │  Pod(s)  │ │  Pod(s)  │  │              │
                          │         │  │  (Nginx) │ │  (Nginx) │  │              │
                          │         │  └────┬─────┘ └────┬─────┘  │              │
                          │         │       └──────┬──────┘        │              │
                          │         │         ┌────▼─────┐         │              │
                          │         │         │ Backend  │         │              │
                          │         │         │ API Pods │◄───────── HPA          │
                          │         │         │(Node.js) │         │              │
                          │         │         └────┬─────┘         │              │
                          │         │    ┌─────────┴──────────┐    │              │
                          │         │    │                     │    │              │
                          │         │  ┌─▼──────┐    ┌───────▼─┐  │              │
                          │         │  │ Redis  │    │Prometheus│  │              │
                          │         │  │ Cache  │    │ Grafana  │  │              │
                          │         │  └────────┘    └─────────┘  │              │
                          │         └──────────────────────────────┘              │
                          │                    │          │                        │
                          │         ┌──────────▼──┐  ┌───▼──────┐               │
                          │         │ RDS MySQL   │  │    S3     │               │
                          │         │ Multi-AZ    │  │  Bucket   │               │
                          │         │(Private Sub)│  │(Images)   │               │
                          │         └─────────────┘  └──────────┘               │
                          └─────────────────────────────────────────────────────┘

  VPC: 3 Public Subnets + 3 Private Subnets across 3 AZs (us-east-1a/b/c)
```

### Component Summary

| Layer | Technology | Purpose |
| --- | --- | --- |
| DNS | Route 53 | Domain management |
| CDN | CloudFront | Static asset caching, global edge |
| Ingress | AWS ALB Controller | L7 load balancing into EKS |
| Frontend | React + Nginx (container) | Product UI served via Nginx |
| Backend API | Node.js REST API (container) | Business logic, auth, orders |
| Cache | Redis (in-cluster) | Session store, product cache |
| Database | Amazon RDS MySQL (Multi-AZ) | Persistent transactional data |
| Storage | Amazon S3 | Product images, static assets |
| IaC | Terraform | All AWS infrastructure |
| Orchestration | Amazon EKS (Kubernetes 1.29) | Container scheduling |
| Autoscaling | HPA (CPU + Memory) | Dynamic pod scaling |
| Monitoring | Prometheus + Grafana | Metrics and dashboards |
| CI/CD | GitHub Actions | Build, push, deploy pipeline |
| Registry | Amazon ECR | Docker image storage |

---

## 📁 Repository Structure

```text
ecommerce-eks/
├── terraform/                  # All AWS infrastructure as code
│   ├── main.tf                 # Provider config, backend
│   ├── vpc.tf                  # VPC, subnets, route tables, NAT
│   ├── eks.tf                  # EKS cluster and node groups
│   ├── rds.tf                  # RDS MySQL Multi-AZ
│   ├── s3.tf                   # S3 bucket + policies
│   ├── iam.tf                  # IAM roles (IRSA, nodes, CI/CD)
│   ├── ecr.tf                  # ECR repositories
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Exported values
│   └── terraform.tfvars.example
├── kubernetes/                 # K8s manifests
│   ├── namespace.yaml
│   ├── frontend/               # Deployment, Service, HPA
│   ├── backend/                # Deployment, Service, HPA, ConfigMap
│   ├── redis/                  # Deployment, Service
│   ├── ingress/                # ALB Ingress
│   └── monitoring/             # Prometheus + Grafana via Helm values
├── apps/
│   ├── frontend/               # React app + Nginx Dockerfile
│   └── backend/                # Node.js API + Dockerfile
├── monitoring/
│   ├── prometheus/values.yaml  # Helm chart overrides
│   └── grafana/dashboards/     # Custom dashboard JSON
├── .github/workflows/
│   └── deploy.yml              # Full CI/CD pipeline
└── docs/
    ├── architecture.md         # Deep-dive architecture notes
    ├── troubleshooting.md      # Common issues and fixes
    └── cost-breakdown.md       # AWS cost analysis
```

---

## 🚀 Prerequisites

| Tool | Version | Purpose |
| ---- | ------- | ------- |
| AWS CLI | ≥ 2.x | AWS authentication |
| Terraform | ≥ 1.6 | Infrastructure provisioning |
| kubectl | ≥ 1.28 | Kubernetes management |
| Helm | ≥ 3.12 | Kubernetes package manager |
| Docker | ≥ 24.x | Building container images |

```bash
# Verify all tools
aws --version
terraform --version
kubectl version --client
helm version
docker --version
```

---

## 🛠️ Step-by-Step Deployment

### Step 1: AWS Authentication & Configuration

```bash
# Configure AWS CLI with your credentials
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json

# Verify authentication
aws sts get-caller-identity
```

### Step 2: Clone & Configure

```bash
git clone https://github.com/YOUR_USERNAME/ecommerce-eks.git
cd ecommerce-eks

# Copy and edit Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
nano terraform/terraform.tfvars
```

Edit the following required values in `terraform.tfvars`:

```hcl
aws_region       = "eu-west-2"
project_name     = "ecommerce"
environment      = "prod"
db_password      = "YourSecurePassword123!"   # Change this!
alert_email      = "you@youremail.com"
```

### Step 3: Provision AWS Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform (downloads providers)
terraform init

# Preview all resources to be created (~45 resources)
terraform plan -out=tfplan

# Apply infrastructure (~15-20 minutes for EKS)
terraform apply tfplan
```

**Resources created:**

- VPC with 3 public + 3 private subnets across 3 AZs
- EKS cluster (Kubernetes 1.29) with managed node group
- RDS MySQL 8.0 Multi-AZ instance
- S3 bucket for product images
- ECR repositories (frontend + backend)
- IAM roles with IRSA (IAM Roles for Service Accounts)
- CloudWatch log groups

### Step 4: Configure kubectl

```bash
# Update kubeconfig to point to new EKS cluster
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(terraform output -raw cluster_name)

# Verify cluster connectivity
kubectl get nodes
# Expected: 3 nodes in Ready state
```

### Step 5: Install Cluster Add-ons

```bash
# Install AWS Load Balancer Controller (required for ALB Ingress)
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify the controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Step 6: Build and Push Docker Images

```bash
# Get ECR registry URL from Terraform output
ECR_REGISTRY=$(terraform output -raw ecr_registry_url)
AWS_REGION="eu-west-2"

# Authenticate Docker with ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Build and push frontend
cd ../apps/frontend
docker build -t $ECR_REGISTRY/ecommerce-frontend:latest .
docker push $ECR_REGISTRY/ecommerce-frontend:latest

# Build and push backend
cd ../backend
docker build -t $ECR_REGISTRY/ecommerce-backend:latest .
docker push $ECR_REGISTRY/ecommerce-backend:latest

cd ../../
```

### Step 7: Create Kubernetes Secrets

```bash
# Get RDS endpoint from Terraform
RDS_ENDPOINT=$(cd terraform && terraform output -raw rds_endpoint)
S3_BUCKET=$(cd terraform && terraform output -raw s3_bucket_name)

# Create namespace first
kubectl apply -f kubernetes/namespace.yaml

# Create database secret
kubectl create secret generic db-credentials \
  --namespace=ecommerce \
  --from-literal=host=$RDS_ENDPOINT \
  --from-literal=username=admin \
  --from-literal=password=YourSecurePassword123! \
  --from-literal=database=ecommerce

# Create app secrets (JWT, S3)
kubectl create secret generic app-secrets \
  --namespace=ecommerce \
  --from-literal=jwt_secret=$(openssl rand -base64 32) \
  --from-literal=s3_bucket=$S3_BUCKET
```

### Step 8: Deploy Kubernetes Resources

```bash
# Apply all manifests in order
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/redis/
kubectl apply -f kubernetes/backend/
kubectl apply -f kubernetes/frontend/
kubectl apply -f kubernetes/ingress/

# Watch rollout progress
kubectl rollout status deployment/backend -n ecommerce
kubectl rollout status deployment/frontend -n ecommerce

# Get all running pods
kubectl get pods -n ecommerce
```

### Step 9: Install Monitoring Stack

```bash
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f monitoring/prometheus/values.yaml

# Verify monitoring pods
kubectl get pods -n monitoring

# Get Grafana admin password
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Step 10: Access the Application

```bash
# Get the ALB DNS name (takes ~3 minutes to provision)
kubectl get ingress -n ecommerce
# NAME       CLASS   HOSTS   ADDRESS                               PORTS
# ecommerce  alb     *       k8s-ecommerce-xxx.us-east-1.elb.amazonaws.com   80, 443

# Access Grafana dashboard (port-forward for security)
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Open: http://localhost:3000 (admin / <password from above>)

# Access Prometheus (for debugging)
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090
```

---

## 📊 Monitoring Dashboards

After deploying Grafana, import these dashboards:

| Dashboard | ID | Purpose |
| --------- | -- | ------- |
| Kubernetes Cluster | 7249 | Node CPU, memory, disk |
| Kubernetes Pods | 6417 | Per-pod resource usage |
| Node Exporter | 1860 | Host-level metrics |
| EKS Custom | custom | App-specific metrics |

```bash
# Import dashboard via kubectl
kubectl apply -f monitoring/grafana/dashboards/ecommerce-dashboard.yaml -n monitoring
```

**Key metrics monitored:**

- HTTP request rate and error rate (RED method)
- Pod CPU/Memory utilization (triggers HPA)
- RDS connection count and query latency
- Redis hit/miss ratio
- ALB request count and target response time

---

## 🔄 CI/CD Pipeline

The GitHub Actions pipeline (`.github/workflows/deploy.yml`) triggers on push to `main`:

```
Push to main
     │
     ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Test     │──► │    Build    │──► │    Push     │──► │   Deploy    │
│  (Jest +   │    │   Docker   │    │  to ECR    │    │  to EKS    │
│  Pytest)   │    │   Images   │    │            │    │            │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

**Required GitHub Secrets:**

```text
AWS_ACCESS_KEY_ID       - CI/CD IAM user access key
AWS_SECRET_ACCESS_KEY   - CI/CD IAM user secret
AWS_REGION              - us-east-1
EKS_CLUSTER_NAME        - ecommerce-prod
ECR_REGISTRY            - <account>.dkr.ecr.us-east-1.amazonaws.com
```

---

## ⚖️ Autoscaling Configuration

### Horizontal Pod Autoscaler (HPA)

```yaml
# Backend HPA: scales 2–10 pods based on CPU/Memory
Target CPU:    70%   → adds pods when average CPU exceeds 70%
Target Memory: 80%   → adds pods when average Memory exceeds 80%
Min Replicas:  2     → always 2 pods for HA
Max Replicas:  10    → cost cap

# Frontend HPA: scales 2–6 pods
Target CPU:    60%
Min Replicas:  2
Max Replicas:  6
```

### EKS Node Group Auto Scaling

```
Min nodes:  2
Max nodes:  6
Desired:    3
Instance:   t3.medium (2 vCPU, 4GB RAM)
```

---

## 💰 Cost Breakdown (~$85–110/month)

| Resource | Type | Cost/Month |
|----------|------|-----------|
| EKS Cluster | Control plane | $72 |
| EC2 Nodes | 3× t3.medium | $30 |
| RDS MySQL | db.t3.micro Multi-AZ | $29 |
| NAT Gateway | 2× (HA) | $65 |
| ALB | 1× Application LB | $18 |
| S3 | 10GB storage + requests | $1 |
| ECR | 2 repos, ~2GB | $0.20 |
| CloudWatch | Logs + metrics | $3 |
| **Total** | | **~$218/mo** |

> 💡 **Cost Optimization for Demo/Portfolio:**
> - Use a **single NAT Gateway** → saves ~$32/mo
> - Scale EKS to **2 nodes** during off-hours → saves ~$10/mo
> - Use `db.t3.micro` Single-AZ for dev → saves ~$14/mo
> - **Estimated demo cost: ~$80–100/month**
> - **Tear down after demo:** `terraform destroy` removes everything

---

## 🧹 Tear Down

```bash
# Remove Kubernetes resources first
kubectl delete namespace ecommerce
kubectl delete namespace monitoring

# Destroy all AWS infrastructure
cd terraform
terraform destroy
# Type 'yes' when prompted

# Verify no resources remain (avoid unexpected charges)
aws eks list-clusters
aws rds describe-db-instances
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"
```

---

## 🔧 Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for detailed fixes. Quick reference:

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| Pods in `Pending` state | Insufficient node capacity | Check `kubectl describe pod <name>`, scale node group |
| ALB not provisioning | LB Controller not running | `kubectl get deploy -n kube-system aws-load-balancer-controller` |
| RDS connection refused | Security group | Verify EKS node SG is in RDS inbound rules |
| HPA shows `<unknown>` for CPU | Metrics server missing | `helm install metrics-server metrics-server/metrics-server -n kube-system` |
| ImagePullBackOff | ECR auth expired | Re-run `aws ecr get-login-password` |
| `terraform apply` fails on EKS | IAM permissions | Ensure your IAM user has `AmazonEKSClusterPolicy` |

---

## 📚 Architecture Deep Dive

See [`docs/architecture.md`](docs/architecture.md) for:
- Networking design (VPC CIDR, subnet layout)
- IAM trust relationships and IRSA explanation
- Why Redis is in-cluster vs ElastiCache
- RDS Multi-AZ failover behavior
- Security hardening decisions

---

## 🙋 Author

Built as a cloud engineering portfolio project demonstrating production-level AWS + Kubernetes skills.

**Skills demonstrated:** Terraform IaC · Amazon EKS · RDS Multi-AZ · S3 · IAM/IRSA · Kubernetes (Deployments/HPA/Ingress) · Prometheus/Grafana · GitHub Actions CI/CD · Docker · AWS Load Balancer Controller
