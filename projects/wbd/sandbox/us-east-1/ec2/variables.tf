variable "customer"    { type = string }
variable "environment" { type = string }
variable "region"      { type = string }

# Instance settings
variable "instance_type" {
  type    = string
  default = "t3a.medium"
}

variable "root_volume_size_gb" {
  type    = number
  default = 8
}

# Amazon Linux via SSM parameter (override if you want AL2, etc.)
# Common values:
#  - "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
#  - "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
variable "ami_ssm_parameter" {
  type    = string
  default = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Use key pair from keypair_secret stack? (no SSH opened regardless)
variable "use_key_pair" {
  type    = bool
  default = true
}

# If VPC outputs don't match our guesses, you can override the subnet directly
variable "subnet_id_override" {
  type      = string
  default   = null
  nullable  = true
}

# Extra tags
variable "tags_extra" {
  type    = map(string)
  default = {}
}

locals {
  name_prefix = "${var.customer}_${var.environment}"                 # e.g., WBD_sandbox
  ec2_name    = "${local.name_prefix}-ec2-app"                       # instance name
  sg_name     = "${local.name_prefix}-ec2-app-sg"                    # sg name ends with -sg

  common_tags = merge(
    { Customer = var.customer, Environment = var.environment },
    var.tags_extra
  )
}
