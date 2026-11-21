variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "m7i-flex.large"
}

variable "volume_size" {
  type    = number
  default = 60
}

variable "admin_cidr" {
  type = string
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "terraform_version" {
  type    = string
  default = "1.17.2"
}

variable "iam_policy_json" {
  type = string
}
