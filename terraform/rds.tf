# ─────────────────────────────────────────────────────────────────────────────
# RDS MySQL 8.0 — Multi-AZ for automatic failover
# Placed in private subnets, accessible only from EKS nodes
# ─────────────────────────────────────────────────────────────────────────────

# Subnet group — RDS must span at least 2 AZs for Multi-AZ
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet"
  description = "Private subnets for RDS across 3 AZs"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Parameter group — tune MySQL for container workloads
resource "aws_db_parameter_group" "mysql" {
  name        = "${var.project_name}-${var.environment}-mysql-params"
  family      = "mysql8.0"
  description = "Custom MySQL 8.0 parameters for ${var.project_name}"

  # Increase max connections for connection pooling from multiple pods
  parameter {
    name  = "max_connections"
    value = "200"
  }

  # Enable slow query log (write to CloudWatch)
  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  # UTF8MB4 for full Unicode (emoji support)
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "${var.project_name}-mysql-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-mysql"

  # Engine
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage — GP3 is more cost-effective than GP2
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100 # Enable storage autoscaling up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true # Encrypt at rest (compliance)

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Never expose RDS publicly

  # High Availability
  multi_az = var.db_multi_az # Standby replica in different AZ

  # Performance
  parameter_group_name = aws_db_parameter_group.mysql.name

  # Backups — 7-day retention, daily window
  backup_retention_period  = 7
  backup_window            = "03:00-04:00" # UTC low-traffic window
  maintenance_window       = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  # Monitoring
  enabled_cloudwatch_logs_exports = ["error", "slowquery", "general"]
  monitoring_interval             = 60 # Enhanced monitoring every 60s
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = false # Disable to save costs; enable in prod if needed
  #performance_insights_retention_period = 7     # Free tier: 7 days

  # Lifecycle
  deletion_protection       = true # Prevent accidental deletion
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-final-snapshot"

  apply_immediately = false # Apply changes during maintenance window in prod

  tags = {
    Name = "${var.project_name}-${var.environment}-rds"
  }
}

# ── CloudWatch Alarms for RDS ─────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization > 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.project_name}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5GB in bytes
  alarm_description   = "RDS free storage < 5GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

# ── SNS Topic for alerts ─────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
