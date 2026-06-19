locals {
  portal_names = sort(keys(var.private_app_subnet_cidrs))
  dns_resolver = "${cidrhost(var.vpc_cidr, 2)}/32"

  # Explicit deny pairs make cross-portal intent visible even though NACLs deny
  # unmatched traffic by default.
  cross_portal_denies = merge([
    for portal in local.portal_names : {
      for blocked_index, blocked_portal in local.portal_names :
      "${portal}-blocks-${blocked_portal}" => {
        portal       = portal
        blocked_cidr = var.private_app_subnet_cidrs[blocked_portal]
        rule_number  = 100 + blocked_index
      } if portal != blocked_portal
    }
  ]...)

  portal_public_paths = merge([
    for portal in local.portal_names : {
      for cidr_index, cidr in var.public_subnet_cidrs :
      "${portal}-public-${cidr_index}" => {
        portal      = portal
        cidr        = cidr
        rule_number = 200 + cidr_index
      }
    }
  ]...)

  portal_database_paths = merge([
    for portal in local.portal_names : {
      for cidr_index, cidr in var.private_db_subnet_cidrs :
      "${portal}-database-${cidr_index}" => {
        portal      = portal
        cidr        = cidr
        rule_number = 400 + cidr_index
      }
    }
  ]...)
}

# This security group is a placeholder for a future internet-facing load
# balancer. It is not attached to private EC2 instances.
resource "aws_security_group" "ingress" {
  name_prefix            = "${var.environment}-ingress-"
  description            = "Future HTTPS load balancer boundary"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-ingress-sg"
    Purpose = "IngressPlaceholder"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ingress_https" {
  for_each = toset(var.https_ingress_cidrs)

  security_group_id = aws_security_group.ingress.id
  description       = "Permit HTTPS to a future load balancer"
  cidr_ipv4         = each.value
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

# A distinct security group per portal prevents one portal instance from being
# treated as another portal merely because both run inside the same VPC.
resource "aws_security_group" "portal" {
  for_each = var.private_app_subnet_cidrs

  name_prefix            = "${var.environment}-${each.key}-app-"
  description            = "Isolated application boundary for the ${each.key} portal"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-app-sg"
    Portal  = title(each.key)
    Purpose = "Application"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# The placeholder load balancer may forward only to the application port. A
# portal security group never trusts another portal security group.
resource "aws_vpc_security_group_ingress_rule" "portal_from_ingress" {
  for_each = aws_security_group.portal

  security_group_id            = each.value.id
  description                  = "Permit application traffic from the ingress boundary"
  referenced_security_group_id = aws_security_group.ingress.id
  from_port                    = var.application_port
  ip_protocol                  = "tcp"
  to_port                      = var.application_port
}

resource "aws_vpc_security_group_egress_rule" "ingress_to_portal" {
  for_each = aws_security_group.portal

  security_group_id            = aws_security_group.ingress.id
  description                  = "Forward HTTPS only to the ${each.key} portal"
  referenced_security_group_id = each.value.id
  from_port                    = var.application_port
  ip_protocol                  = "tcp"
  to_port                      = var.application_port
}

# SSH is absent by default. Setting ssh_allowed_cidr creates an explicit,
# narrow exception for a routed VPN or bastion network; 0.0.0.0/0 is rejected.
resource "aws_vpc_security_group_ingress_rule" "portal_ssh" {
  for_each = var.ssh_allowed_cidr == null ? {} : aws_security_group.portal

  security_group_id = each.value.id
  description       = "Temporary SSH exception; prefer SSM Session Manager"
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# PostgreSQL is the only application-to-database egress allowed by this module.
resource "aws_security_group" "rds" {
  name_prefix            = "${var.environment}-postgresql-"
  description            = "Private PostgreSQL boundary"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-postgresql-sg"
    Purpose = "Database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "portal_to_rds" {
  for_each = aws_security_group.portal

  security_group_id            = each.value.id
  description                  = "Permit ${each.key} to reach PostgreSQL"
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}

# Referencing the portal security groups is stronger than permitting the whole
# VPC CIDR. No internet CIDR or public subnet CIDR can reach PostgreSQL.
resource "aws_vpc_security_group_ingress_rule" "rds_from_portal" {
  for_each = aws_security_group.portal

  security_group_id            = aws_security_group.rds.id
  description                  = "Permit PostgreSQL from the ${each.key} application group"
  referenced_security_group_id = each.value.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}

# Private instances need VPC DNS to resolve the RDS endpoint. No general
# internet HTTPS egress is included in the no-NAT assignment topology.
resource "aws_vpc_security_group_egress_rule" "portal_dns_udp" {
  for_each = aws_security_group.portal

  security_group_id = each.value.id
  description       = "Resolve private AWS service names using the VPC resolver"
  cidr_ipv4         = local.dns_resolver
  from_port         = 53
  ip_protocol       = "udp"
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "portal_dns_tcp" {
  for_each = aws_security_group.portal

  security_group_id = each.value.id
  description       = "Permit DNS TCP fallback to the VPC resolver"
  cidr_ipv4         = local.dns_resolver
  from_port         = 53
  ip_protocol       = "tcp"
  to_port           = 53
}

# Each application subnet receives its own NACL. Explicit cross-portal denies
# create a subnet-level boundary if an application attempts direct lateral traffic.
resource "aws_network_acl" "portal" {
  for_each = var.application_subnet_ids

  vpc_id     = var.vpc_id
  subnet_ids = [each.value]

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-app-nacl"
    Portal  = title(each.key)
    Purpose = "ApplicationIsolation"
  })
}

resource "aws_network_acl_rule" "portal_blocks_other_portals_ingress" {
  for_each = local.cross_portal_denies

  network_acl_id = aws_network_acl.portal[each.value.portal].id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = each.value.blocked_cidr
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_rule" "portal_blocks_other_portals_egress" {
  for_each = local.cross_portal_denies

  network_acl_id = aws_network_acl.portal[each.value.portal].id
  rule_number    = each.value.rule_number
  egress         = true
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = each.value.blocked_cidr
  from_port      = 0
  to_port        = 0
}

# A future load balancer in the public subnets can reach only the application
# port. Return traffic uses ephemeral destination ports because NACLs are stateless.
resource "aws_network_acl_rule" "portal_from_public_ingress" {
  for_each = local.portal_public_paths

  network_acl_id = aws_network_acl.portal[each.value.portal].id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = var.application_port
  to_port        = var.application_port
}

resource "aws_network_acl_rule" "portal_to_public_response" {
  for_each = local.portal_public_paths

  network_acl_id = aws_network_acl.portal[each.value.portal].id
  rule_number    = each.value.rule_number
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = var.ephemeral_port_start
  to_port        = var.ephemeral_port_end
}

# Application subnets may initiate PostgreSQL connections to database subnets.
# The matching ingress rule permits only stateless return traffic from port 5432.
resource "aws_network_acl_rule" "portal_to_database" {
  for_each = local.portal_database_paths

  network_acl_id = aws_network_acl.portal[each.value.portal].id
  rule_number    = each.value.rule_number
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "portal_from_database_response" {
  for_each = local.portal_database_paths

  network_acl_id = aws_network_acl.portal[each.value.portal].id
  rule_number    = each.value.rule_number
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = var.ephemeral_port_start
  to_port        = var.ephemeral_port_end
}

resource "aws_network_acl_rule" "portal_dns_udp_egress" {
  for_each = aws_network_acl.portal

  network_acl_id = each.value.id
  rule_number    = 500
  egress         = true
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = local.dns_resolver
  from_port      = 53
  to_port        = 53
}

resource "aws_network_acl_rule" "portal_dns_udp_response" {
  for_each = aws_network_acl.portal

  network_acl_id = each.value.id
  rule_number    = 500
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = local.dns_resolver
  from_port      = var.ephemeral_port_start
  to_port        = var.ephemeral_port_end
}

resource "aws_network_acl_rule" "portal_dns_tcp_egress" {
  for_each = aws_network_acl.portal

  network_acl_id = each.value.id
  rule_number    = 501
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.dns_resolver
  from_port      = 53
  to_port        = 53
}

resource "aws_network_acl_rule" "portal_dns_tcp_response" {
  for_each = aws_network_acl.portal

  network_acl_id = each.value.id
  rule_number    = 501
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.dns_resolver
  from_port      = var.ephemeral_port_start
  to_port        = var.ephemeral_port_end
}

resource "aws_network_acl_rule" "portal_ssh_ingress" {
  for_each = var.ssh_allowed_cidr == null ? {} : aws_network_acl.portal

  network_acl_id = each.value.id
  rule_number    = 300
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.ssh_allowed_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "portal_ssh_response" {
  for_each = var.ssh_allowed_cidr == null ? {} : aws_network_acl.portal

  network_acl_id = each.value.id
  rule_number    = 300
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.ssh_allowed_cidr
  from_port      = var.ephemeral_port_start
  to_port        = var.ephemeral_port_end
}

# RDS subnets share a database NACL. Only portal application CIDRs can start a
# PostgreSQL connection; public and arbitrary VPC sources remain denied.
resource "aws_network_acl" "database" {
  vpc_id     = var.vpc_id
  subnet_ids = var.database_subnet_ids

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-database-nacl"
    Purpose = "DatabaseIsolation"
  })
}

resource "aws_network_acl_rule" "database_from_portal" {
  for_each = var.private_app_subnet_cidrs

  network_acl_id = aws_network_acl.database.id
  rule_number    = 200 + index(local.portal_names, each.key)
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "database_to_portal_response" {
  for_each = var.private_app_subnet_cidrs

  network_acl_id = aws_network_acl.database.id
  rule_number    = 200 + index(local.portal_names, each.key)
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value
  from_port      = var.ephemeral_port_start
  to_port        = var.ephemeral_port_end
}

# These controls isolate portal compute and database network entry points. They
# cannot distinguish rows inside shared PostgreSQL; forced RLS and scoped DB
# roles remain the enforcement boundary for customer-level data isolation.
