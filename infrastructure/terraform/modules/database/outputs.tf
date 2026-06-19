output "instance_id" {
  description = "RDS database instance identifier."
  value       = aws_db_instance.primary.id
}

output "endpoint" {
  description = "Private PostgreSQL hostname without credentials."
  value       = aws_db_instance.primary.address
  sensitive   = true
}

output "port" {
  description = "PostgreSQL listener port."
  value       = aws_db_instance.primary.port
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret; never the secret value."
  value       = aws_db_instance.primary.master_user_secret[0].secret_arn
  sensitive   = true
}

output "deletion_protection_enabled" {
  description = "Effective deletion protection setting."
  value       = aws_db_instance.primary.deletion_protection
}
