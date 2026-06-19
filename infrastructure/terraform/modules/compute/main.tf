data "aws_ami" "amazon_linux" {
  count = var.ami_id == null ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  selected_ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux[0].id
  portal_names    = sort(keys(var.instance_types))
}

check "portal_module_contracts" {
  assert {
    condition = (
      local.portal_names == sort(keys(var.subnet_ids)) &&
      local.portal_names == sort(keys(var.security_group_ids)) &&
      local.portal_names == sort(keys(var.instance_profile_names))
    )
    error_message = "Instance types, subnets, security groups, and instance profiles must use identical portal keys."
  }
}

# A separate instance per portal prevents process, filesystem, metadata, IAM,
# and security-group sharing between Companies, Bureaus, and Employees.
resource "aws_instance" "portal" {
  for_each = var.instance_types

  ami                         = local.selected_ami_id
  instance_type               = each.value
  subnet_id                   = var.subnet_ids[each.key]
  vpc_security_group_ids      = [var.security_group_ids[each.key]]
  iam_instance_profile        = var.instance_profile_names[each.key]
  associate_public_ip_address = false
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    environment = var.environment
    portal      = each.key
  })
  user_data_replace_on_change = true

  # IMDSv2 reduces exposure to metadata credential theft through SSRF.
  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  # Encryption is explicit even when an account-level EBS default is absent.
  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
  }

  tags = merge(var.common_tags, {
    Name       = "${var.environment}-${each.key}-backend"
    Owner      = var.owner
    Portal     = title(each.key)
    Service    = "Backend"
    TenantType = title(each.key)
  })

  volume_tags = merge(var.common_tags, {
    Name       = "${var.environment}-${each.key}-backend-root"
    Owner      = var.owner
    Portal     = title(each.key)
    Service    = "Backend"
    TenantType = title(each.key)
  })
}
