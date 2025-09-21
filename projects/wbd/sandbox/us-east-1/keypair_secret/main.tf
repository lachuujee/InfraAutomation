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

  lifecycle {
    prevent_destroy = true
  }
}

# 3) Secrets Manager secret (uses AWS-managed KMS by default)
#    recovery_window_in_days must be 7–30; using 30 (max)
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
