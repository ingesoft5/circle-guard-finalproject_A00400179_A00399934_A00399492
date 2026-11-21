resource "aws_cloudwatch_log_group" "node" {
  name              = "/circleguard/${var.environment}/k3s"
  retention_in_days = var.retention_days
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }
}
