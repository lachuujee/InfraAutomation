variable "customer"    { type = string }    # e.g., "WBD"
variable "environment" { type = string }    # e.g., "sandbox"
variable "region"      { type = string }    # e.g., "us-east-1"

# Optional override; else we'll use <customer>_<environment>-admin
variable "key_name_override" { type = string, default = null }

# Crypto
variable "algorithm"  { type = string, default = "RSA" }  # or "ED25519"
variable "rsa_bits"   { type = number, default = 4096 }

# Secrets Manager / KMS
variable "create_kms_key" { type = bool,  default = false }  # true => create dedicated CMK
variable "kms_key_id"     { type = string, default = null }  # or use an existing CMK ARN

# Extra tags similar to stack-network
variable "tags_extra" { type = map(string), default = {} }

locals {
  name_prefix = "${var.customer}_${var.environment}"                  # "WBD_sandbox"
  key_name    = coalesce(var.key_name_override, "${local.name_prefix}-admin")

  common_tags = merge(
    { Customer = var.customer, Environment = var.environment },
    var.tags_extra
  )
}
