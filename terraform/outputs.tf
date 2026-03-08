output "cluster_name" {
  description = "EKS cluster name — used in kubectl and CI/CD config"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL — used for IRSA configuration"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "node_group_arn" {
  description = "EKS managed node group ARN"
  value       = aws_eks_node_group.main.arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint — use in Kubernetes secrets"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "s3_bucket_name" {
  description = "S3 bucket name for product images"
  value       = aws_s3_bucket.images.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.images.arn
}

output "ecr_registry_url" {
  description = "ECR registry URL (without repo name) — for Docker login"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_url" {
  description = "ECR repository URL for backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "backend_irsa_role_arn" {
  description = "IAM role ARN for backend service account (IRSA)"
  value       = aws_iam_role.backend.arn
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.lb_controller.arn
}

output "cicd_access_key_id" {
  description = "Access key ID for CI/CD user — add to GitHub Secrets"
  value       = aws_iam_access_key.cicd.id
  sensitive   = true
}

output "cicd_secret_access_key" {
  description = "Secret access key for CI/CD user — add to GitHub Secrets"
  value       = aws_iam_access_key.cicd.secret
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes, RDS)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT gateways)"
  value       = aws_subnet.public[*].id
}

output "sns_alert_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

# Helper commands output
output "configure_kubectl_command" {
  description = "Run this command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "ecr_login_command" {
  description = "Run this command to authenticate Docker with ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
