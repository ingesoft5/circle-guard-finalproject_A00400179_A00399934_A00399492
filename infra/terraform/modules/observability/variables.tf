variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_id" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "cpu_threshold" {
  type    = number
  default = 80
}
