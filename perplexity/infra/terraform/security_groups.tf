################################
# Security Groups
# ALB <- 0.0.0.0/0 (443/80)
# ECS frontend / backend / ai-worker <- ALB / 内部
# RDS <- backend のみ
# OpenSearch <- ai-worker のみ (ADR 0002 本番想定: ベクタ retrieval は ai-worker から直接)
################################

resource "aws_security_group" "alb" {
  name        = "perplexity-alb"
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
  name        = "perplexity-ecs-frontend"
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
  name        = "perplexity-ecs-backend"
  description = "Rails task (ActionController::Live SSE)"
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
  name        = "perplexity-ecs-ai-worker"
  description = "FastAPI ai-worker"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From backend (Rails) /retrieve /extract /synthesize"
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
  name        = "perplexity-rds"
  description = "Aurora MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  ingress {
    description     = "MySQL from ai-worker (ADR 0001: ai-worker は DB read-only でアクセス)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_ai_worker.id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
}

# OpenSearch は本番想定で ai-worker からのみ HTTPS でアクセス (ADR 0002)
resource "aws_security_group" "opensearch" {
  name        = "perplexity-opensearch"
  description = "OpenSearch domain (vector + BM25 hybrid search)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from ai-worker"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_ai_worker.id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
}
