################################
# CloudWatch
# - 各 ECS サービスのログ
# - 重要メトリクスのアラーム (ALB 5xx, RDS CPU)
# Redis は本構成では使わない (ADR 0001: Solid Queue 採用 / DB-driven Queue)。
# 本番化後にスループットの観点で SQS / Sidekiq+Redis に移行する場合、対応する
# リソースをここで追加する。
################################

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/github/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/github/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/github/ai-worker"
  retention_in_days = 30
}

# ALB 5xx > 10/min でアラート
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "github-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_description = "ALB target 5xx が閾値超過"
}

# Aurora CPU 80% で警告
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "github-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.id
  }

  alarm_description = "Aurora MySQL の CPU 使用率が 80% 超"
}
