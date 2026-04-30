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
  description = "VPC の CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "利用する AZ のリスト (3-AZ HA を想定)"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

variable "domain_name" {
  description = "ALB / CloudFront に紐付けるホスト名"
  type        = string
  default     = "chat.example.com"
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
  description = "Next.js frontend コンテナイメージ"
  type        = string
  default     = "ghcr.io/example/slack-frontend:latest"
}

variable "backend_image" {
  description = "Rails backend コンテナイメージ"
  type        = string
  default     = "ghcr.io/example/slack-backend:latest"
}

variable "ai_worker_image" {
  description = "ai-worker (FastAPI) コンテナイメージ"
  type        = string
  default     = "ghcr.io/example/slack-ai-worker:latest"
}

variable "rds_instance_class" {
  description = "Aurora MySQL のインスタンスクラス"
  type        = string
  default     = "db.t3.medium"
}

variable "redis_node_type" {
  description = "ElastiCache Redis のノードタイプ"
  type        = string
  default     = "cache.t3.micro"
}
