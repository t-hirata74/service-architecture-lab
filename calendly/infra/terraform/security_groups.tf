resource "aws_security_group" "alb" {
  name        = "calendly-alb-sg"
  description = "ALB ingress (HTTPS only)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "calendly-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "calendly-ecs-sg"
  description = "ECS tasks (frontend / backend / ai-worker / queue worker)"
  vpc_id      = aws_vpc.main.id

  # ALB → backend (3100) / frontend (3105)
  ingress {
    description     = "from ALB to backend"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description     = "from ALB to frontend"
    from_port       = 3105
    to_port         = 3105
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # backend → ai-worker (内部 ingress / Bearer token / /recommend_slots)
  ingress {
    description = "internal ingress to ai-worker"
    from_port   = 8090
    to_port     = 8090
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "calendly-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "calendly-rds-sg"
  description = "MySQL only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from ECS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "calendly-rds-sg" }
}
