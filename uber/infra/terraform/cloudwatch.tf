resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/uber/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/uber/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/uber/ai-worker"
  retention_in_days = 30
}
