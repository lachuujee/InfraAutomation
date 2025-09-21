variable "customer" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

# Optional override; else we use <customer>_<environment>-admin
variable "key_name_override" {
  type    = string
  default = null
}

# Crypto
variable "algorithm" {
  type    = string
  default = "RSA" # or "ED25519"
  validation {
    condition     = contains(["RSA", "ED25519"], var.algorithm)
    error_message = "algorithm must be RSA or ED25519."
  }
}

variable "rsa_bits" {
  type    = number
  default = 4096
}

# Extra tags merged into all resources
variable "tags_extra" {
  type    = map(string)
  default = {}
}

locals {
  # e.g., WBD_sandbox
  name_prefix = "${var.customer}_${var.environment}"

  # e.g., WBD_sandbox-admin (unless overridden)
  key_name = coalesce(var.key_name_override, "${local.name_prefix}-admin")

  common_tags = merge(
    {
      Customer    = var.customer
      Environment = var.environment
    },
    var.tags_extra
  )
}
