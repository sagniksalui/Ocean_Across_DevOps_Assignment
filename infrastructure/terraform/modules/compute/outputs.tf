output "instance_ids" {
  description = "EC2 instance ID keyed by portal."
  value = {
    for portal, instance in aws_instance.portal : portal => instance.id
  }
}

output "private_ips" {
  description = "Private IPv4 address keyed by portal."
  value = {
    for portal, instance in aws_instance.portal : portal => instance.private_ip
  }
}
