output "ingress_security_group_id" {
  description = "Security group ID reserved for a future HTTPS load balancer."
  value       = aws_security_group.ingress.id
}

output "portal_security_group_ids" {
  description = "Application security group ID keyed by portal."
  value = {
    for portal, security_group in aws_security_group.portal : portal => security_group.id
  }
}

output "rds_security_group_id" {
  description = "Security group ID that permits PostgreSQL only from portal groups."
  value       = aws_security_group.rds.id
}

output "portal_network_acl_ids" {
  description = "Application network ACL ID keyed by portal."
  value = {
    for portal, network_acl in aws_network_acl.portal : portal => network_acl.id
  }
}

output "database_network_acl_id" {
  description = "Network ACL ID associated with private database subnets."
  value       = aws_network_acl.database.id
}
