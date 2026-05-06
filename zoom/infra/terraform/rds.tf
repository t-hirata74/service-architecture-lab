resource "aws_db_subnet_group" "main" {
  name       = "zoom-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "zoom-db-subnet" }
}

resource "aws_db_instance" "main" {
  identifier                    = "zoom-mysql"
  engine                        = "mysql"
  engine_version                = "8.0"
  instance_class                = var.rds_instance_class
  allocated_storage             = 50
  max_allocated_storage         = 200
  storage_type                  = "gp3"
  storage_encrypted             = true
  db_name                       = "zoom_production"
  username                      = "zoom_admin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = null
  db_subnet_group_name          = aws_db_subnet_group.main.name
  vpc_security_group_ids        = [aws_security_group.rds.id]
  multi_az                      = true
  backup_retention_period       = 7
  deletion_protection           = true
  skip_final_snapshot           = false
  final_snapshot_identifier     = "zoom-mysql-final"

  # Solid Queue を同居させる single-DB 方針 (CLAUDE.md / ADR 0001)。
  # スループット要求が上がったら queue 専用 RDS を分離するのが次の一手。
  parameter_group_name = aws_db_parameter_group.main.name

  tags = { Name = "zoom-mysql" }
}

resource "aws_db_parameter_group" "main" {
  name   = "zoom-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
}
