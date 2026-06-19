variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain noncurrent S3 object versions."
  type        = number

  validation {
    condition     = var.noncurrent_version_retention_days >= 30
    error_message = "Retain noncurrent payroll document versions for at least 30 days."
  }
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
