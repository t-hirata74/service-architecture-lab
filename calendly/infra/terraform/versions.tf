terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46"
    }
  }

  # 本番想定の state 配置 (本リポでは apply しないので commented)
  # backend "s3" {
  #   bucket         = "calendly-architecture-lab-tfstate"
  #   key            = "calendly/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "calendly-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "calendly-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
