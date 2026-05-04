resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/reddit/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/reddit/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/reddit/ai-worker"
  retention_in_days = 30
}
