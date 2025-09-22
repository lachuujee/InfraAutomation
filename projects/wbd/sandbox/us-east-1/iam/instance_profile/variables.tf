variable "customer"    { type = string }   # e.g., "WBD"
variable "environment" { type = string }   # e.g., "sandbox"
variable "region"      { type = string }   # e.g., "us-east-1"

# Extra tags merged into all resources (same idea as VPC)
variable "tags_extra" {
  type    = map(string)
  default = {}
}

# Optional: allow adding/removing managed policies without editing code
variable "managed_policy_arns" {
  type    = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
}

# Optional inline policies: { "policy-name" = json }
variable "inline_policies" {
  type    = map(string)
  default = {}
}

locals {
  # Build names from customer/env (no name_prefix variable anywhere)
  name_prefix  = "${var.customer}_${var.environment}"         # e.g., WBD_sandbox
  role_name    = "${local.name_prefix}-ec2-role"
  profile_name = "${local.name_prefix}-ec2-profile"

  common_tags = merge(
    { Customer = var.customer, Environment = var.environment },
    var.tags_extra
  )
}
