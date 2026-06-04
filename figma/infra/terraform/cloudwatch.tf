resource "aws_cloudwatch_log_group" "backend" {
  name              = "/figma/backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/figma/frontend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/figma/ai-worker"
  retention_in_days = 14
}
