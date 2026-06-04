terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 本番想定の state 配置 (実行はしないので commented)
  # backend "s3" {
  #   bucket         = "datadog-architecture-lab-tfstate"
  #   key            = "datadog/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "datadog-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "datadog-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
