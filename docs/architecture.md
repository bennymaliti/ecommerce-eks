# Architecture Deep Dive

## Why These Design Choices?

This document explains the architectural decisions made in this project and the trade-offs considered.

---

## Networking Design

### VPC CIDR Layout

```
VPC: 10.0.0.0/16 (65,536 IPs)

Public Subnets (ALB, NAT Gateways):
  10.0.1.0/24  — us-east-1a  (254 IPs)
  10.0.2.0/24  — us-east-1b  (254 IPs)
  10.0.3.0/24  — us-east-1c  (254 IPs)

Private Subnets (EKS nodes, RDS):
  10.0.11.0/24 — us-east-1a  (254 IPs)
  10.0.12.0/24 — us-east-1b  (254 IPs)
  10.0.13.0/24 — us-east-1c  (254 IPs)
```

**Why separate public/private subnets?** EKS nodes and RDS should never have direct internet access. They communicate outbound via NAT Gateway. The ALB sits in public subnets and routes inbound traffic to pods in private subnets. This is the standard AWS security pattern.

**Why 3 NAT Gateways?** One per AZ ensures that if one AZ's NAT Gateway fails, nodes in the other AZs can still reach the internet (for ECR image pulls, etc.). Using a single NAT Gateway saves ~$32/month but creates an AZ-level single point of failure.

---

## IAM Design — IRSA (IAM Roles for Service Accounts)

IRSA allows Kubernetes pods to assume IAM roles without any stored credentials.

**How it works:**
1. EKS cluster has an OIDC Identity Provider
2. A ServiceAccount is annotated with an IAM role ARN
3. When a pod starts, the EKS Pod Identity Webhook injects AWS credential environment variables
4. The pod exchanges its Kubernetes service account token for temporary AWS credentials via STS

**Why not use EC2 instance profiles?** Instance profiles give ALL pods on a node the same permissions. IRSA gives each service account its own minimal permissions (principle of least privilege). The backend only needs S3 access — it shouldn't have RDS IAM auth, CloudWatch, or anything else.

---

## Why Redis In-Cluster vs ElastiCache?

**This project uses in-cluster Redis.** For a portfolio project, this:
- Saves ~$25/month (ElastiCache.cache.t3.micro costs ~$25/mo)
- Keeps the architecture self-contained and easier to demo
- Is still realistic — many companies run Redis in Kubernetes

**In production you would use ElastiCache because:**
- Managed failover and replication
- Automated backups
- Performance Insights
- No pod scheduling dependency
- Multi-AZ Redis clusters

---

## RDS Multi-AZ Failover

When Multi-AZ is enabled, AWS maintains a synchronous standby replica in a different AZ:

```
Primary (us-east-1a) ──sync replication──► Standby (us-east-1b)
         │
         ▼ (on failure)
Standby promoted to Primary (~60-120 seconds)
DNS updated automatically
Application reconnects via connection pool
```

The connection string uses the RDS endpoint DNS name (not an IP), so failover is transparent to the application. The `mysql2` connection pool in the backend handles reconnections automatically.

---

## HPA Scaling Logic

```
Scale Out triggers:
  Average CPU across all pods > 70%   OR
  Average Memory across all pods > 80%

Scale Out behavior:
  Add up to 2 pods, then wait 60 seconds before adding more
  (avoids rapid thrashing during traffic spikes)

Scale In triggers:
  CPU drops below 70% AND Memory below 80%

Scale In behavior:
  Wait 5 minutes before removing pods
  Remove at most 1 pod at a time
  Never go below 2 pods (minReplicas)
```

**Why CPU at 70%?** Leaving headroom allows pods to handle traffic bursts while new pods are initializing. At 70%, a new pod can be ready before the existing pods are overwhelmed.

---

## Security Decisions

| Decision | Rationale |
|----------|-----------|
| `endpoint_public_access = true` | Allows `kubectl` from developer machines. Restrict `public_access_cidrs` to your office IP in production. |
| `deletion_protection = true` on RDS | Prevents accidental `terraform destroy` from deleting your database. Must be manually disabled first. |
| Secrets stored in K8s Secrets | Secrets are base64-encoded, not encrypted at rest by default. Enable EKS secrets encryption with a KMS key for production. |
| `runAsNonRoot: true` on pods | Containers run as UID 1000, reducing blast radius of container escape vulnerabilities. |
| ECR `scan_on_push = true` | Automatically scans images for CVEs on push. Review findings in ECR console. |

---

## CI/CD Pipeline Design

```
Developer pushes to main branch
         │
         ▼
Test job (Jest + coverage)
  - Fails fast: blocks deploy if tests fail
  - Coverage report saved as artifact
         │
         ▼
Build job (only on main, not PRs)
  - Uses Docker Buildx with layer caching
  - Pushes two tags: :latest AND :<short-sha>
  - Short SHA enables rollback: kubectl set image ... backend:abc1234
         │
         ▼
Deploy job (with GitHub Environment protection rules)
  - Can require manual approval in GitHub UI
  - Rolling update (maxUnavailable: 0) = zero downtime
  - Smoke test polls /api/health for 60s
  - Posts summary to GitHub workflow summary
```

**Why tag with git SHA?** It makes images traceable. If you deploy :latest and something breaks, you can rollback to the previous SHA immediately without rebuilding.
