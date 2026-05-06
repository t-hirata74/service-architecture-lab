data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "zoom-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager から JWT 鍵 / 内部 ingress token を読む権限
resource "aws_iam_policy" "ecs_secrets_read" {
  name = "zoom-ecs-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.internal_ingress_token.arn,
          aws_secretsmanager_secret.rodauth_jwt.arn,
          aws_secretsmanager_secret.db_password.arn,
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_secrets_read.arn
}

resource "aws_iam_role" "ecs_task" {
  name               = "zoom-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}
