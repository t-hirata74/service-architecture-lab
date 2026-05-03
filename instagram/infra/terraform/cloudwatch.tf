################################
# CloudWatch Log Groups (ECS task definition から参照)
################################

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/instagram/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/instagram/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "celery" {
  name              = "/ecs/instagram/celery"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "ai_worker" {
  name              = "/ecs/instagram/ai-worker"
  retention_in_days = 30
}
