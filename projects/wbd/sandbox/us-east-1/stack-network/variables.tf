variable "customer"    { type = string }
variable "environment" { type = string }
variable "region"      { type = string }

# IPAM pool (use this for auto-allocation). If set, leave vpc_cidr = "".
variable "ipam_pool_id" {
  type        = string
  default     = ""    # overridden in terraform.tfvars
  description = "IPAM pool ID (e.g., ipam-pool-xxxx). If set, VPC is allocated from this pool."
}

# Fallback: fixed VPC CIDR (set this OR ipam_pool_id, not both).
variable "vpc_cidr" {
  type        = string
  default     = ""
  description = "Fixed VPC CIDR (leave empty to use IPAM)."
}

# Size to allocate from IPAM pool ( /20 gives room for 6x /23 + 2x /28 )
variable "ipam_netmask_length" {
  type    = number
  default = 20
}

# Exactly two AZs used for the layout
variable "azs" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  description = "Two AZs for subnet distribution."
}

# Flow logs retention
variable "flow_logs_retention_days" {
  type    = number
  default = 30
}

# Extra tags (merged into all resources)
variable "tags_extra" {
  type    = map(string)
  default = {}
}

locals {
  name_prefix = "${var.customer}_${var.environment}"
  common_tags = merge(
    {
      Customer    = var.customer
      Environment = var.environment
    },
    var.tags_extra
  )
}
