terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "circleguard-tfstate-a00400179"
    key            = "envs/tools/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "circleguard-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "circleguard"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

module "registry" {
  source       = "../../modules/registry"
  repositories = var.repositories
}
