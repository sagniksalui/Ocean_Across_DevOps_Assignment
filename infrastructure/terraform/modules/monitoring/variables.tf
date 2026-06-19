variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "portals" {
  description = "Portal names requiring separate monitoring resources."
  type        = list(string)

  validation {
    condition = (
      length(var.portals) == 3 &&
      length(toset(var.portals)) == 3 &&
      alltrue([
        for portal in ["companies", "bureaus", "employees"] :
        contains(var.portals, portal)
      ])
    )
    error_message = "Portals must contain companies, bureaus, and employees exactly once."
  }
}

variable "portal_instance_ids" {
  description = "EC2 instance ID keyed by portal name."
  type        = map(string)

  validation {
    condition = alltrue([
      for instance_id in values(var.portal_instance_ids) :
      can(regex("^i-[0-9a-fA-F]{8}([0-9a-fA-F]{9})?$", instance_id))
    ])
    error_message = "Every portal_instance_ids value must be a valid EC2 instance ID."
  }
}

variable "rds_instance_id" {
  description = "RDS DB instance identifier used for CloudWatch metric dimensions."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.rds_instance_id))
    error_message = "rds_instance_id must be a valid lowercase RDS DB instance identifier."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days."
  type        = number

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653,
    ], var.log_retention_days)
    error_message = "log_retention_days must be a retention period supported by CloudWatch Logs."
  }
}

variable "ec2_cpu_threshold_percent" {
  description = "Average EC2 CPU percentage that triggers a critical alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.ec2_cpu_threshold_percent > 0 && var.ec2_cpu_threshold_percent <= 100
    error_message = "ec2_cpu_threshold_percent must be greater than 0 and no more than 100."
  }
}

variable "rds_connection_threshold" {
  description = "Average number of RDS database connections that triggers a critical alarm."
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

variable "sns_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for SNS encryption; its key policy must allow CloudWatch publishing."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.sns_kms_key_arn == null ||
      can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-fA-F-]{36}$", var.sns_kms_key_arn))
    )
    error_message = "sns_kms_key_arn must be null or a customer-managed KMS key ARN."
  }
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
