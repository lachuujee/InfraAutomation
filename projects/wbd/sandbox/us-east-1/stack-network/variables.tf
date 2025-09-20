variable "customer"    { type = string }                 # "WBD"
variable "environment" { type = string }                 # "sandbox" | "prod"
variable "region"      { type = string }                 # "us-east-1"
variable "vpc_cidr"    { type = string, default = "10.20.0.0/16" }

locals {
  name_prefix = "${var.customer}_${var.environment}"
  common_tags = {
    Customer    = var.customer
    Environment = var.environment
  }
}
