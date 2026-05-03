################################
# ALB
# - HTTPS (443) listener
# - default → frontend (Next.js)
# - /queries* と /api/* → backend (Rails)
# - ActionController::Live で SSE を流すため idle_timeout を長めに取る (ADR 0003)
################################

resource "aws_lb" "main" {
  name               = "perplexity-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = true
  # SSE long-lived stream のため 60s よりも長く取る (典型的な synthesize は数秒〜十数秒).
  idle_timeout = 120
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

resource "aws_lb_target_group" "frontend" {
  name        = "perplexity-tg-frontend"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

# Backend target group (REST + SSE)
# ADR 0003: SSE は long-lived HTTP. stickiness は不要だが、deregistration delay を
# 短くして SSE 切断時に確実に新規 task に切り替わるようにする.
resource "aws_lb_target_group" "backend" {
  name        = "perplexity-tg-backend"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

# /queries* と /me, /login, /create-account (rodauth-rails) を backend に振り分け
resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [
        "/queries",
        "/queries/*",
        "/health",
        "/login",
        "/logout",
        "/create-account",
        "/me",
      ]
    }
  }
}
