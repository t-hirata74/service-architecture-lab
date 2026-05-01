terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 本番運用想定の state 配置（実行はしないので commented）
  # backend "s3" {
  #   bucket         = "github-architecture-lab-tfstate"
  #   key            = "github/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "github-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "github-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "github-architecture-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
