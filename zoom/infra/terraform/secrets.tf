resource "aws_secretsmanager_secret" "internal_ingress_token" {
  name        = var.internal_ingress_token_secret_name
  description = "ADR 0003: backend → ai-worker の内部 ingress 共有 Bearer token"
}

resource "aws_secretsmanager_secret" "rodauth_jwt" {
  name        = var.rodauth_jwt_secret_name
  description = "rodauth JWT 署名鍵 (HS256)"
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "zoom/rds-password"
  description = "MySQL master password"
}
