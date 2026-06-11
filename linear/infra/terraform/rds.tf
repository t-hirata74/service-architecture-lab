################################
# RDS MySQL (single writer)
#
# ai-worker は DB を読まない (backend が body で座標 / cell を渡す, ADR 0004) ため
# reader endpoint は不要。Aurora ではなく標準 MySQL で十分 (本番化時に判断)。
################################

resource "aws_db_subnet_group" "main" {
  name       = "linear-db-subnet"
  subnet_ids = aws_subnet.private_data[*].id
  tags       = { Name = "linear-db-subnet" }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "main" {
  identifier                = "linear-mysql"
  engine                    = "mysql"
  engine_version            = "8.0"
  instance_class            = var.rds_instance_class
  allocated_storage         = 50
  storage_type              = "gp3"
  storage_encrypted         = true
  db_name                   = "linear"
  username                  = "linear"
  password                  = random_password.db.result
  db_subnet_group_name      = aws_db_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  multi_az                  = true
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "linear-mysql-final"

  tags = { Name = "linear-mysql" }
}
