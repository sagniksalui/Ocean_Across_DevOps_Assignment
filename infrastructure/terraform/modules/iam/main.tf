locals {
  ec2_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  portal_prefixes = {
    for portal, prefix in var.portal_prefixes : portal => trimsuffix(prefix, "/")
  }

  portal_object_actions = [
    "s3:AbortMultipartUpload",
    "s3:DeleteObject",
    "s3:GetObject",
    "s3:ListMultipartUploadParts",
    "s3:PutObject",
  ]

  prefix_scoped_bucket_actions = [
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads",
    "s3:ListBucketVersions",
  ]

  log_group_arns = {
    for portal in var.portals : portal =>
    [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ocean-across/${var.environment}/${portal}:*",
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ocean-across/${var.environment}/${portal}/infrastructure:*",
    ]
  }

  parameter_path_arns = {
    for portal in var.portals : portal =>
    "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/payroll/${var.environment}/${portal}/*"
  }
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

check "portal_prefix_contracts" {
  assert {
    condition     = sort(var.portals) == sort(keys(var.portal_prefixes))
    error_message = "IAM portals and S3 portal prefixes must use identical keys."
  }
}

# Separate roles prevent one portal instance from inheriting another portal's
# future S3, parameter, or logging permissions.
resource "aws_iam_role" "portal" {
  for_each = toset(var.portals)

  name               = "${var.environment}-${each.key}-ec2-role"
  path               = "/payroll/"
  assume_role_policy = local.ec2_assume_role_policy

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-ec2-role"
    Portal  = title(each.key)
    Purpose = "ApplicationCompute"
  })
}

# SSM is preferred to SSH. Use narrow Session Manager and Run Command channel
# actions instead of AmazonSSMManagedInstanceCore, whose broad GetParameter
# permissions would bypass the portal-specific Parameter Store paths below.
data "aws_iam_policy_document" "portal_session_manager" {
  statement {
    sid    = "SessionManagerAgentChannels"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]

    # These service channel actions do not support resource-level scoping.
    resources = ["*"]
  }

  statement {
    sid    = "RunCommandMessageChannel"
    effect = "Allow"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]

    # Message transport APIs also do not support resource-level scoping.
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "portal_session_manager" {
  for_each = aws_iam_role.portal

  name   = "${var.environment}-${each.key}-session-manager"
  role   = each.value.name
  policy = data.aws_iam_policy_document.portal_session_manager.json
}

# This document exposes only validated deployment parameters and invokes a
# fixed root-owned host script. It avoids granting CI arbitrary shell content
# through the AWS-managed AWS-RunShellScript document.
resource "aws_ssm_document" "deploy_container" {
  name            = "${var.environment}-ocean-across-deploy"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy a validated Ocean Across container artifact"
    parameters = {
      Service = {
        type          = "String"
        allowedValues = ["frontend", "backend", "ai"]
      }
      ImageName = {
        type           = "String"
        allowedPattern = "^ocean-across-(frontend|backend|ai):[0-9a-f]{40}$"
      }
      DeploymentBucket = {
        type           = "String"
        allowedPattern = "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"
      }
      ArtifactKey = {
        type           = "String"
        allowedPattern = "^deployments/(dev|production)/(frontend|backend|ai)/[0-9a-f]{40}/[0-9]+-[0-9]+/image[.]tar[.]gz$"
      }
      ExpectedDigest = {
        type           = "String"
        allowedPattern = "^[0-9a-f]{64}$"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deployContainer"
      inputs = {
        runCommand = [
          "/usr/local/sbin/ocean-across-deploy '{{ Service }}' '{{ ImageName }}' '{{ DeploymentBucket }}' '{{ ArtifactKey }}' '{{ ExpectedDigest }}'",
        ]
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-ocean-across-deploy"
    Purpose = "ValidatedContainerDeployment"
  })
}

# Each role can list only its own logical S3 prefix and access objects only
# beneath that prefix. No Allow statement uses s3:* or the full object namespace.
data "aws_iam_policy_document" "portal_documents" {
  for_each = aws_iam_role.portal

  statement {
    sid     = "ListOwnPrefix"
    effect  = "Allow"
    actions = ["s3:ListBucket"]

    resources = [var.documents_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "${local.portal_prefixes[each.key]}/",
        "${local.portal_prefixes[each.key]}/*",
      ]
    }
  }

  statement {
    sid       = "AccessOwnObjects"
    effect    = "Allow"
    actions   = local.portal_object_actions
    resources = ["${var.documents_bucket_arn}/${local.portal_prefixes[each.key]}/*"]
  }
}

resource "aws_iam_role_policy" "portal_documents" {
  for_each = aws_iam_role.portal

  name   = "${var.environment}-${each.key}-payroll-documents"
  role   = each.value.name
  policy = data.aws_iam_policy_document.portal_documents[each.key].json
}

# Parameter Store access is scoped to the service path. A Companies instance
# cannot retrieve Bureaus or Employees configuration, even if it knows the name.
data "aws_iam_policy_document" "portal_parameters" {
  for_each = aws_iam_role.portal

  statement {
    sid    = "ReadOwnParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [local.parameter_path_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "portal_parameters" {
  for_each = aws_iam_role.portal

  name   = "${var.environment}-${each.key}-runtime-parameters"
  role   = each.value.name
  policy = data.aws_iam_policy_document.portal_parameters[each.key].json
}

# Log permissions are limited to the portal's pre-created CloudWatch log group.
# Log-group creation and retention remain infrastructure responsibilities.
data "aws_iam_policy_document" "portal_logging" {
  for_each = aws_iam_role.portal

  statement {
    sid    = "WriteOwnApplicationLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = local.log_group_arns[each.key]
  }
}

resource "aws_iam_role_policy" "portal_logging" {
  for_each = aws_iam_role.portal

  name   = "${var.environment}-${each.key}-application-logs"
  role   = each.value.name
  policy = data.aws_iam_policy_document.portal_logging[each.key].json
}

# The bucket resource policy is an independent guardrail. It denies each portal
# role from every other object namespace, out-of-prefix listing, and bucket
# administration even if a broader identity policy is attached accidentally.
data "aws_iam_policy_document" "documents_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      var.documents_bucket_arn,
      "${var.documents_bucket_arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = aws_iam_role.portal

    content {
      sid    = "Deny${title(statement.key)}OutsideOwnPrefix"
      effect = "Deny"

      principals {
        type        = "AWS"
        identifiers = [statement.value.arn]
      }

      actions = ["s3:*"]
      not_resources = [
        var.documents_bucket_arn,
        "${var.documents_bucket_arn}/${local.portal_prefixes[statement.key]}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = aws_iam_role.portal

    content {
      sid    = "Deny${title(statement.key)}CrossPrefixListing"
      effect = "Deny"

      principals {
        type        = "AWS"
        identifiers = [statement.value.arn]
      }

      actions   = local.prefix_scoped_bucket_actions
      resources = [var.documents_bucket_arn]

      condition {
        test     = "StringNotLike"
        variable = "s3:prefix"
        values = [
          "${local.portal_prefixes[statement.key]}/",
          "${local.portal_prefixes[statement.key]}/*",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = aws_iam_role.portal

    content {
      sid    = "Deny${title(statement.key)}BucketAdministration"
      effect = "Deny"

      principals {
        type        = "AWS"
        identifiers = [statement.value.arn]
      }

      not_actions = local.prefix_scoped_bucket_actions
      resources   = [var.documents_bucket_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "documents" {
  bucket = var.documents_bucket_name
  policy = data.aws_iam_policy_document.documents_bucket.json
}

resource "aws_iam_instance_profile" "portal" {
  for_each = aws_iam_role.portal

  name = "${var.environment}-${each.key}-ec2-profile"
  path = "/payroll/"
  role = each.value.name

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-ec2-profile"
    Portal  = title(each.key)
    Purpose = "ApplicationCompute"
  })

  depends_on = [
    aws_iam_role_policy.portal_documents,
    aws_iam_role_policy.portal_logging,
    aws_iam_role_policy.portal_parameters,
    aws_iam_role_policy.portal_session_manager,
  ]
}

# These roles isolate portal categories. They do not isolate individual
# companies within companies/*; that requires trusted tenant-scoped sessions or
# separate tenant roles rather than a shared EC2 instance role.
