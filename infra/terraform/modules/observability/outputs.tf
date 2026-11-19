output "log_group_name" {
  value = aws_cloudwatch_log_group.node.name
}

output "cpu_alarm_name" {
  value = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}
