output "alb_dns_name" {
  description = "ALB の DNS 名 (CloudFront origin に紐付けるとき使う)"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain" {
  description = "CloudFront のドメイン (DNS で var.domain_name → ここへ向ける)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "rds_writer_endpoint" {
  description = "Aurora MySQL writer endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "rds_reader_endpoint" {
  description = "Aurora MySQL reader endpoint (ai-worker 用)"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint (Celery broker)"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "images_bucket" {
  description = "画像保管 S3 bucket"
  value       = aws_s3_bucket.images.bucket
}
