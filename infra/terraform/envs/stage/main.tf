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
    key            = "envs/stage/terraform.tfstate"
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

module "network" {
  source             = "../../modules/network"
  name               = "circleguard-${var.environment}"
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  az                 = "${var.region}a"
}

module "compute" {
  source        = "../../modules/compute"
  name          = "circleguard-${var.environment}"
  environment   = var.environment
  region        = var.region
  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.public_subnet_id
  instance_type = var.instance_type
  admin_cidr    = var.admin_cidr
}

module "storage" {
  source = "../../modules/storage"
  name   = "circleguard-${var.environment}"
}

module "observability" {
  source      = "../../modules/observability"
  name        = "circleguard-${var.environment}"
  environment = var.environment
  instance_id = module.compute.instance_id
}
