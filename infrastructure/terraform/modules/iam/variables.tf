variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "aws_region" {
  description = "AWS region used to scope CloudWatch Logs and Parameter Store ARNs."
  type        = string
}

variable "portals" {
  description = "Portal names requiring isolated IAM roles."
  type        = list(string)
}

variable "documents_bucket_name" {
  description = "Name of the private payroll document bucket."
  type        = string
}

variable "documents_bucket_arn" {
  description = "ARN of the private payroll document bucket."
  type        = string
}

variable "portal_prefixes" {
  description = "S3 document prefix keyed by portal."
  type        = map(string)
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
