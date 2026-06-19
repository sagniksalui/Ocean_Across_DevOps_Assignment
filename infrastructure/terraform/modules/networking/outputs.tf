output "vpc_id" {
  description = "ID of the payroll VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public ingress subnets, ordered by input CIDR."
  value = [
    for index in range(length(var.public_subnet_cidrs)) :
    aws_subnet.public["public-${index}"].id
  ]
}

output "application_private_subnet_ids" {
  description = "Private application subnet ID keyed by portal."
  value = {
    for portal, subnet in aws_subnet.application : portal => subnet.id
  }
}

output "database_private_subnet_ids" {
  description = "Private database subnet IDs, ordered by input CIDR."
  value = [
    for index in range(length(var.private_db_subnet_cidrs)) :
    aws_subnet.database["database-${index}"].id
  ]
}

output "private_subnet_ids" {
  description = "All private application and database subnet IDs."
  value = concat(
    [for portal in sort(keys(aws_subnet.application)) : aws_subnet.application[portal].id],
    [
      for index in range(length(var.private_db_subnet_cidrs)) :
      aws_subnet.database["database-${index}"].id
    ]
  )
}

output "cidr_blocks" {
  description = "Configured VPC, public, private application, and private database CIDRs."
  value = {
    vpc                 = aws_vpc.main.cidr_block
    public              = var.public_subnet_cidrs
    private_application = var.private_app_subnet_cidrs
    private_database    = var.private_db_subnet_cidrs
  }
}
