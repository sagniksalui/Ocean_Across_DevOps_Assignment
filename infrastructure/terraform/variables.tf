variable "aws_region" {
  description = "AWS region in which all regional resources will be created."
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Deployment environment name used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR assigned to the payroll VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for a future load balancer or access tier."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]

  validation {
    condition = (
      length(var.public_subnet_cidrs) >= 2 &&
      length(toset(var.public_subnet_cidrs)) == length(var.public_subnet_cidrs) &&
      alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "Provide at least two unique, valid public subnet CIDRs."
  }
}

variable "private_app_subnet_cidrs" {
  description = "Private application subnet CIDR assigned to each portal."
  type        = map(string)
  default = {
    companies = "10.20.20.0/24"
    bureaus   = "10.20.21.0/24"
    employees = "10.20.22.0/24"
  }

  validation {
    condition = (
      alltrue([
        for portal in ["companies", "bureaus", "employees"] :
        contains(keys(var.private_app_subnet_cidrs), portal)
      ]) &&
      length(toset(values(var.private_app_subnet_cidrs))) == length(var.private_app_subnet_cidrs) &&
      alltrue([for cidr in values(var.private_app_subnet_cidrs) : can(cidrnetmask(cidr))])
    )
    error_message = "Provide a unique, valid private application CIDR for each portal."
  }
}

variable "private_db_subnet_cidrs" {
  description = "Private database subnet CIDRs used by the RDS subnet group."
  type        = list(string)
  default     = ["10.20.100.0/24", "10.20.101.0/24"]

  validation {
    condition = (
      length(var.private_db_subnet_cidrs) >= 2 &&
      length(toset(var.private_db_subnet_cidrs)) == length(var.private_db_subnet_cidrs) &&
      alltrue([for cidr in var.private_db_subnet_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "Provide at least two unique, valid private database subnet CIDRs."
  }
}

variable "instance_types" {
  description = "EC2 instance type selected for each portal."
  type        = map(string)
  default = {
    companies = "t3.micro"
    bureaus   = "t3.micro"
    employees = "t3.micro"
  }

  validation {
    condition = (
      alltrue([
        for portal in ["companies", "bureaus", "employees"] :
        contains(keys(var.instance_types), portal)
      ]) &&
      alltrue([
        for instance_type in values(var.instance_types) :
        contains(["t2.micro", "t3.micro"], instance_type)
      ])
    )
    error_message = "Define companies, bureaus, and employees using only t2.micro or t3.micro."
  }
}

variable "ec2_ami_id" {
  description = "Optional pinned Amazon Linux-compatible AMI ID. Null selects the latest Amazon Linux 2023 AMI."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ec2_ami_id == null || can(regex("^ami-[0-9a-fA-F]+$", var.ec2_ami_id))
    error_message = "ec2_ami_id must be null or a valid AMI ID."
  }
}

variable "resource_owner" {
  description = "Team recorded as the owner of application compute resources."
  type        = string
  default     = "PlatformEngineering"
}

variable "application_port" {
  description = "TLS application port exposed to the future ingress boundary."
  type        = number
  default     = 443

  validation {
    condition     = var.application_port >= 1 && var.application_port <= 65535
    error_message = "application_port must be between 1 and 65535."
  }
}

variable "https_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to reach a future HTTPS load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.https_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every HTTPS ingress entry must be a valid IPv4 CIDR."
  }
}

variable "ssh_allowed_cidr" {
  description = "Optional routed VPN or bastion IPv4 CIDR for SSH. Null disables SSH."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.ssh_allowed_cidr == null ||
      (can(cidrnetmask(var.ssh_allowed_cidr)) && var.ssh_allowed_cidr != "0.0.0.0/0")
    )
    error_message = "SSH must be disabled with null or restricted to a valid CIDR other than 0.0.0.0/0."
  }
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "payroll"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]*$", var.db_name))
    error_message = "db_name must begin with a letter and contain only letters, numbers, or underscores."
  }
}

variable "db_instance_class" {
  description = "RDS instance class used by PostgreSQL."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = var.db_instance_class == "db.t3.micro"
    error_message = "This assignment requires db.t3.micro."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL major or minor engine version."
  type        = string
  default     = "16"
}

variable "db_master_username" {
  description = "Non-secret PostgreSQL master username; RDS generates the password in Secrets Manager."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_master_username))
    error_message = "db_master_username must start with a letter and contain at most 63 letters, numbers, or underscores."
  }
}

variable "db_backup_retention_days" {
  description = "Number of days that RDS automated backups are retained."
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "RDS backup retention must be between 1 and 35 days."
  }
}

variable "rds_deletion_protection" {
  description = "Override RDS deletion protection. Null enables it for production and disables it elsewhere."
  type        = bool
  default     = null
  nullable    = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days."
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be a retention period supported by CloudWatch Logs."
  }
}

variable "ec2_cpu_threshold_percent" {
  description = "Average EC2 CPU percentage that triggers a critical CloudWatch alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.ec2_cpu_threshold_percent > 0 && var.ec2_cpu_threshold_percent <= 100
    error_message = "ec2_cpu_threshold_percent must be greater than 0 and no more than 100."
  }
}

variable "rds_connection_threshold" {
  description = "Average RDS database connection count that triggers a critical CloudWatch alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.rds_connection_threshold > 0
    error_message = "rds_connection_threshold must be greater than zero."
  }
}

variable "alert_email" {
  description = "Optional email address for critical SNS alerts. Null disables the email subscription."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.alert_email == null ||
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    )
    error_message = "alert_email must be null or a syntactically valid email address."
  }
}

variable "s3_noncurrent_version_retention_days" {
  description = "Days to retain noncurrent S3 object versions before expiration."
  type        = number
  default     = 90

  validation {
    condition     = var.s3_noncurrent_version_retention_days > 0
    error_message = "S3 noncurrent version retention must be greater than zero days."
  }
}
