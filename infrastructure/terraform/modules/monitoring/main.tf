check "portal_monitoring_contracts" {
  assert {
    condition     = sort(var.portals) == sort(keys(var.portal_instance_ids))
    error_message = "Portal names and EC2 instance ID keys must be identical."
  }
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# A dedicated log group per portal keeps Companies, Bureaus, and Employees
# application logs independently searchable and aligned with their IAM boundary.
# Retention is finite so operational evidence is available without storing logs
# indefinitely; applications must still exclude payroll data, bank details, and secrets.
resource "aws_cloudwatch_log_group" "portal" {
  for_each = toset(var.portals)

  name              = "/ocean-across/${var.environment}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-application-logs"
    Portal  = title(each.key)
    Purpose = "ApplicationLogging"
  })
}

# The assignment also asks for infrastructure log groups. This destination is
# created separately from application logs, but no delivery agent is claimed in
# the no-egress topology. SSM/OS logs must exclude secrets and payroll content.
resource "aws_cloudwatch_log_group" "infrastructure" {
  for_each = toset(var.portals)

  name              = "/ocean-across/${var.environment}/${each.key}/infrastructure"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-${each.key}-infrastructure-logs"
    Portal  = title(each.key)
    Purpose = "InfrastructureLogging"
  })
}

# The topic is the common incident-notification path. Alarm and recovery
# notifications give responders both detection and closure signals. SNS payloads
# must contain operational identifiers only: KMS is outside the assignment's
# permitted live-deployment service list, so sensitive data is prohibited here.
resource "aws_sns_topic" "critical_alerts" {
  name         = "${var.environment}-payroll-critical-alerts"
  display_name = "${title(var.environment)} payroll alerts"

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-payroll-critical-alerts"
    Purpose = "IncidentNotification"
  })
}

# Permit only this account's CloudWatch alarms to publish across the service
# boundary. SourceAccount and SourceArn mitigate confused-deputy requests, while
# topic administration remains with this account rather than public principals.
data "aws_iam_policy_document" "critical_alerts" {
  statement {
    sid    = "AccountTopicAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "sns:AddPermission",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:Publish",
      "sns:Receive",
      "sns:RemovePermission",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
    ]
    resources = [aws_sns_topic.critical_alerts.arn]
  }

  statement {
    sid    = "CloudWatchAlarmPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.critical_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:*:${data.aws_caller_identity.current.account_id}:alarm:*"]
    }
  }
}

resource "aws_sns_topic_policy" "critical_alerts" {
  arn    = aws_sns_topic.critical_alerts.arn
  policy = data.aws_iam_policy_document.critical_alerts.json
}

# Email is optional and supplied outside source control. AWS sends a confirmation
# request before this subscription can receive alerts, preventing silent delivery
# to an unverified address. The address is stored in Terraform state, not in code.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Sustained high CPU can indicate load, a runaway process, or malicious activity.
# Two consecutive periods reduce transient noise while still creating an early
# incident signal for the isolated portal host that needs investigation.
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  for_each = var.portal_instance_ids

  alarm_name          = "${var.environment}-${each.key}-ec2-high-cpu"
  alarm_description   = "Sustained CPU pressure on the ${each.key} portal EC2 instance."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.ec2_cpu_threshold_percent
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  # Missing metrics can mean the instance stopped reporting. Treat that as an
  # incident signal rather than silently reporting a healthy state.
  treat_missing_data = "breaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]
  ok_actions    = [aws_sns_topic.critical_alerts.arn]

  tags = merge(var.common_tags, {
    Name     = "${var.environment}-${each.key}-ec2-high-cpu"
    Portal   = title(each.key)
    Purpose  = "IncidentDetection"
    Severity = "Critical"
  })

  depends_on = [aws_sns_topic_policy.critical_alerts]
}

# A connection surge can precede PostgreSQL exhaustion, failed payroll requests,
# or an abusive client. Alerting before the micro instance reaches its practical
# limit gives responders time to identify the portal and contain the source.
resource "aws_cloudwatch_metric_alarm" "rds_high_connections" {
  alarm_name          = "${var.environment}-rds-high-database-connections"
  alarm_description   = "RDS PostgreSQL connections are approaching the configured operational limit."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.rds_connection_threshold
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  # A missing RDS metric can indicate an unavailable or misconfigured database.
  # Planned maintenance must therefore be coordinated with alert suppression.
  treat_missing_data = "breaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]
  ok_actions    = [aws_sns_topic.critical_alerts.arn]

  tags = merge(var.common_tags, {
    Name     = "${var.environment}-rds-high-database-connections"
    Purpose  = "IncidentDetection"
    Severity = "Critical"
  })

  depends_on = [aws_sns_topic_policy.critical_alerts]
}
