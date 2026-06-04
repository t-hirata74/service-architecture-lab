################################
# Security Groups
################################

resource "aws_security_group" "alb" {
  name        = "datadog-alb-sg"
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
  tags = { Name = "datadog-alb-sg" }
}

resource "aws_security_group" "frontend" {
  name        = "datadog-frontend-sg"
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
  tags = { Name = "datadog-frontend-sg" }
}

resource "aws_security_group" "backend" {
  name        = "datadog-backend-sg"
  description = "Go dispatch: REST + driver WebSocket. Inbound from ALB only."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "datadog-backend-sg" }
}

resource "aws_security_group" "ai_worker" {
  name        = "datadog-ai-worker-sg"
  description = "FastAPI ai-worker (ETA / demand), inbound from backend only (no public)"
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
  tags = { Name = "datadog-ai-worker-sg" }
}

resource "aws_security_group" "rds" {
  name        = "datadog-rds-sg"
  description = "MySQL 3306, inbound from backend only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }
  tags = { Name = "datadog-rds-sg" }
}
