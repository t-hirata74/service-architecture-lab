################################
# Security Groups
# ALB <- 0.0.0.0/0 (443/80)
# ECS (frontend / backend / ai-worker) <- ALB / 自身経由
# RDS / Redis <- ECS のみ
################################

resource "aws_security_group" "alb" {
  name        = "slack-alb"
  description = "Public-facing ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_frontend" {
  name        = "slack-ecs-frontend"
  description = "Next.js task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_backend" {
  name        = "slack-ecs-backend"
  description = "Rails task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_ai_worker" {
  name        = "slack-ecs-ai-worker"
  description = "FastAPI ai-worker"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From backend (Rails)"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "slack-rds"
  description = "Aurora MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
}

resource "aws_security_group" "redis" {
  name        = "slack-redis"
  description = "ElastiCache Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from backend (ActionCable Pub/Sub)"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
}
