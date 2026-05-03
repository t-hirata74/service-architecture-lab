################################
# Aurora MySQL (ADR 0002 / 0006)
# - 3-AZ にまたがる subnet group
# - writer 1 + reader 1 で開始
# - sources / chunks / queries / answers / citations を保持 (Phase 2-3 の schema)
# - chunks.embedding は LONGBLOB で保存 (擬似 encoder の精度より「データ管理」を学ぶ目的, ADR 0002).
#   本番化時は OpenSearch に knn_vector で持つ想定 (opensearch.tf 参照).
################################

resource "aws_db_subnet_group" "main" {
  name       = "perplexity-db-subnets"
  subnet_ids = aws_subnet.private_data[*].id

  tags = { Name = "perplexity-db-subnets" }
}

resource "aws_rds_cluster" "main" {
  cluster_identifier        = "perplexity-aurora"
  engine                    = "aurora-mysql"
  engine_version            = "8.0.mysql_aurora.3.05.2"
  database_name             = "perplexity_production"
  master_username           = "perplexity"
  master_password           = aws_secretsmanager_secret_version.db_password.secret_string
  db_subnet_group_name      = aws_db_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  backup_retention_period   = 7
  preferred_backup_window   = "17:00-18:00"
  storage_encrypted         = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "perplexity-aurora-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4
  }

  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
}

resource "aws_rds_cluster_instance" "writer" {
  identifier          = "perplexity-aurora-writer"
  cluster_identifier  = aws_rds_cluster.main.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version
  publicly_accessible = false
}

resource "aws_rds_cluster_instance" "reader" {
  identifier          = "perplexity-aurora-reader-1"
  cluster_identifier  = aws_rds_cluster.main.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version
  publicly_accessible = false
}
