################################
# ElastiCache Redis: Celery broker + 結果 backend
# ADR 0001: fan-out task / backfill / unfollow remove / soft delete propagation
# が Redis を broker として走る。
################################

resource "aws_elasticache_subnet_group" "main" {
  name       = "instagram-redis-subnet-group"
  subnet_ids = aws_subnet.private_data[*].id
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "instagram-redis"
  description                = "Celery broker / 結果 backend"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.elasticache_node_type
  num_cache_clusters         = 2
  parameter_group_name       = "default.redis7"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.elasticache.id]
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  # ADR 0001 の派生課題として、本番では auth_token + transit encryption を
  # 有効化する余地を残す (ローカル完結方針との対比として)。
}
