variable "customer"    { type = string }
variable "environment" { type = string }
variable "region"      { type = string }

# Defaults you can override
variable "instance_type" {
  type    = string
  default = "t3a.medium"
}

variable "root_volume_size_gb" {
  type    = number
  default = 8
}

# Latest Amazon Linux via SSM Parameter (x86_64, AL2023)
variable "ami_ssm_parameter" {
  type    = string
  default = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Optional: force a specific subnet instead of auto-pick from VPC outputs
variable "subnet_id_override" {
  type      = string
  default   = null
  nullable  = true
}

# Optional extra tags merged into all resources
variable "tags_extra" {
  type    = map(string)
  default = {}
}

locals {
  name_prefix = "${var.customer}_${var.environment}"   # e.g., WBD_sandbox
  ec2_name    = "${local.name_prefix}-ec2-app"         # instance Name tag

  common_tags = merge(
    { Customer = var.customer, Environment = var.environment },
    var.tags_extra
  )
}
