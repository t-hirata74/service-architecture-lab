################################
# Secrets Manager
################################

resource "aws_secretsmanager_secret" "django_secret_key" {
  name = "instagram/django-secret-key"
}

resource "aws_secretsmanager_secret_version" "django_secret_key" {
  secret_id     = aws_secretsmanager_secret.django_secret_key.id
  secret_string = "REPLACE-ME-AT-DEPLOY-TIME"
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "instagram/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}
