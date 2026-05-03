################################
# IAM Roles
################################

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 共通: ECR pull / CloudWatch Logs 書き込み
resource "aws_iam_role" "ecs_task_execution" {
  name               = "instagram-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets を読むための inline policy
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "instagram-ecs-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.django_secret_key.arn,
        aws_secretsmanager_secret.db_password.arn,
      ]
    }]
  })
}

# Frontend task role: S3 read (画像表示で必要なら)
resource "aws_iam_role" "ecs_task_frontend" {
  name               = "instagram-ecs-task-frontend"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# Backend task role: S3 (image upload) + CloudWatch metric
resource "aws_iam_role" "ecs_task_backend" {
  name               = "instagram-ecs-task-backend"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "ecs_task_backend" {
  name = "instagram-ecs-task-backend"
  role = aws_iam_role.ecs_task_backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.images.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
    ]
  })
}

# ai-worker task role: 必要に応じて拡張 (今は基本のみ)
resource "aws_iam_role" "ecs_task_ai_worker" {
  name               = "instagram-ecs-task-ai-worker"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}
