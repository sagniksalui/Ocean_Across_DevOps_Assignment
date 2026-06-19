output "portal_role_arns" {
  description = "EC2 IAM role ARN keyed by portal."
  value = {
    for portal, role in aws_iam_role.portal : portal => role.arn
  }
}

output "portal_role_names" {
  description = "EC2 IAM role name keyed by portal."
  value = {
    for portal, role in aws_iam_role.portal : portal => role.name
  }
}

output "portal_instance_profile_names" {
  description = "EC2 instance profile name keyed by portal."
  value = {
    for portal, profile in aws_iam_instance_profile.portal : portal => profile.name
  }
}

output "deployment_document_arn" {
  description = "ARN of the account-owned, parameter-validated SSM deployment document."
  value       = aws_ssm_document.deploy_container.arn
}

output "deployment_document_name" {
  description = "Name of the account-owned SSM deployment document."
  value       = aws_ssm_document.deploy_container.name
}
