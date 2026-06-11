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
  #   bucket         = "linear-architecture-lab-tfstate"
  #   key            = "linear/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "linear-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "linear-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
