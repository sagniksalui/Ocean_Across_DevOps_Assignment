locals {
  deletion_protection_enabled = (
    var.deletion_protection != null ?
    var.deletion_protection :
    var.environment == "production"
  )
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
}

# The subnet group contains only database-tier private subnets. RDS therefore
# has no route to an internet gateway even if another resource is misconfigured.
resource "aws_db_subnet_group" "primary" {
  name       = "${var.environment}-payroll-postgresql"
  subnet_ids = var.subnet_ids

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-payroll-postgresql-subnets"
    Purpose = "Database"
  })
}

# Require TLS for every PostgreSQL connection. Storage encryption separately
# protects database files, automated backups, and snapshots at rest.
resource "aws_db_parameter_group" "primary" {
  name   = "${var.environment}-payroll-${local.parameter_group_family}"
  family = local.parameter_group_family

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-payroll-${local.parameter_group_family}"
    Purpose = "EnforcePostgreSQLTLS"
  })
}

# RDS generates the master password and stores it in Secrets Manager. Terraform
# never receives a plaintext password and outputs only the managed secret ARN.
resource "aws_db_instance" "primary" {
  identifier = "${var.environment}-payroll-postgresql"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.db_instance_class
  db_name        = var.db_name
  username       = var.master_username
  port           = 5432

  manage_master_user_password = true

  allocated_storage     = var.allocated_storage_gib
  storage_type          = "gp2"
  storage_encrypted     = true
  max_allocated_storage = 0

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  parameter_group_name   = aws_db_parameter_group.primary.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = var.backup_retention_days
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = false

  deletion_protection       = local.deletion_protection_enabled
  skip_final_snapshot       = !local.deletion_protection_enabled
  final_snapshot_identifier = local.deletion_protection_enabled ? "${var.environment}-payroll-postgresql-final" : null

  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-payroll-postgresql"
    Purpose = "PrimaryPayrollDatabase"
  })

  lifecycle {
    # Public exposure must remain impossible even if a caller changes defaults.
    precondition {
      condition     = var.security_group_id != ""
      error_message = "A dedicated RDS security group ID is required."
    }
  }
}
