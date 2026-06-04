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
  default = "datadog.example.com"
}

variable "certificate_arn" {
  description = "ALB 用 ACM 証明書 ARN (リージョナル)"
  type        = string
  default     = "arn:aws:acm:ap-northeast-1:000000000000:certificate/REPLACE-ME"
}

variable "frontend_image" {
  type    = string
  default = "ghcr.io/example/datadog-frontend:latest"
}

variable "backend_image" {
  type    = string
  default = "ghcr.io/example/datadog-backend:latest"
}

variable "ai_worker_image" {
  type    = string
  default = "ghcr.io/example/datadog-ai-worker:latest"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "h3_resolution" {
  description = "H3 cell 解像度 (ADR 0001: 都市内ライドは 9, edge ~174m)"
  type        = number
  default     = 9
}
