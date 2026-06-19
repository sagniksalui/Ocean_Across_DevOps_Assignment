data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Selecting AZs dynamically avoids account-specific AZ name assumptions.
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets = {
    for index, cidr in var.public_subnet_cidrs : "public-${index}" => {
      availability_zone = local.availability_zones[index % length(local.availability_zones)]
      cidr_block        = cidr
    }
  }

  application_subnets = {
    for index, portal in sort(keys(var.private_app_subnet_cidrs)) : portal => {
      availability_zone = local.availability_zones[index % length(local.availability_zones)]
      cidr_block        = var.private_app_subnet_cidrs[portal]
    }
  }

  database_subnets = {
    for index, cidr in var.private_db_subnet_cidrs : "database-${index}" => {
      availability_zone = local.availability_zones[index % length(local.availability_zones)]
      cidr_block        = cidr
    }
  }
}

# The dedicated VPC is the primary network boundary for payroll workloads.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-payroll-vpc"
  })
}

# Only public subnets receive a route to this gateway.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-payroll-igw"
  })
}

# Public subnets are reserved for a future load balancer or controlled access
# component. Public IP assignment remains opt-in to prevent accidental exposure.
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}"
    Tier    = "Public"
    Purpose = "IngressPlaceholder"
  })
}

# Each portal receives a private application subnet. These subnets have no
# internet route, so EC2 instances placed here cannot be reached from the internet.
resource "aws_subnet" "application" {
  for_each = local.application_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-app-private"
    Portal  = title(each.key)
    Tier    = "Private"
    Purpose = "Application"
  })
}

# RDS uses a separate private subnet tier across two AZs. It has no public route
# and is kept apart from application instances for clearer security controls.
resource "aws_subnet" "database" {
  for_each = local.database_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-private"
    Tier    = "Private"
    Purpose = "Database"
  })
}

# The public route table is the only route table with an internet default route.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-public-rt"
    Tier = "Public"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# This route table intentionally contains only the VPC-local route. With no NAT
# gateway, private application instances have no direct internet egress.
resource "aws_route_table" "application_private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-application-private-rt"
    Tier    = "Private"
    Purpose = "Application"
  })
}

resource "aws_route_table_association" "application_private" {
  for_each = aws_subnet.application

  subnet_id      = each.value.id
  route_table_id = aws_route_table.application_private.id
}

# The database route table also has only the VPC-local route. This prevents RDS
# subnets from becoming publicly routable through a future application change.
resource "aws_route_table" "database_private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-database-private-rt"
    Tier    = "Private"
    Purpose = "Database"
  })
}

resource "aws_route_table_association" "database_private" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database_private.id
}
