################################
# ALB
#
# 重要 (ADR 0005): WS room は backend プロセス内の in-memory Map なので、
# desired_count>1 で並べると「mutation を受けたタスク」と「WS が繋がっている
# タスク」がズレた接続へ op push が届かない。ただし linear の push は
# at-most-once のヒントで、真実は sync log (ADR 0002) — 届かなくても client が
# delta で自己修復するため、欠けるのはリアルタイム性だけで正しさは壊れない。
#   - REST (/mutations, /sync/bootstrap|delta) は round-robin で良い
#   - WS /sync/ws は idle_timeout を長めに取り接続を維持 (server ping 30s あり)
#   - 完全な fan-out を保ったまま水平化するには Redis pub/sub 等の中継を
#     派生 ADR で入れてから desired_count を上げる
################################

resource "aws_lb" "main" {
  name               = "linear-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout = 4000 # /sync/ws の WebSocket を idle で殺さないため長めに (default 60s)

  tags = { Name = "linear-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "linear-front-tg"
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

  tags = { Name = "linear-front-tg" }
}

resource "aws_lb_target_group" "backend" {
  name        = "linear-back-tg"
  port        = 3140
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # WS の deregister 時、既存接続を打ち切らない猶予 (client は再接続 → delta で復帰)
  deregistration_delay = 120

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  # server ping/pong (RealtimeService 30s heartbeat) があるので LB stickiness は不要。
  # desired_count=1 のうちはそもそも対象が 1 台 (ecs.tf の注記)。
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = { Name = "linear-back-tg" }
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

# /sync/ws は WebSocket、/auth /mutations /sync /ai /workspaces は REST。
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
        "/mutations",
        "/sync/*",
        "/ai/*",
        "/workspaces",
        "/health",
      ]
    }
  }
}
