################################
# CloudWatch
# - 各 ECS サービスのログ
# - OpenSearch のアプリケーションログ
# - 重要メトリクスのアラーム (ALB 5xx, RDS CPU)
################################

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/perplexity/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/perplexity/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/perplexity/ai-worker"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "opensearch" {
  name              = "/aws/opensearch/perplexity"
  retention_in_days = 30
}

# ALB 5xx > 10/min でアラート
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "perplexity-alb-5xx"
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

  alarm_description = "ALB target 5xx が閾値超過 (ADR 0003 §A 領域の失敗が頻発している兆候)"
}

# Aurora CPU 80% で警告
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "perplexity-rds-cpu-high"
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

# OpenSearch クラスタの red status を監視 (knn 検索の可用性に直結)
resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_red" {
  alarm_name          = "perplexity-opensearch-red"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_description = "OpenSearch ドメインが red 状態"
}

data "aws_caller_identity" "current" {}
