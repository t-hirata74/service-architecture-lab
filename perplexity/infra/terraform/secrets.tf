################################
# Secrets Manager
# - DB password (Aurora master)
# - Rails master key (config/credentials.yml.enc 復号用)
# - rodauth JWT secret (ADR 0007: rodauth-rails JWT bearer)
# - OpenSearch master user password
################################

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "_-+="
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "perplexity/aurora/master-password"
  description             = "Aurora MySQL master password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "rails_master_key" {
  name                    = "perplexity/rails/master-key"
  description             = "Rails 8 credentials master key"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "rails_master_key" {
  secret_id     = aws_secretsmanager_secret.rails_master_key.id
  secret_string = "REPLACE-ME-AT-FIRST-APPLY"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "random_password" "rodauth_jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "rodauth_jwt_secret" {
  name                    = "perplexity/rodauth/jwt-secret"
  description             = "rodauth-rails JWT signing secret (ADR 0007)"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "rodauth_jwt_secret" {
  secret_id     = aws_secretsmanager_secret.rodauth_jwt_secret.id
  secret_string = random_password.rodauth_jwt_secret.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "random_password" "opensearch_master_password" {
  length           = 32
  special          = true
  override_special = "_-+="
}

resource "aws_secretsmanager_secret" "opensearch_master_password" {
  name                    = "perplexity/opensearch/master-password"
  description             = "OpenSearch internal master user password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "opensearch_master_password" {
  secret_id     = aws_secretsmanager_secret.opensearch_master_password.id
  secret_string = random_password.opensearch_master_password.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}
