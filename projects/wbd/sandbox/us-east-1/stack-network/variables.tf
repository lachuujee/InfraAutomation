variable "customer" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

locals {
  name_prefix = "${var.customer}_${var.environment}"
  common_tags = {
    Customer    = var.customer
    Environment = var.environment
  }
}
