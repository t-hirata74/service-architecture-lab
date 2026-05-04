################################
# Security Groups
################################

resource "aws_security_group" "alb" {
  name        = "reddit-alb-sg"
  description = "ALB inbound 443/80, outbound any"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
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
  tags = { Name = "reddit-alb-sg" }
}

resource "aws_security_group" "frontend" {
  name        = "reddit-frontend-sg"
  description = "Next.js front, inbound from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
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
  tags = { Name = "reddit-frontend-sg" }
}

resource "aws_security_group" "backend" {
  name        = "reddit-backend-sg"
  description = "FastAPI backend (REST). Inbound from ALB only."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "reddit-backend-sg" }
}

resource "aws_security_group" "ai_worker" {
  name        = "reddit-ai-worker-sg"
  description = "FastAPI ai-worker, inbound from backend only (no public)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "reddit-ai-worker-sg" }
}

resource "aws_security_group" "rds" {
  name        = "reddit-rds-sg"
  description = "MySQL 3306, inbound from backend + ai-worker"
  vpc_id      = aws_vpc.main.id

  # ai-worker も Hot 再計算で書き込みアクセスする (ADR 0003)。
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id, aws_security_group.ai_worker.id]
  }
  tags = { Name = "reddit-rds-sg" }
}
