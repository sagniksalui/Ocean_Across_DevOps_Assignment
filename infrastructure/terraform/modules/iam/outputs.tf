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
