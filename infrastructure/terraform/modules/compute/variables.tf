variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "instance_types" {
  description = "EC2 instance type selected for each portal."
  type        = map(string)

  validation {
    condition = alltrue([
      for instance_type in values(var.instance_types) :
      contains(["t2.micro", "t3.micro"], instance_type)
    ])
    error_message = "Portal instances must use only t2.micro or t3.micro."
  }
}

variable "subnet_ids" {
  description = "Private application subnet ID keyed by portal."
  type        = map(string)
}

variable "security_group_ids" {
  description = "Application security group ID keyed by portal."
  type        = map(string)
}

variable "instance_profile_names" {
  description = "IAM instance profile name keyed by portal."
  type        = map(string)
}

variable "ami_id" {
  description = "Optional pinned Amazon Linux-compatible AMI ID. Null selects the latest Amazon Linux 2023 AMI."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-fA-F]+$", var.ami_id))
    error_message = "ami_id must be null or a valid AMI ID."
  }
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root volume size in GiB."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size_gib >= 8 && var.root_volume_size_gib <= 30
    error_message = "root_volume_size_gib must be between 8 and 30 GiB for this assignment."
  }
}

variable "owner" {
  description = "Team responsible for the EC2 instances."
  type        = string
  default     = "PlatformEngineering"
}

variable "common_tags" {
  description = "Tags applied to module resources."
  type        = map(string)
}
