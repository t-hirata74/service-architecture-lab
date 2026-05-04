################################
# ALB
#
# 重要: ADR 0001「単一プロセス per-guild Hub」前提なので **WebSocket のセッション
# 継続性は load-balancer 越しに保てない**。ALB はそもそも sticky を使っても
# 「最初に upgrade したインスタンスに固定する」だけで、guild_id ベースの一貫
# ハッシュにはならない。ここでは:
#   - REST は普通に round-robin
#   - WebSocket /gateway は **target_group の deregistration_delay を長めに**
#     して、reconnect 時に同じインスタンスに戻りやすくはするが、shard 化を
#     したい場合は派生 ADR 0005 (Redis pub/sub multi-process) を実装する
################################

resource "aws_lb" "main" {
  name               = "discord-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout = 4000 # WebSocket 維持のため長めに (default 60s)

  tags = { Name = "discord-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "discord-front-tg"
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

  tags = { Name = "discord-front-tg" }
}

resource "aws_lb_target_group" "backend" {
  name        = "discord-back-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # WebSocket 後の deregister 時、既存接続を打ち切らない猶予
  deregistration_delay = 120

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  # WebSocket / app-layer heartbeat があるので LB stickiness は不要 (ADR 0001 / 0003)。
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = { Name = "discord-back-tg" }
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

# /gateway は WebSocket、/auth/* /me /guilds* /channels* /health は REST。
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
        "/gateway",
        "/auth/*",
        "/me",
        "/guilds",
        "/guilds/*",
        "/channels/*",
        "/health",
      ]
    }
  }
}
