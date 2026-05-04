################################
# RDS MySQL (single writer)
#
# instagram と違い ai-worker が DB を読まないため reader endpoint は不要。
# Aurora ではなく標準 MySQL で十分 (本番化時に判断、Aurora にしたい場合は派生)。
################################

resource "aws_db_subnet_group" "main" {
  name       = "reddit-db-subnet"
  subnet_ids = aws_subnet.private_data[*].id
  tags       = { Name = "reddit-db-subnet" }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "main" {
  identifier                = "reddit-mysql"
  engine                    = "mysql"
  engine_version            = "8.0"
  instance_class            = var.rds_instance_class
  allocated_storage         = 50
  storage_type              = "gp3"
  storage_encrypted         = true
  db_name                   = "reddit"
  username                  = "reddit"
  password                  = random_password.db.result
  db_subnet_group_name      = aws_db_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  multi_az                  = true
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "reddit-mysql-final"

  tags = { Name = "reddit-mysql" }
}
