################################
# ECS Cluster + 3 Services
# - Fargate (サーバ管理レスにすることで運用負荷を最小化)
# - 各サービス 2 task で AZ 分散
################################

resource "aws_ecs_cluster" "main" {
  name = "slack"

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

# Service Discovery (ai-worker への内部呼び出し用)
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "slack.internal"
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
  family                   = "slack-frontend"
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
      { name = "NEXT_PUBLIC_CABLE_URL", value = "wss://${var.domain_name}/cable" },
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
  family                   = "slack-backend"
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
    portMappings = [{ containerPort = 3000, hostPort = 3000, protocol = "tcp" }]
    environment = [
      { name = "RAILS_ENV", value = "production" },
      { name = "RAILS_LOG_TO_STDOUT", value = "1" },
      { name = "DB_HOST", value = aws_rds_cluster.main.endpoint },
      { name = "DB_PORT", value = "3306" },
      { name = "DB_USERNAME", value = "slack" },
      { name = "REDIS_URL", value = "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/1" },
      { name = "AI_WORKER_URL", value = "http://ai-worker.slack.internal:8000" },
      { name = "FRONTEND_ORIGIN", value = "https://${var.domain_name}" },
    ]
    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
      { name = "RAILS_MASTER_KEY", valueFrom = aws_secretsmanager_secret.rails_master_key.arn },
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

resource "aws_ecs_task_definition" "ai_worker" {
  family                   = "slack-ai-worker"
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
  name            = "slack-frontend"
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
  name            = "slack-backend"
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
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
}

resource "aws_ecs_service" "ai_worker" {
  name            = "slack-ai-worker"
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
