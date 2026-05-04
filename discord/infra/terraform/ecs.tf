################################
# ECS Fargate
#
# 3 service: frontend (Next.js) / backend (Go gateway) / ai-worker (FastAPI)
# perplexity / instagram と違い:
#   - Celery worker 相当なし (ai-worker は同期 REST)
#   - Redis ElastiCache なし (ADR 0001: 単一プロセス Hub)
################################

resource "aws_ecs_cluster" "main" {
  name = "discord-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "discord.internal"
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
  family                   = "discord-frontend"
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
      { name = "NEXT_PUBLIC_WS_URL", value = "wss://${var.domain_name}/gateway" },
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
  name            = "discord-frontend"
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

# ─── backend (Go gateway) ────────────────────────────────────────────────────
#
# desired_count=2 で複数台立てているが、ADR 0001 通り **同 guild の subscriber が
# 別タスクに分散すると fan-out できない**。ここでは "REST 負荷の水平分散" のみ
# 期待し、WebSocket スケーリング戦略は派生 ADR 0005 (multi-process + Redis pub/sub)
# にて扱う想定。

resource "aws_ecs_task_definition" "backend" {
  family                   = "discord-backend"
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
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "HTTP_ADDR", value = ":8080" },
      { name = "HEARTBEAT_INTERVAL_MS", value = tostring(var.heartbeat_interval_ms) },
      { name = "AI_WORKER_URL", value = "http://ai-worker.discord.internal:8000" },
    ]
    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn },
      { name = "AI_INTERNAL_TOKEN", valueFrom = aws_secretsmanager_secret.ai_internal_token.arn },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:8080/health || exit 1"]
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
  name            = "discord-backend"
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
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.https]
}

# ─── ai-worker ───────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "ai_worker" {
  family                   = "discord-ai-worker"
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
    secrets = [
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
  name            = "discord-ai-worker"
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
