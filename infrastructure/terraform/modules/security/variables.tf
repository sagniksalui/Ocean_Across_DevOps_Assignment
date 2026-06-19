variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC that receives security groups and NACLs."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR assigned to the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the ingress tier."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "Private application subnet CIDR assigned to each portal."
  type        = map(string)
}

variable "private_db_subnet_cidrs" {
  description = "Private database subnet CIDRs."
  type        = list(string)
}

variable "application_subnet_ids" {
  description = "Private application subnet ID keyed by portal."
  type        = map(string)
}

variable "database_subnet_ids" {
  description = "Private database subnet IDs associated with the database NACL."
  type        = list(string)
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

variable "ephemeral_port_start" {
  description = "Start of the operating system ephemeral port range used in stateless NACL return rules."
  type        = number
  default     = 1024
}

variable "ephemeral_port_end" {
  description = "End of the operating system ephemeral port range used in stateless NACL return rules."
  type        = number
  default     = 65535
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
