resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/shopify/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/shopify/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/shopify/ai-worker"
  retention_in_days = 30
}
