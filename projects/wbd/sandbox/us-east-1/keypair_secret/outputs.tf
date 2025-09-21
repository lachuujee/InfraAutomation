output "key_name"    { value = aws_key_pair.this.key_name }
output "secret_name" { value = aws_secretsmanager_secret.pk.name }
output "secret_arn"  { value = aws_secretsmanager_secret.pk.arn }
