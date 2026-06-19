output "portal_log_group_names" {
  description = "CloudWatch application log group name keyed by portal."
  value = {
    for portal, log_group in aws_cloudwatch_log_group.portal : portal => log_group.name
  }
}

output "infrastructure_log_group_names" {
  description = "CloudWatch infrastructure log group name keyed by portal."
  value = {
    for portal, log_group in aws_cloudwatch_log_group.infrastructure : portal => log_group.name
  }
}

output "ec2_cpu_alarm_names" {
  description = "EC2 high-CPU CloudWatch alarm name keyed by portal."
  value = {
    for portal, alarm in aws_cloudwatch_metric_alarm.ec2_high_cpu : portal => alarm.alarm_name
  }
}

output "rds_database_connections_alarm_name" {
  description = "Name of the RDS high-database-connections CloudWatch alarm."
  value       = aws_cloudwatch_metric_alarm.rds_high_connections.alarm_name
}

output "alarm_names" {
  description = "Names of all CloudWatch alarms created by this module."
  value = concat(
    [for portal in sort(keys(aws_cloudwatch_metric_alarm.ec2_high_cpu)) : aws_cloudwatch_metric_alarm.ec2_high_cpu[portal].alarm_name],
    [aws_cloudwatch_metric_alarm.rds_high_connections.alarm_name],
  )
}

output "sns_topic_arn" {
  description = "ARN of the operational SNS topic; payloads must not contain payroll data, PII, credentials, or secrets."
  value       = aws_sns_topic.critical_alerts.arn
}
