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

module "network" {
  source             = "../../modules/network"
  name               = "circleguard-${var.environment}"
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  az                 = "${var.region}a"
}

module "ci_server" {
  source            = "../../modules/ci-server"
  name              = "circleguard-${var.environment}"
  region            = var.region
  vpc_id            = module.network.vpc_id
  subnet_id         = module.network.public_subnet_id
  instance_type     = var.instance_type
  volume_size       = var.volume_size
  admin_cidr        = var.admin_cidr
  terraform_version = var.terraform_version
  iam_policy_json   = file("${path.module}/../../iam/terraform-policy.json")
}
