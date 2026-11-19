variable "region" {
  type    = string
  default = "us-east-2"
}

variable "environment" {
  type = string
}

variable "repositories" {
  type = list(string)
}
