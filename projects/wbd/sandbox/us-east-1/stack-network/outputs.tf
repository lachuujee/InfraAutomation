# Core VPC
output "vpc_id"    { value = aws_vpc.this.id }
output "vpc_cidr"  { value = aws_vpc.this.cidr_block }

# Internet Gateway / NAT / EIP
output "igw_id"           { value = aws_internet_gateway.igw.id }
output "nat_gateway_id"   { value = aws_nat_gateway.nat.id }
output "nat_eip_id"       { value = aws_eip.nat.id }
output "nat_eip_public_ip"{ value = aws_eip.nat.public_ip }

# Route tables
output "rtb_public_id"    { value = aws_route_table.public.id }
output "rtb_private_ids" {
  value = {
    app = aws_route_table.private_app.id
    api = aws_route_table.private_api.id
    db  = aws_route_table.private_db.id
  }
}

# Subnets (IDs and CIDRs)
output "public_subnet_ids"  { value = { for k, s in aws_subnet.public  : k => s.id } }
output "public_subnet_cidrs"{ value = { for k, s in aws_subnet.public  : k => s.cidr_block } }

output "private_subnet_ids_by_role"   { value = { for k, s in aws_subnet.private : k => s.id } }
output "private_subnet_cidrs_by_role" { value = { for k, s in aws_subnet.private : k => s.cidr_block } }

# Network ACL
output "nacl_id" { value = aws_network_acl.vpc_acl.id }

# Flow Logs (CloudWatch + IAM)
output "flow_logs_log_group_name" { value = aws_cloudwatch_log_group.flowlogs.name }
output "flow_logs_log_group_arn"  { value = aws_cloudwatch_log_group.flowlogs.arn }
output "flow_logs_role_name"      { value = aws_iam_role.flowlogs_role.name }
output "flow_logs_role_arn"       { value = aws_iam_role.flowlogs_role.arn }
output "flow_log_id"              { value = aws_flow_log.vpc.id }

# Useful context
output "availability_zones" { value = var.azs }
