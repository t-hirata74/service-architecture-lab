terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # 本番想定の state 配置 (実行はしないので commented)
  # backend "s3" {
  #   bucket         = "zoom-architecture-lab-tfstate"
  #   key            = "zoom/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "zoom-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "zoom-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
