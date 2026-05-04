variable "region" {
  description = "メインリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "環境名 (production / staging / dev)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

variable "domain_name" {
  type    = string
  default = "shopify.example.com"
}

variable "certificate_arn" {
  description = "ALB 用 ACM 証明書 ARN (リージョナル)"
  type        = string
  default     = "arn:aws:acm:ap-northeast-1:000000000000:certificate/REPLACE-ME"
}

variable "cloudfront_certificate_arn" {
  description = "CloudFront 用 ACM 証明書 ARN (us-east-1)"
  type        = string
  default     = "arn:aws:acm:us-east-1:000000000000:certificate/REPLACE-ME"
}

variable "frontend_image" {
  type    = string
  default = "ghcr.io/example/shopify-frontend:latest"
}

variable "backend_image" {
  type    = string
  default = "ghcr.io/example/shopify-backend:latest"
}

variable "ai_worker_image" {
  type    = string
  default = "ghcr.io/example/shopify-ai-worker:latest"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "hot_recompute_interval_seconds" {
  description = "ai-worker の Hot 再計算 interval (ADR 0003)"
  type        = number
  default     = 60
}
