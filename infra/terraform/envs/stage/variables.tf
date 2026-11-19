variable "region" {
  type    = string
  default = "us-east-2"
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidr" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "admin_cidr" {
  type = string
}
