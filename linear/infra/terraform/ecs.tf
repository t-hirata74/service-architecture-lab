################################
# ECS Fargate
#
# 3 service: frontend (Next.js) / backend (NestJS) / ai-worker (FastAPI)
#   - キューなし (mutation は同期 REST、配信は WS push + delta 自己修復)
#   - Redis ElastiCache なし (ADR 0005: WS room は in-memory Map / 単一プロセス)
#   - ai-worker は同期 REST + 共有トークン (graceful degradation)
################################

resource "aws_ecs_cluster" "main" {
  name = "linear-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "linear.internal"
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
  family                   = "linear-frontend"
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
      # WS URL は client 側で API_URL から導出する (frontend/src/lib/config.ts)
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
  name            = "linear-frontend"
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

# ─── backend (NestJS) ────────────────────────────────────────────────────────
#
# desired_count=1 が原則。WS room (ADR 0005) が in-memory Map のため、複数タスクに
# 分散すると別タスクの WS 接続へ op push が届かない。正しさは sync log + delta が
# 守る (push は at-most-once のヒント) ので、リアルタイム性を保ったまま水平化する
# には Redis pub/sub 中継を派生 ADR で入れてから desired_count を上げる。
# 採番 (lastSyncId) は DB の counter 行ロックなので multi-task でも壊れない (ADR 0002)。

resource "aws_ecs_task_definition" "backend" {
  family                   = "linear-backend"
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
      containerPort = 3140
      protocol      = "tcp"
    }]
    environment = [
      { name = "PORT", value = "3140" },
      { name = "AI_WORKER_URL", value = "http://ai-worker.linear.internal:8000" },
    ]
    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
      { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn },
      { name = "AI_INTERNAL_TOKEN", valueFrom = aws_secretsmanager_secret.ai_internal_token.arn },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "node -e \"fetch('http://localhost:3140/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
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
  name            = "linear-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.private_app[*].id
    security_groups = [aws_security_group.backend.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 3140
  }

  depends_on = [aws_lb_listener.https]
}

# ─── ai-worker ───────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "ai_worker" {
  family                   = "linear-ai-worker"
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
  name            = "linear-ai-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_worker.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets         = aws_subnet.private_app[*].id
    security_groups = [aws_security_group.ai_worker.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ai_worker.arn
  }
}
