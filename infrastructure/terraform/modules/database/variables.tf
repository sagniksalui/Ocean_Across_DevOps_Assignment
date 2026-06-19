variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must start with a letter and contain at most 63 letters, numbers, or underscores."
  }
}

variable "db_instance_class" {
  description = "RDS instance class used by PostgreSQL."
  type        = string

  validation {
    condition     = var.db_instance_class == "db.t3.micro"
    error_message = "This assignment requires db.t3.micro."
  }
}

variable "engine_version" {
  description = "PostgreSQL major or minor engine version."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be a PostgreSQL major or major.minor version."
  }
}

variable "master_username" {
  description = "Non-secret PostgreSQL master username; RDS generates the password."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain at most 63 letters, numbers, or underscores."
  }
}

variable "subnet_ids" {
  description = "Private database subnet IDs spanning at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && length(toset(var.subnet_ids)) == length(var.subnet_ids)
    error_message = "Provide at least two unique private database subnet IDs."
  }
}

variable "security_group_id" {
  description = "Dedicated RDS security group that accepts PostgreSQL only from application groups."
  type        = string
}

variable "allocated_storage_gib" {
  description = "General Purpose SSD database storage in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage_gib >= 20 && var.allocated_storage_gib <= 30
    error_message = "allocated_storage_gib must be between 20 and 30 GiB for this assignment."
  }
}

variable "backup_retention_days" {
  description = "Number of days that RDS automated backups are retained."
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Override deletion protection. Null enables it only for production."
  type        = bool
  default     = null
  nullable    = true
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
