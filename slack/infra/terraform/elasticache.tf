################################
# ElastiCache Redis (ADR 0001 の ActionCable Pub/Sub 基盤)
# - cluster mode disabled の replication group (1 primary + 1 replica)
# - スケールアウトが必要になった段階で cluster mode に切替
################################

resource "aws_elasticache_subnet_group" "main" {
  name       = "slack-redis-subnets"
  subnet_ids = aws_subnet.private_data[*].id
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "slack-redis"
  description                = "ActionCable Pub/Sub for Slack"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.redis_node_type
  num_cache_clusters         = 2
  parameter_group_name       = "default.redis7"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.redis.id]
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # ActionCable client が TLS 非対応の場合は false

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slowlog.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }
}
