terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote State
  backend "s3" {
    bucket  = "ecommerce-eks-tfstate-919399847940"
    key     = "prod/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
    #dynamodb_table = "ecommerce-eks-tflock"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Benny Maliti"
    }
  }
}

# Kubernetes provider - reads EKS Cluster Credentials
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
# ── Security Group Rules (manual fixes made permanent) ────────────────────────

# Allow ALB to reach frontend pods (port 8080) on cluster SG
resource "aws_security_group_rule" "cluster_sg_allow_alb_frontend" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = "sg-0598632e54e139ea6"
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow ALB to reach frontend pods"
}

# Allow ALB to reach backend pods (port 3000) on cluster SG
resource "aws_security_group_rule" "cluster_sg_allow_alb_backend" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = "sg-0598632e54e139ea6"
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow ALB to reach backend pods"
}

# Allow EKS cluster SG to reach RDS
resource "aws_security_group_rule" "rds_allow_cluster_sg" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = "sg-0598632e54e139ea6"
  description              = "Allow EKS cluster SG to reach RDS"
}
