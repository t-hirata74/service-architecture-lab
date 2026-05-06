output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB の DNS。Route 53 で var.domain_name を CNAME 設定する想定。"
}

output "rds_endpoint" {
  value       = aws_db_instance.main.address
  description = "Backend が DB_HOST に渡す MySQL エンドポイント。"
}

output "ai_worker_internal_dns" {
  value       = "ai-worker.zoom.local"
  description = "VPC 内から ai-worker を解決する Service Discovery DNS。"
}
