# 🔧 Troubleshooting Guide

A comprehensive reference for diagnosing and resolving common issues with this EKS deployment.

---

## 🔑 Quick Diagnostic Commands

```bash
# Overall cluster health
kubectl get nodes
kubectl get pods -n ecommerce
kubectl get pods -n monitoring
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | tail -20

# HPA status
kubectl get hpa -n ecommerce
kubectl describe hpa backend-hpa -n ecommerce

# Resource usage
kubectl top nodes
kubectl top pods -n ecommerce

# Ingress / ALB status
kubectl describe ingress ecommerce-ingress -n ecommerce
kubectl get events -n ecommerce | grep ingress
```

---

## 🚨 Issue: Pods stuck in `Pending` state

**Symptoms:** `kubectl get pods -n ecommerce` shows pods with `Pending` status for more than 2 minutes.

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n ecommerce
# Look for "Events" section at the bottom
```

**Common causes:**

| Cause | Event Message | Fix |
|-------|--------------|-----|
| Insufficient CPU/memory | `0/3 nodes are available: 3 Insufficient cpu` | Scale up node group in AWS console or increase max nodes in Terraform |
| Node not ready | `0/3 nodes are available: 3 node(s) had untolerated taint` | Check node status: `kubectl get nodes` |
| PVC not bound | `persistentvolumeclaim "redis-pvc" not found` | Verify EBS CSI driver: `kubectl get pods -n kube-system \| grep ebs` |

**Fix for insufficient capacity:**
```bash
# Check current node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Manually scale node group (temporary)
aws eks update-nodegroup-config \
  --cluster-name ecommerce-prod \
  --nodegroup-name ecommerce-prod-nodes \
  --scaling-config minSize=3,maxSize=6,desiredSize=4
```

---

## 🚨 Issue: `ImagePullBackOff` or `ErrImagePull`

**Symptoms:** Pod keeps restarting, events show image pull errors.

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n ecommerce
# Look for: Failed to pull image ... unauthorized
```

**Fix:**
```bash
# Re-authenticate Docker with ECR (tokens expire after 12 hours)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Verify the image exists in ECR
aws ecr list-images --repository-name ecommerce-backend

# Force pods to re-pull
kubectl rollout restart deployment/backend -n ecommerce
```

---

## 🚨 Issue: ALB not provisioning (Ingress stuck)

**Symptoms:** `kubectl get ingress -n ecommerce` shows no ADDRESS after 5+ minutes.

**Diagnosis:**
```bash
# Check if LB Controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller | tail -30

# Check ingress events
kubectl describe ingress ecommerce-ingress -n ecommerce
```

**Common causes:**

1. **LB Controller not installed or crashing:**
   ```bash
   helm status aws-load-balancer-controller -n kube-system
   # If not found, install it following README Step 5
   ```

2. **IRSA role misconfigured:**
   ```bash
   # Verify service account has correct annotation
   kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o yaml
   # annotation eks.amazonaws.com/role-arn should match terraform output lb_controller_role_arn
   ```

3. **Subnets missing required tags:**
   ```bash
   # Public subnets need: kubernetes.io/role/elb = 1
   aws ec2 describe-subnets --subnet-ids <subnet-id> \
     --query 'Subnets[*].Tags'
   ```

---

## 🚨 Issue: RDS connection refused from pods

**Symptoms:** Backend pods crash with "ECONNREFUSED" or "Access denied" when connecting to MySQL.

**Diagnosis:**
```bash
# Check backend pod logs
kubectl logs deployment/backend -n ecommerce | tail -50

# Test connectivity from a debug pod
kubectl run -it --rm debug \
  --image=mysql:8.0 \
  --namespace=ecommerce \
  --restart=Never \
  -- mysql -h <rds-endpoint> -u admin -p
```

**Common causes:**

1. **Security group not allowing EKS nodes:**
   ```bash
   # Verify RDS SG has inbound rule from EKS node SG
   aws ec2 describe-security-groups \
     --group-ids <rds-sg-id> \
     --query 'SecurityGroups[0].IpPermissions'
   ```

2. **Secret has wrong values:**
   ```bash
   # Decode and check secret
   kubectl get secret db-credentials -n ecommerce \
     -o jsonpath='{.data.host}' | base64 --decode
   ```

3. **RDS not in same VPC:** Verify `aws_db_instance.main.vpc_security_group_ids` matches.

---

## 🚨 Issue: HPA shows `<unknown>` for metrics

**Symptoms:** `kubectl get hpa -n ecommerce` shows `<unknown>/70%` for CPU.

**Cause:** Metrics Server not installed.

**Fix:**
```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set args="{--kubelet-insecure-tls}"

# Wait for metrics-server to start
kubectl rollout status deployment/metrics-server -n kube-system

# Verify it works
kubectl top pods -n ecommerce
```

---

## 🚨 Issue: Terraform state lock error

**Symptoms:** `terraform apply` fails with "Error locking state: Error acquiring the state lock".

**Fix:**
```bash
# Find the lock ID from the error message, then force-unlock
terraform force-unlock <LOCK_ID>

# If DynamoDB table doesn't exist yet
aws dynamodb create-table \
  --table-name ecommerce-eks-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

## 🚨 Issue: GitHub Actions deployment fails at kubectl step

**Symptoms:** Pipeline fails with "error: the server doesn't have a resource type".

**Diagnosis:** Check if the EKS_CLUSTER_NAME and AWS credentials are correct.

**Fix:**
```bash
# In your GitHub repo: Settings → Secrets → Actions
# Verify these secrets exist:
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, EKS_CLUSTER_NAME, ECR_REGISTRY

# Get the correct values:
cd terraform
terraform output cicd_access_key_id
terraform output cicd_secret_access_key
terraform output cluster_name
terraform output ecr_registry_url
```

Also ensure the CI/CD IAM user has been added to the EKS cluster's `aws-auth` ConfigMap:
```bash
kubectl edit configmap aws-auth -n kube-system
# Add:
# mapUsers:
# - userarn: arn:aws:iam::ACCOUNT:user/ecommerce-prod-cicd
#   username: cicd
#   groups:
#     - system:masters
```

---

## 🚨 Issue: Grafana not showing data

**Symptoms:** Grafana dashboards show "No data" for all panels.

**Fix:**
```bash
# Verify Prometheus is scraping targets
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets — all targets should be "UP"

# Verify data source in Grafana
# Grafana UI → Configuration → Data Sources → Prometheus
# URL should be: http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090

# Check Prometheus can reach pods
kubectl exec -n monitoring deployment/monitoring-grafana -- \
  wget -qO- http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/targets
```

---

## 💰 Unexpected AWS Costs

If you see unexpected charges:

```bash
# List all resources created by this project
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=ecommerce \
  --region us-east-1

# Check for orphaned NAT Gateways (most expensive if left running)
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].{ID:NatGatewayId,State:State}'

# Check for EBS volumes not in use
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,State:State}'
```

To fully tear down and stop all charges:
```bash
kubectl delete namespace ecommerce
kubectl delete namespace monitoring
cd terraform && terraform destroy
```
