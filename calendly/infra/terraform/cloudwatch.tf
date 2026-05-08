resource "aws_cloudwatch_log_group" "backend" {
  name              = "/calendly/backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/calendly/frontend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/calendly/ai-worker"
  retention_in_days = 14
}
