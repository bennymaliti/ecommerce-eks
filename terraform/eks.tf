# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster — managed Kubernetes control plane + managed node group
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    security_group_ids      = [aws_security_group.eks_nodes.id]
    endpoint_private_access = true          # Nodes talk to API server internally
    endpoint_public_access  = true          # Allow kubectl from dev machine
    public_access_cidrs     = ["0.0.0.0/0"] # Restrict to your IP in prod!
  }

  # Enable control plane logging to CloudWatch
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Enable OIDC for IRSA (IAM Roles for Service Accounts)
  # This lets pods assume IAM roles without storing credentials in secrets
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# CloudWatch log group for EKS control plane logs
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-${var.environment}/cluster"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-eks-logs"
  }
}

# ── OIDC Identity Provider — required for IRSA ───────────
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-oidc"
  }
}

# ── Managed Node Group ───────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  # Place nodes in private subnets — they're not directly internet accessible
  subnet_ids = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND" # Switch to "SPOT" for significant cost savings in dev

  scaling_config {
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
    desired_size = var.node_group_desired_size
  }

  # Rolling update strategy — ensures zero-downtime node upgrades
  update_config {
    max_unavailable = 1
  }

  # Use latest EKS-optimized AMI
  ami_type = "AL2_x86_64"

  # Node labels for workload scheduling (e.g., node selectors)
  labels = {
    Environment = var.environment
    NodeGroup   = "main"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-node"
    # Required for Cluster Autoscaler to discover this node group
    "k8s.io/cluster-autoscaler/enabled"                                = "true"
    "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}" = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # Let autoscaler manage this
  }
}

# ── EKS Add-ons — managed by AWS ─────────────────────────
# CoreDNS: in-cluster DNS resolution
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.4"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

# kube-proxy: network routing on each node
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.29.1-eksbuild.2"
  resolve_conflicts_on_update = "OVERWRITE"
}

# VPC CNI: AWS networking for pods (assigns VPC IPs to pods)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.16.2-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
}

# EBS CSI Driver: required for PersistentVolumeClaims backed by EBS
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.28.0-eksbuild.1"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}
