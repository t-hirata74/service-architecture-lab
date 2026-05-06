resource "aws_cloudwatch_log_group" "backend" {
  name              = "/zoom/backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/zoom/frontend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/zoom/ai-worker"
  retention_in_days = 14
}
