################################
# IAM
# - ECS task execution role: ECR pull / Secrets / Logs
# - 各サービス task role: アプリケーションが使う AWS 権限を最小化
################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "perplexity-ecs-task-execution"

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
        aws_secretsmanager_secret.rodauth_jwt_secret.arn,
        aws_secretsmanager_secret.opensearch_master_password.arn,
      ]
    }]
  })
}

resource "aws_iam_role" "ecs_task_frontend" {
  name = "perplexity-ecs-task-frontend"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Backend task role: corpus S3 への read 権限
resource "aws_iam_role" "ecs_task_backend" {
  name = "perplexity-ecs-task-backend"
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
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.corpus.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          aws_s3_bucket.corpus.arn,
        ]
      },
    ]
  })
}

# ai-worker task role: corpus S3 read + OpenSearch http (本番想定)
resource "aws_iam_role" "ecs_task_ai_worker" {
  name = "perplexity-ecs-task-ai-worker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_ai_worker" {
  role = aws_iam_role.ecs_task_ai_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.corpus.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          aws_s3_bucket.corpus.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = ["es:ESHttpGet", "es:ESHttpPost", "es:ESHttpPut", "es:ESHttpDelete"]
        Resource = [
          "${aws_opensearch_domain.main.arn}/*",
        ]
      },
    ]
  })
}
