################################
# ECS Fargate
#
# 3 service: frontend (Next.js) / backend (FastAPI) / ai-worker (FastAPI + APScheduler)
#
# 設計上の留意点 (ADR 0003 + ADR 0004):
#   - ai-worker は **desired_count=1**。APScheduler を複数台で並走させると Hot 再計算
#     と reconcile job が重複起動する。派生 ADR で advisory lock 化すれば horizontal
#     scale 可能。
#   - backend は async I/O (FastAPI + aiomysql) なので 1 task で多数の接続を捌ける。
#     desired_count=2 は AZ 冗長目的のみ。
#   - Redis ElastiCache なし (ranking は MySQL の denormalize で完結、ADR 0003)。
################################

resource "aws_ecs_cluster" "main" {
  name = "reddit-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "reddit.internal"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "ai_worker" {
  name = "ai-worker"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  health_check_custom_config { failure_threshold = 1 }
}

# ─── frontend ────────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "frontend" {
  family                   = "reddit-frontend"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.frontend_task.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = var.frontend_image
    essential = true
    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]
    environment = [
      { name = "NEXT_PUBLIC_API_URL", value = "https://${var.domain_name}" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.frontend.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "frontend"
      }
    }
  }])
}

resource "aws_ecs_service" "frontend" {
  name            = "reddit-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets         = aws_subnet.private_app[*].id
    security_groups = [aws_security_group.frontend.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.https]
}

# ─── backend (FastAPI) ───────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "backend" {
  family                   = "reddit-backend"
  cpu                      = "1024"
  memory                   = "2048"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.backend_task.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = var.backend_image
    essential = true
    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]
    environment = [
      { name = "AI_WORKER_URL", value = "http://ai-worker.reddit.internal:8000" },
    ]
    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn },
      { name = "INTERNAL_TOKEN", valueFrom = aws_secretsmanager_secret.ai_internal_token.arn },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/health')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.backend.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "backend"
      }
    }
  }])
}

resource "aws_ecs_service" "backend" {
  name            = "reddit-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets         = aws_subnet.private_app[*].id
    security_groups = [aws_security_group.backend.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.https]
}

# ─── ai-worker (FastAPI + APScheduler) ───────────────────────────────────────
#
# desired_count=1 が **設計上の制約** (ADR 0003)。複数台立てると
# recompute_hot_scores と reconcile_score が重複実行される。
# horizontal scale したい場合は派生 ADR で advisory lock を入れる。

resource "aws_ecs_task_definition" "ai_worker" {
  family                   = "reddit-ai-worker"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ai_worker_task.arn

  container_definitions = jsonencode([{
    name      = "ai-worker"
    image     = var.ai_worker_image
    essential = true
    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]
    environment = [
      { name = "ENABLE_SCHEDULER", value = "true" },
    ]
    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "INTERNAL_TOKEN", valueFrom = aws_secretsmanager_secret.ai_internal_token.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ai_worker.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "ai-worker"
      }
    }
  }])
}

resource "aws_ecs_service" "ai_worker" {
  name            = "reddit-ai-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_worker.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.private_app[*].id
    security_groups = [aws_security_group.ai_worker.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ai_worker.arn
  }
}
