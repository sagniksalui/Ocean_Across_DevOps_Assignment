output "configuration_summary" {
  description = "Non-sensitive summary of the selected Terraform configuration."
  value = {
    region      = var.aws_region
    environment = var.environment
    portals     = local.portal_names
    database    = var.db_name
  }
}

output "vpc_id" {
  description = "ID of the payroll VPC."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public ingress-placeholder subnets."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of all private application and database subnets."
  value       = module.networking.private_subnet_ids
}

output "application_private_subnet_ids" {
  description = "Private application subnet ID keyed by portal."
  value       = module.networking.application_private_subnet_ids
}

output "database_private_subnet_ids" {
  description = "IDs of private database subnets."
  value       = module.networking.database_private_subnet_ids
}

output "network_cidr_blocks" {
  description = "Configured CIDR blocks for each network tier."
  value       = module.networking.cidr_blocks
}

output "portal_security_group_ids" {
  description = "Application security group ID keyed by portal."
  value       = module.security.portal_security_group_ids
}

output "rds_security_group_id" {
  description = "Security group ID for private PostgreSQL."
  value       = module.security.rds_security_group_id
}

output "portal_network_acl_ids" {
  description = "Application network ACL ID keyed by portal."
  value       = module.security.portal_network_acl_ids
}

output "database_network_acl_id" {
  description = "Network ACL ID for private database subnets."
  value       = module.security.database_network_acl_id
}

output "portal_instance_ids" {
  description = "EC2 instance ID keyed by portal."
  value       = module.compute.instance_ids
}

output "portal_private_ips" {
  description = "Private EC2 address keyed by portal."
  value       = module.compute.private_ips
}

output "portal_instance_profile_names" {
  description = "IAM instance profile name keyed by portal."
  value       = module.iam.portal_instance_profile_names
}

output "deployment_document_arn" {
  description = "ARN of the account-owned, parameter-validated SSM deployment document."
  value       = module.iam.deployment_document_arn
}

output "deployment_document_name" {
  description = "Name of the account-owned SSM deployment document."
  value       = module.iam.deployment_document_name
}

output "monitoring_alarm_names" {
  description = "Names of all EC2 and RDS CloudWatch alarms."
  value       = module.monitoring.alarm_names
}

output "portal_cpu_alarm_names" {
  description = "EC2 high-CPU CloudWatch alarm name keyed by portal."
  value       = module.monitoring.ec2_cpu_alarm_names
}

output "rds_database_connections_alarm_name" {
  description = "Name of the RDS high-database-connections CloudWatch alarm."
  value       = module.monitoring.rds_database_connections_alarm_name
}

output "critical_alerts_sns_topic_arn" {
  description = "ARN of the non-sensitive operational alert topic."
  value       = module.monitoring.sns_topic_arn
}

output "portal_log_group_names" {
  description = "CloudWatch application log group name keyed by portal."
  value       = module.monitoring.portal_log_group_names
}

output "infrastructure_log_group_names" {
  description = "CloudWatch infrastructure log group name keyed by portal."
  value       = module.monitoring.infrastructure_log_group_names
}

output "rds_instance_id" {
  description = "RDS PostgreSQL instance identifier."
  value       = module.database.instance_id
}

output "rds_endpoint" {
  description = "Private PostgreSQL hostname without credentials."
  value       = module.database.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "PostgreSQL listener port."
  value       = module.database.port
}

output "rds_master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret."
  value       = module.database.master_user_secret_arn
  sensitive   = true
}

output "rds_deletion_protection_enabled" {
  description = "Effective RDS deletion protection setting."
  value       = module.database.deletion_protection_enabled
}

output "payroll_documents_bucket_name" {
  description = "Name of the private payroll documents and reports bucket."
  value       = module.storage.bucket_name
}

output "payroll_documents_bucket_arn" {
  description = "ARN of the private payroll documents and reports bucket."
  value       = module.storage.bucket_arn
}

output "payroll_documents_portal_prefixes" {
  description = "Portal prefixes protected by role-specific IAM and bucket policies."
  value       = module.storage.portal_prefixes
}
