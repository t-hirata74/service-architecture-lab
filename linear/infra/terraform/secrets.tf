################################
# Secrets Manager
#
# DATABASE_URL / JWT_SECRET / AI_INTERNAL_TOKEN
################################

resource "aws_secretsmanager_secret" "database_url" {
  name        = "linear/database_url"
  description = "MySQL DSN for NestJS backend (Prisma)"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  # Prisma 形式の DSN (mysql://user:pass@host:3306/db)
  secret_string = format(
    "mysql://%s:%s@%s:3306/%s",
    aws_db_instance.main.username,
    random_password.db.result,
    aws_db_instance.main.address,
    aws_db_instance.main.db_name,
  )
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "linear/jwt_secret"
  description = "HS256 signing key for user JWT (REST + /sync/ws で共通, ADR 0005)"
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt.result
}

resource "random_password" "ai_internal" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "ai_internal_token" {
  name        = "linear/ai_internal_token"
  description = "Shared secret between NestJS backend and ai-worker (X-Internal-Token)"
}

resource "aws_secretsmanager_secret_version" "ai_internal_token" {
  secret_id     = aws_secretsmanager_secret.ai_internal_token.id
  secret_string = random_password.ai_internal.result
}
