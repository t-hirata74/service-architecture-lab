terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47"
    }
  }

  # 本番想定の state 配置 (本リポでは apply しないので commented)
  # backend "s3" {
  #   bucket         = "figma-architecture-lab-tfstate"
  #   key            = "figma/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "figma-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "figma-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
