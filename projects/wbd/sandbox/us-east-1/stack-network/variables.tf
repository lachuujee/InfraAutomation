variable "customer"    { type = string }
variable "environment" { type = string }
variable "region"      { type = string }

# Use this IPAM pool for VPC auto-allocation
variable "ipam_pool_id" {
  type        = string
  description = "IPAM pool ID (e.g., ipam-pool-xxxxxxxx)."
}

# Netmask length requested from IPAM ( /20 fits 6x /23 + 2x /28 )
variable "vpc_netmask_length" {
  type    = number
  default = 20
}

# Exactly two AZs to spread subnets across
variable "azs" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  description = "Two AZs for this layout."
}

# Flow Logs retention
variable "flow_logs_retention_days" {
  type    = number
  default = 30
}

# Optional extra tags merged into all resources
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
