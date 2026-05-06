resource "aws_ecs_cluster" "main" {
  name = "zoom-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Backend (Rails API + Solid Queue を同 task に同居 / SOLID_QUEUE_IN_PUMA=1)。
# スループット要求が上がったら別 service に分離するのが次の一手 (ADR 0001 / 0003)。
resource "aws_ecs_task_definition" "backend" {
  family                   = "zoom-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name         = "backend"
      image        = var.backend_image
      essential    = true
      portMappings = [{ containerPort = 3090 }]
      environment = [
        { name = "RAILS_ENV", value = "production" },
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_PORT", value = "3306" },
        { name = "DB_USER", value = "zoom_admin" },
        { name = "AI_WORKER_URL", value = "http://ai-worker.zoom.local:8080" },
        { name = "SOLID_QUEUE_IN_PUMA", value = "1" },
      ]
      secrets = [
        { name = "INTERNAL_INGRESS_TOKEN", valueFrom = aws_secretsmanager_secret.internal_ingress_token.arn },
        { name = "RODAUTH_JWT_SECRET", valueFrom = aws_secretsmanager_secret.rodauth_jwt.arn },
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "backend"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "backend" {
  name            = "zoom-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 3090
  }

  depends_on = [aws_lb_listener.https]
}

# Frontend (Next.js production server)
resource "aws_ecs_task_definition" "frontend" {
  family                   = "zoom-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name         = "frontend"
      image        = var.frontend_image
      essential    = true
      portMappings = [{ containerPort = 3095 }]
      environment = [
        { name = "NEXT_PUBLIC_API_BASE", value = "https://${var.domain_name}" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.frontend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "frontend"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "frontend" {
  name            = "zoom-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3095
  }

  depends_on = [aws_lb_listener.https]
}

# ai-worker (内部からのみアクセス。Service Discovery 経由)
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "zoom.local"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "ai_worker" {
  name = "ai-worker"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "ai_worker" {
  family                   = "zoom-ai-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name         = "ai-worker"
      image        = var.ai_worker_image
      essential    = true
      portMappings = [{ containerPort = 8080 }]
      secrets = [
        { name = "INTERNAL_TOKEN", valueFrom = aws_secretsmanager_secret.internal_ingress_token.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ai_worker.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ai-worker"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ai_worker" {
  name            = "zoom-ai-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ai_worker.arn
  }
}
