variable "region" {
  description = "メインリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "domain_name" {
  type    = string
  default = "zoom.example.com"
}

variable "certificate_arn" {
  description = "ALB 用 ACM 証明書 ARN (リージョナル)"
  type        = string
  default     = "arn:aws:acm:ap-northeast-1:000000000000:certificate/REPLACE-ME"
}

variable "backend_image" {
  type    = string
  default = "ghcr.io/example/zoom-backend:latest"
}

variable "frontend_image" {
  type    = string
  default = "ghcr.io/example/zoom-frontend:latest"
}

variable "ai_worker_image" {
  type    = string
  default = "ghcr.io/example/zoom-ai-worker:latest"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "internal_ingress_token_secret_name" {
  description = "Secrets Manager に登録する内部 ingress 共有トークン (ADR 0003)"
  type        = string
  default     = "zoom/internal-ingress-token"
}

variable "rodauth_jwt_secret_name" {
  description = "Secrets Manager に登録する rodauth JWT 署名鍵"
  type        = string
  default     = "zoom/rodauth-jwt"
}
