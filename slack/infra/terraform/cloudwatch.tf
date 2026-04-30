################################
# CloudWatch
# - 各 ECS サービスのログ
# - 重要メトリクスのアラーム (ALB 5xx, RDS CPU, Redis CPU)
################################

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/slack/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/slack/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/slack/ai-worker"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "redis_slowlog" {
  name              = "/elasticache/slack/redis/slow"
  retention_in_days = 14
}

# ALB 5xx > 10/min でアラート
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "slack-alb-5xx"
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
  alarm_name          = "slack-rds-cpu-high"
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

# Redis CPU 75% で警告
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "slack-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 75

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }

  alarm_description = "ElastiCache Redis の CPU 使用率が 75% 超"
}
