terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
    tls = { source = "hashicorp/tls", version = ">= 4.0" }
  }
}

# 1) Generate private/public key (no .pem written to disk)
resource "tls_private_key" "this" {
  algorithm = var.algorithm
  rsa_bits  = var.algorithm == "RSA" ? var.rsa_bits : null
}

# 2) Register public key in EC2
resource "aws_key_pair" "this" {
  key_name   = local.key_name
  public_key = tls_private_key.this.public_key_openssh
  tags       = local.common_tags

  lifecycle { prevent_destroy = true }
}

# 3) Optional KMS CMK (only if you want a customer-managed key)
resource "aws_kms_key" "this" {
  count                    = var.create_kms_key && var.kms_key_id == null ? 1 : 0
  description              = "CMK for ${local.key_name} secret"
  enable_key_rotation      = true
  deletion_window_in_days  = 7
  tags                     = local.common_tags
}

resource "aws_kms_alias" "this" {
  count         = length(aws_kms_key.this) == 1 ? 1 : 0
  name          = "alias/${local.key_name}-secrets"
  target_key_id = aws_kms_key.this[0].key_id
}

locals {
  chosen_kms = var.kms_key_id != null ? var.kms_key_id :
               (length(aws_kms_key.this) == 1 ? aws_kms_key.this[0].arn : null)
}

# 4) Secrets Manager secret (AWS-managed KMS by default)
resource "aws_secretsmanager_secret" "pk" {
  name       = "${local.key_name}-private-key"
  kms_key_id = local.chosen_kms
  tags       = local.common_tags
  recovery_window_in_days = 7
}

# 5) Store PEM string in the secret
resource "aws_secretsmanager_secret_version" "pkv" {
  secret_id     = aws_secretsmanager_secret.pk.id
  secret_string = tls_private_key.this.private_key_pem
}
