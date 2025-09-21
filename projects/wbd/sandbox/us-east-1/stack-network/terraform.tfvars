# Core
customer    = "WBD"
environment = "sandbox"
region      = "us-east-1"

# Use your IPAM pool (recommended). Leave vpc_cidr empty when using IPAM.
ipam_pool_id        = "ipam-pool-00c5cf0fe44301219"
vpc_cidr            = ""          # keep empty since using IPAM
ipam_netmask_length = 20

# AZs and flow logs
azs                      = ["us-east-1a", "us-east-1b"]
flow_logs_retention_days = 30
