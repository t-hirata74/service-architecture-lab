################################
# Secrets Manager
#
# JWT_SECRET / DATABASE_URL / AI_INTERNAL_TOKEN
################################

resource "aws_secretsmanager_secret" "database_url" {
  name        = "reddit/database_url"
  description = "MySQL URL for FastAPI backend + ai-worker (SQLAlchemy aiomysql)"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  secret_string = format(
    "mysql+aiomysql://%s:%s@%s:3306/%s",
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
  name        = "reddit/jwt_secret"
  description = "HS256 signing key for user JWT (ADR 0004)"
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
  name        = "reddit/ai_internal_token"
  description = "Shared secret between backend and ai-worker (X-Internal-Token)"
}

resource "aws_secretsmanager_secret_version" "ai_internal_token" {
  secret_id     = aws_secretsmanager_secret.ai_internal_token.id
  secret_string = random_password.ai_internal.result
}
