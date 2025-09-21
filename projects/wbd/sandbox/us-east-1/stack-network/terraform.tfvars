customer    = "WBD"
environment = "sandbox"
region      = "us-east-1"

# Your actual IPAM pool ID:
ipam_pool_id        = "ipam-pool-00c5cf0fe44301219"

# Leave default unless you want a different VPC size
vpc_netmask_length  = 20

azs                      = ["us-east-1a", "us-east-1b"]
flow_logs_retention_days = 30

# Optional extra tags for *all* resources
# tags_extra = { Owner = "you", CostCenter = "poc" }
