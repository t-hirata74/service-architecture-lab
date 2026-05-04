################################
# ALB
#
# Reddit は WebSocket を持たないので普通の REST 用 ALB。
# 認証 / 認可 (Bearer JWT) は backend が処理。frontend は SSR + 静的、
# backend (FastAPI) と同じドメインの path 振り分けで運用する。
################################

resource "aws_lb" "main" {
  name               = "reddit-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout = 60

  tags = { Name = "reddit-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "reddit-front-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200-399"
  }

  tags = { Name = "reddit-front-tg" }
}

resource "aws_lb_target_group" "backend" {
  name        = "reddit-back-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  # JWT bearer なので stickiness 不要。
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = { Name = "reddit-back-tg" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# REST は backend (/auth/*, /me, /r, /r/*, /posts/*, /comments/*, /health)、
# それ以外は frontend (Next.js) に流す。
resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [
        "/auth/*",
        "/me",
        "/r",
        "/r/*",
        "/posts/*",
        "/comments/*",
        "/health",
      ]
    }
  }
}
