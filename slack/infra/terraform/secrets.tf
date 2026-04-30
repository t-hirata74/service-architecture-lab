################################
# Secrets Manager
# - DB password (Aurora master) と Rails master key を保管
# - 値は terraform state に乗らないようランダム生成 + 後段の更新は手動 / SecretsManager UI
################################

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "_-+="
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "slack/aurora/master-password"
  description             = "Aurora MySQL master password (slack)"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Rails master key は手動投入想定 (CI/CD で apply した上でローテ可能)
resource "aws_secretsmanager_secret" "rails_master_key" {
  name                    = "slack/rails/master-key"
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
