################################
# IAM
# - ECS task execution role: ECR pull / Secrets / Logs
# - 各サービス task role: アプリケーションが使う AWS 権限を最小化して付与
################################

# Execution role (全 ECS タスクで共有)
resource "aws_iam_role" "ecs_task_execution" {
  name = "github-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager 読み取りを execution role に付与 (env -> secret 連携)
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_password.arn,
        aws_secretsmanager_secret.rails_master_key.arn,
      ]
    }]
  })
}

# Frontend task role (現状特に AWS API は不要)
resource "aws_iam_role" "ecs_task_frontend" {
  name = "github-ecs-task-frontend"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Backend task role: S3 / SQS への権限
resource "aws_iam_role" "ecs_task_backend" {
  name = "github-ecs-task-backend"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_backend" {
  role = aws_iam_role.ecs_task_backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.attachments.arn}/*",
          "${aws_s3_bucket.exports.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          aws_s3_bucket.attachments.arn,
          aws_s3_bucket.exports.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [
          aws_sqs_queue.notifications.arn,
          aws_sqs_queue.notifications_dlq.arn,
        ]
      },
    ]
  })
}

# ai-worker task role (現状 AWS API 利用なし、将来 SageMaker/Bedrock 等を使う想定で空ロール)
resource "aws_iam_role" "ecs_task_ai_worker" {
  name = "github-ecs-task-ai-worker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
