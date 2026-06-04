resource "aws_lb" "main" {
  name               = "figma-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "figma-alb" }
}

resource "aws_lb_target_group" "backend" {
  name        = "figma-backend-tg"
  port        = 3120
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/up"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "figma-frontend-tg"
  port        = 3125
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
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

# /event_types* / /availability_rules* / /busy_periods* / /bookings* / /public/* /
# rodauth path 群 (/login, /create-account 等) は backend に振る。
# それ以外は frontend (Next.js SSR) で受ける。
resource "aws_lb_listener_rule" "backend_paths" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = [
        "/event_types*", "/availability_rules*", "/busy_periods*", "/bookings*",
        "/public/*",
        "/login", "/logout", "/create-account", "/change-password", "/close-account",
        "/up",
      ]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
