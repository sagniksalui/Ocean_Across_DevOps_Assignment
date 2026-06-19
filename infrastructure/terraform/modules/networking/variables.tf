variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR assigned to the VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the ingress tier."
  type        = list(string)

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

  validation {
    condition = (
      length(var.private_db_subnet_cidrs) >= 2 &&
      length(toset(var.private_db_subnet_cidrs)) == length(var.private_db_subnet_cidrs) &&
      alltrue([for cidr in var.private_db_subnet_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "Provide at least two unique, valid private database subnet CIDRs."
  }
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
