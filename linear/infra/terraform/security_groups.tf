################################
# Security Groups
################################

resource "aws_security_group" "alb" {
  name        = "linear-alb-sg"
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
  tags = { Name = "linear-alb-sg" }
}

resource "aws_security_group" "frontend" {
  name        = "linear-frontend-sg"
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
  tags = { Name = "linear-frontend-sg" }
}

resource "aws_security_group" "backend" {
  name        = "linear-backend-sg"
  description = "NestJS backend: REST + /sync/ws WebSocket. Inbound from ALB only."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3140
    to_port         = 3140
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "linear-backend-sg" }
}

resource "aws_security_group" "ai_worker" {
  name        = "linear-ai-worker-sg"
  description = "FastAPI ai-worker (triage / duplicates), inbound from backend only (no public)"
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
  tags = { Name = "linear-ai-worker-sg" }
}

resource "aws_security_group" "rds" {
  name        = "linear-rds-sg"
  description = "MySQL 3306, inbound from backend only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }
  tags = { Name = "linear-rds-sg" }
}
