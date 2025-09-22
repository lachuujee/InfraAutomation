customer    = "WBD"
environment = "sandbox"
region      = "us-east-1"

# Optional overrides (uncomment only if you want to change defaults)
# role_name_override    = "WBD_sandbox-ec2-role"
# profile_name_override = "WBD_sandbox-ec2-profile"

# Managed policies to attach (defaults already include SSM + CloudWatch Agent)
# managed_policy_arns = [
#   "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
#   "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# ]

# Inline policies as JSON strings, e.g.:
# inline_policies = {
#   "extra-permissions" = jsonencode({
#     Version   = "2012-10-17",
#     Statement = [{
#       Effect   = "Allow",
#       Action   = ["logs:CreateLogGroup"],
#       Resource = "*"
#     }]
#   })
# }

tags_extra = {
  Project     = "automation-demo"
  Owner       = "user123"
}
