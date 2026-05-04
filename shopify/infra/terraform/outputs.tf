output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB の DNS 名 (Route53 ALIAS の宛先)"
}

output "rds_endpoint" {
  value       = aws_db_instance.main.address
  description = "MySQL endpoint (private subnet 内のみアクセス可)"
}

output "ai_worker_service_dns" {
  value       = "ai-worker.shopify.internal"
  description = "ECS Service Discovery 経由の ai-worker 名"
}
