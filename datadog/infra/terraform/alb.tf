################################
# ALB
#
# 重要 (ADR 0003): matcher は **per-H3-cell goroutine + in-memory idle-driver
# registry** で、driver の WS 接続と同じプロセス内に閉じている。よって ALB 越しに
# desired_count>1 で並べると「driver が接続したタスク」と「rider の trip request が
# enqueue されたタスク」がズレた瞬間 offer が届かない。discord の per-guild Hub と
# 同じ単一プロセス制約だが、datadog は **rider(REST) と driver(WS) が別経路で同じ
# matcher に出会う**必要があるぶん制約が強い。
#   - REST (/trips など) は round-robin で良い
#   - driver WS /ws は idle_timeout を長めに取り接続を維持
#   - 本格的な水平スケールは派生 ADR (cell→task の consistent hashing or
#     共有メッセージバス) を実装してから ECS 配置を見直す
################################

resource "aws_lb" "main" {
  name               = "datadog-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout = 4000 # driver WebSocket を idle で殺さないため長めに (default 60s)

  tags = { Name = "datadog-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "datadog-front-tg"
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

  tags = { Name = "datadog-front-tg" }
}

resource "aws_lb_target_group" "backend" {
  name        = "datadog-back-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # driver WS の deregister 時、既存接続を打ち切らない猶予
  deregistration_delay = 120

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  # gorilla の ping/pong (protocol 層 heartbeat) があるので LB stickiness は不要。
  # cell→task の固定が必要になったら派生 ADR で consistent hashing を入れる。
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = { Name = "datadog-back-tg" }
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

# /ws は driver WebSocket、/auth/* /me /trips* /demand /healthz は REST。
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
        "/ws",
        "/auth/*",
        "/me",
        "/trips",
        "/trips/*",
        "/demand",
        "/healthz",
      ]
    }
  }
}
