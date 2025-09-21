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

# 3) Secrets Manager secret
#    - No kms_key_id provided => uses AWS-managed KMS key for Secrets Manager
#    - recovery_window_in_days must be 7–30 (AWS limit) — set to 30 (max/safest)
resource "aws_secretsmanager_secret" "pk" {
  name                    = "${local.key_name}-private-key"
  recovery_window_in_days = 30
  tags                    = local.common_tags
}

# 4) Store PEM string in the secret
resource "aws_secretsmanager_secret_version" "pkv" {
  secret_id     = aws_secretsmanager_secret.pk.id
  secret_string = tls_private_key.this.private_key_pem
}
