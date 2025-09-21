############################
# Providers / versions
############################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" { region = var.region }

############################
# VPC from IPAM or fixed CIDR
############################

# VPC allocated from IPAM pool
resource "aws_vpc" "from_ipam" {
  count                = var.ipam_pool_id != "" && var.vpc_cidr == "" ? 1 : 0
  ipv4_ipam_pool_id    = var.ipam_pool_id
  ipv4_netmask_length  = var.ipam_netmask_length
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_VPC"
    Service = "VPC"
  })
}

# VPC with fixed CIDR (fallback)
resource "aws_vpc" "from_cidr" {
  count                = var.vpc_cidr != "" ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_VPC"
    Service = "VPC"
  })
}

# Unified handles
locals {
  vpc_id   = try(aws_vpc.from_cidr[0].id, aws_vpc.from_ipam[0].id)
  vpc_cidr = try(aws_vpc.from_cidr[0].cidr_block, aws_vpc.from_ipam[0].cidr_block)
}

############################
# Subnet CIDR planning
# - 6 private /23 (≈512 IPs), indexes 0..5 via newbits=3
# - 2 public  /28 (≈16 IPs), indexes 192,193 via newbits=8
############################
locals {
  private_cidrs = [
    cidrsubnet(local.vpc_cidr, 3, 0),
    cidrsubnet(local.vpc_cidr, 3, 1),
    cidrsubnet(local.vpc_cidr, 3, 2),
    cidrsubnet(local.vpc_cidr, 3, 3),
    cidrsubnet(local.vpc_cidr, 3, 4),
    cidrsubnet(local.vpc_cidr, 3, 5)
  ]

  public_cidrs = [
    cidrsubnet(local.vpc_cidr, 8, 192),
    cidrsubnet(local.vpc_cidr, 8, 193)
  ]
}

############################
# IGW and Public Route Table
############################
resource "aws_internet_gateway" "igw" {
  vpc_id = local.vpc_id
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_igw"
    Service = "InternetGateway"
  })
}

resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_rt_public"
    Service = "RouteTablePublic"
  })
}

############################
# Public subnets (2) — /28, one per AZ
############################
resource "aws_subnet" "public" {
  for_each                = { a = 0, b = 1 }
  vpc_id                  = local.vpc_id
  cidr_block              = local.public_cidrs[each.value]
  availability_zone       = var.azs[each.value]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_public_${each.key}"
    Service = "SubnetPublic"
    Tier    = "public"
    AZ      = var.azs[each.value]
  })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

############################
# NAT Gateway (1) + EIP (in public-a)
############################
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_nat_eip"
    Service = "EIP"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public["a"].id
  depends_on    = [aws_internet_gateway.igw]
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_nat"
    Service = "NATGateway"
  })
}

############################
# Private Route Tables (3): app, api, db -> default via NAT
############################
resource "aws_route_table" "private_app" {
  vpc_id = local.vpc_id
  route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.nat.id }
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_rt_private_app"
    Service = "RouteTablePrivateApp"
  })
}

resource "aws_route_table" "private_api" {
  vpc_id = local.vpc_id
  route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.nat.id }
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_rt_private_api"
    Service = "RouteTablePrivateApi"
  })
}

resource "aws_route_table" "private_db" {
  vpc_id = local.vpc_id
  route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.nat.id }
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_rt_private_db"
    Service = "RouteTablePrivateDb"
  })
}

############################
# Private subnets (6) — /23, balanced across AZs
############################
locals {
  private_labels = ["app_a", "app_b", "api_a", "api_b", "db_a", "db_b"]

  private_rt_map = {
    app_a = aws_route_table.private_app.id
    app_b = aws_route_table.private_app.id
    api_a = aws_route_table.private_api.id
    api_b = aws_route_table.private_api.id
    db_a  = aws_route_table.private_db.id
    db_b  = aws_route_table.private_db.id
  }

  private_az_map = {
    app_a = var.azs[0]
    app_b = var.azs[1]
    api_a = var.azs[0]
    api_b = var.azs[1]
    db_a  = var.azs[0]
    db_b  = var.azs[1]
  }

  private_cidr_map = {
    app_a = local.private_cidrs[0]
    app_b = local.private_cidrs[1]
    api_a = local.private_cidrs[2]
    api_b = local.private_cidrs[3]
    db_a  = local.private_cidrs[4]
    db_b  = local.private_cidrs[5]
  }

  private_service_map = {
    app_a = "SubnetPrivateApp"
    app_b = "SubnetPrivateApp"
    api_a = "SubnetPrivateApi"
    api_b = "SubnetPrivateApi"
    db_a  = "SubnetPrivateDb"
    db_b  = "SubnetPrivateDb"
  }
}

resource "aws_subnet" "private" {
  for_each          = { for idx, lbl in local.private_labels : lbl => idx }
  vpc_id            = local.vpc_id
  cidr_block        = local.private_cidr_map[each.key]
  availability_zone = local.private_az_map[each.key]
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_private_${each.key}"
    Service = local.private_service_map[each.key]
    Tier    = "private"
    Role    = split("_", each.key)[0]   # app/api/db
    AZ      = local.private_az_map[each.key]
  })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  route_table_id = local.private_rt_map[each.key]
  subnet_id      = each.value.id
}

############################
# Private NACL: inbound 443 only; outbound allow all
############################
resource "aws_network_acl" "private_acl" {
  vpc_id = local.vpc_id
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_nacl_private_443only"
    Service = "NACL"
  })
}

resource "aws_network_acl_rule" "in_allow_443" {
  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "out_allow_all" {
  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_association" "private_acl_assoc" {
  for_each       = aws_subnet.private
  network_acl_id = aws_network_acl.private_acl.id
  subnet_id      = each.value.id
}

############################
# Flow Logs → CloudWatch (log group + role + flow log)
############################
resource "aws_cloudwatch_log_group" "flowlogs" {
  name              = "/vpc/${locals.name_prefix}/flowlogs"
  retention_in_days = var.flow_logs_retention_days
  tags = merge(local.common_tags, {
    Service = "FlowLogs"
  })
}

data "aws_iam_policy_document" "flowlogs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["vpc-flow-logs.amazonaws.com"] }
  }
}

data "aws_iam_policy_document" "flowlogs_rw" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.flowlogs.arn,
      "${aws_cloudwatch_log_group.flowlogs.arn}:*"
    ]
  }
}

resource "aws_iam_role" "flowlogs" {
  name               = "${locals.name_prefix}_flowlogs_role"
  assume_role_policy = data.aws_iam_policy_document.flowlogs_trust.json
  tags = merge(local.common_tags, {
    Service = "FlowLogs"
  })
}

resource "aws_iam_role_policy" "flowlogs" {
  name   = "${locals.name_prefix}_flowlogs_policy"
  role   = aws_iam_role.flowlogs.id
  policy = data.aws_iam_policy_document.flowlogs_rw.json
}

resource "aws_flow_log" "vpc" {
  vpc_id               = local.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_group_name       = aws_cloudwatch_log_group.flowlogs.name
  iam_role_arn         = aws_iam_role.flowlogs.arn
  tags = merge(local.common_tags, {
    Name    = "${locals.name_prefix}_flowlog"
    Service = "FlowLogs"
  })
}
