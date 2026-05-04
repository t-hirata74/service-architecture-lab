resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/discord/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/discord/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/discord/ai-worker"
  retention_in_days = 30
}
