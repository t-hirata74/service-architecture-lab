resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/datadog/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/datadog/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/datadog/ai-worker"
  retention_in_days = 30
}
