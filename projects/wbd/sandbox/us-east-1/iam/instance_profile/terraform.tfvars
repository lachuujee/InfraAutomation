customer    = "WBD"
environment = "sandbox"
region      = "us-east-1"

# Optional extra tags for all IAM resources in this stack
# tags_extra = { Owner = "you", CostCenter = "poc" }

# Optional: override managed policies or add inline_policies if needed
# managed_policy_arns = [
#   "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
#   "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# ]
# inline_policies = {
#   "s3-minimal-object-rw" = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect   = "Allow",
#       Action   = ["s3:GetObject", "s3:PutObject"],
#       Resource = "arn:aws:s3:::*/*"
#     }]
#   })
# }
