################################
# Aurora MySQL: writer + reader
# ai-worker は reader_endpoint + read-only ユーザを使う (ADR 0001 の責務分離を
# 本番でも DB 層で担保する)
################################

resource "aws_db_subnet_group" "main" {
  name       = "instagram-db-subnet-group"
  subnet_ids = aws_subnet.private_data[*].id

  tags = { Name = "instagram-db-subnet-group" }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_rds_cluster" "main" {
  cluster_identifier      = "instagram"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.05.2"
  database_name           = "instagram"
  master_username         = "instagram"
  master_password         = random_password.db.result
  backup_retention_period = 7
  preferred_backup_window = "16:00-17:00" # JST 01:00-02:00

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted         = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "instagram-final"
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "instagram-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
}

resource "aws_rds_cluster_instance" "reader" {
  identifier         = "instagram-reader"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
}
