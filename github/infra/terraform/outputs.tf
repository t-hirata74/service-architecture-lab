output "alb_dns_name" {
  description = "ALB の DNS 名 (Route53 ALIAS の向け先)"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront ディストリビューションのドメイン"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "rds_writer_endpoint" {
  description = "Aurora writer エンドポイント"
  value       = aws_rds_cluster.main.endpoint
}

output "rds_reader_endpoint" {
  description = "Aurora reader エンドポイント"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "ecs_cluster_name" {
  description = "ECS クラスタ名"
  value       = aws_ecs_cluster.main.name
}
