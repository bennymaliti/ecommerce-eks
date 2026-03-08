# ─────────────────────────────────────────────────────────────────────────────
# S3 Bucket — product images and static assets
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "images" {
  bucket        = "${var.project_name}-${var.environment}-images-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name = "${var.project_name}-images-bucket"
  }
}

# Block all public access — images served via CloudFront, not directly
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning (allows rollback of accidentally overwritten images)
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt all objects with AWS-managed keys
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: move old image versions to cheaper storage
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    filter {}


    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# CORS configuration for direct browser uploads
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"] # Restrict to your domain in production
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ECR Repositories — store Docker images for frontend and backend
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}-frontend"
  image_tag_mutability = "MUTABLE" # Allows overwriting :latest tag

  image_scanning_configuration {
    scan_on_push = true # Automatic vulnerability scanning on push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-frontend-ecr"
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-backend-ecr"
  }
}

# Lifecycle policy — keep only last 10 untagged images to control storage costs
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 untagged images"
      selection = {
        tagStatus   = "untagged"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 untagged images"
      selection = {
        tagStatus   = "untagged"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
