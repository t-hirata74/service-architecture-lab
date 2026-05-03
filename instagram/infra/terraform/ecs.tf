################################
# ECS Cluster + 4 Services (Fargate)
# - frontend     (Next.js)              port 3000
# - backend      (Django + DRF + gunicorn) port 8000
# - celery       (Celery worker)        no inbound
# - ai-worker    (FastAPI)              port 8000 (internal)
# 各サービス 2 task で AZ 分散.
################################

resource "aws_ecs_cluster" "main" {
  name = "instagram"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Service Discovery: backend → ai-worker / celery → backend (内部呼び出し)
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "instagram.internal"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "ai_worker" {
  name = "ai-worker"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

############
# Task Definitions
############

resource "aws_ecs_task_definition" "frontend" {
  family                   = "instagram-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_frontend.arn

  container_definitions = jsonencode([{
    name         = "frontend"
    image        = var.frontend_image
    essential    = true
    portMappings = [{ containerPort = 3000, hostPort = 3000, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "NEXT_PUBLIC_API_URL", value = "https://${var.domain_name}" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "frontend"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "instagram-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_backend.arn

  container_definitions = jsonencode([{
    name         = "backend"
    image        = var.backend_image
    essential    = true
    portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
    command      = ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
    environment = [
      { name = "DJANGO_DEBUG", value = "False" },
      { name = "DJANGO_ALLOWED_HOSTS", value = var.domain_name },
      { name = "MYSQL_HOST", value = aws_rds_cluster.main.endpoint },
      { name = "MYSQL_PORT", value = "3306" },
      { name = "MYSQL_USER", value = "instagram" },
      { name = "MYSQL_DATABASE", value = "instagram" },
      { name = "REDIS_URL", value = "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0" },
      { name = "AI_WORKER_URL", value = "http://ai-worker.instagram.internal:8000" },
      { name = "CORS_ALLOWED_ORIGINS", value = "https://${var.domain_name}" },
    ]
    secrets = [
      { name = "DJANGO_SECRET_KEY", valueFrom = aws_secretsmanager_secret.django_secret_key.arn },
      { name = "MYSQL_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "backend"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "celery" {
  family                   = "instagram-celery"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_backend.arn

  container_definitions = jsonencode([{
    name      = "celery"
    image     = var.backend_image
    essential = true
    command = [
      "celery", "-A", "config", "worker",
      "-Q", "fanout,celery", "-l", "info", "--concurrency", "4",
    ]
    environment = [
      { name = "DJANGO_DEBUG", value = "False" },
      { name = "MYSQL_HOST", value = aws_rds_cluster.main.endpoint },
      { name = "MYSQL_PORT", value = "3306" },
      { name = "MYSQL_USER", value = "instagram" },
      { name = "MYSQL_DATABASE", value = "instagram" },
      { name = "REDIS_URL", value = "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0" },
    ]
    secrets = [
      { name = "DJANGO_SECRET_KEY", valueFrom = aws_secretsmanager_secret.django_secret_key.arn },
      { name = "MYSQL_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.celery.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "celery"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "ai_worker" {
  family                   = "instagram-ai-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_ai_worker.arn

  container_definitions = jsonencode([{
    name         = "ai-worker"
    image        = var.ai_worker_image
    essential    = true
    portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
    environment = [
      { name = "DATABASE_URL", value = "mysql+pymysql://instagram_ro:${aws_rds_cluster.main.reader_endpoint}:3306/instagram" },
    ]
    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ai_worker.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ai-worker"
      }
    }
  }])
}

############
# Services
############

resource "aws_ecs_service" "frontend" {
  name            = "instagram-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_frontend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
}

resource "aws_ecs_service" "backend" {
  name            = "instagram-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_backend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
}

resource "aws_ecs_service" "celery" {
  name            = "instagram-celery"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.celery.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_celery.id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "ai_worker" {
  name            = "instagram-ai-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_worker.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_ai_worker.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ai_worker.arn
  }
}
