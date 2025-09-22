variable "customer"    { type = string }   # e.g., "WBD"
variable "environment" { type = string }   # e.g., "sandbox"
variable "region"      { type = string }   # e.g., "us-east-1"

# Defaults you can override via tfvars/CI
variable "instance_type" {
  type    = string
  default = "t3a.medium"
}

variable "root_volume_size_gb" {
  type    = number
  default = 8
}

# Latest Amazon Linux via public SSM Parameter (exists in every account)
variable "ami_ssm_parameter" {
  type    = string
  default = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Optional extra tags merged into all resources
variable "tags_extra" {
  type    = map(string)
  default = {}
}
