output "bucket_name" {
  description = "Name of the private payroll document bucket."
  value       = aws_s3_bucket.documents.id
}

output "bucket_arn" {
  description = "ARN of the private payroll document bucket."
  value       = aws_s3_bucket.documents.arn
}

output "portal_prefixes" {
  description = "Portal prefixes protected by role-specific policies."
  value = {
    for prefix in local.portal_prefixes : prefix => "${prefix}/"
  }
}
