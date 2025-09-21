############################################
# Data & Locals
############################################

# Grab the first two AZs in the region (e.g., us-east-1a, us-east-1b)
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two AZs
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  name_prefix = "${var.customer}_${var.environment}"

  common_tags = merge(
    {
      Customer    = var.customer
      Environment = var.environment
    },
    var.extra_tags
  )
}

############################################
# VPC via IPAM pool
############################################

resource "aws_vpc" "this" {
  # Allocate the VPC CIDR from your IPAM pool
  ipv4_ipam_pool_id   = var.ipam_pool_id
  ipv4_netmask_length = var.vpc_netmask_length # e.g., 20

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-vpc"
    Service = "VPC"
  })
}

############################################
# Public & Private CIDR planning
#
# - Private: six /23 subnets (≈512 IPs each), split across two AZs:
#     app-a, app-b, api-a, api-b, db-a, db-b
# - Public: two /28 subnets (16 IPs each) carved from a dedicated /24
############################################

locals {
  # Six /23s for private subnets (netnums 0..5)
  private_cidrs = [
    cidrsubnet(aws_vpc.this.cidr_block, 3, 0),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 1),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 2),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 3),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 4),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 5),
  ]

  # Reserve the last /24 inside the VPC and carve two /28s for public
  public_parent = cidrsubnet(aws_vpc.this.cidr_block, 4, 15) # /24
  public_cidrs  = [
    cidrsubnet(local.public_parent, 4, 0), # /28
    cidrsubnet(local.public_parent, 4, 1), # /28
  ]

  # Map out the 6 private subnets with roles & AZs
  private_def = {
    "app-a" = { cidr = local.private_cidrs[0], az = local.azs[0], role = "app" }
    "app-b" = { cidr = local.private_cidrs[1], az = local.azs[1], role = "app" }
    "api-a" = { cidr = local.private_cidrs[2], az = local.azs[0], role = "api" }
    "api-b" = { cidr = local.private_cidrs[3], az = local.azs[1], role = "api" }
    "db-a"  = { cidr = local.private_cidrs[4], az = local.azs[0], role = "db"  }
    "db-b"  = { cidr = local.private_cidrs[5], az = local.azs[1], role = "db"  }
  }
}

############################################
# Internet Gateway (for public)
############################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-igw"
    Service = "InternetGateway"
  })
}

############################################
# Public subnets x2 (/28 each)
############################################

resource "aws_subnet" "public" {
  for_each = {
    "a" = { cidr = local.public_cidrs[0], az = local.azs[0] }
    "b" = { cidr = local.public_cidrs[1], az = local.azs[1] }
  }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-public-${each.key}"
    Service = "SubnetPublic"
  })
}

############################################
# EIP + NAT (1 NAT in AZ-a public subnet)
############################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-nat-eip"
    Service = "NATGateway"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-nat"
    Service = "NATGateway"
  })
}

############################################
# Route tables
############################################

# Public RTB with default route to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-public"
    Service = "RouteTablePublic"
  })

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate public subnets with the public RTB
resource "aws_route_table_association" "public_assoc" {
  for_each      = aws_subnet.public
  subnet_id     = each.value.id
  route_table_id = aws_route_table.public.id
}

# Three private RTBs by role, each with default route to the NAT
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-private-app"
    Service = "RouteTablePrivate"
  })

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table" "private_api" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-private-api"
    Service = "RouteTablePrivate"
  })

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-private-db"
    Service = "RouteTablePrivate"
  })

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

############################################
# Private subnets x6 (/23 each) + associations
############################################

resource "aws_subnet" "private" {
  for_each = local.private_def

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-private-${each.value.role}-${substr(each.key, -1, 1)}"
    Role    = upper(each.value.role)
    Service = "SubnetPrivate"
  })
}

# Map role -> private route table id
locals {
  rtb_by_role = {
    app = aws_route_table.private_app.id
    api = aws_route_table.private_api.id
    db  = aws_route_table.private_db.id
  }
}

# Associate each private subnet to its role-specific RTB
resource "aws_route_table_association" "private_assoc" {
  for_each = local.private_def

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = local.rtb_by_role[each.value.role]
}

############################################
# Network ACL (one NACL, attach to all subnets)
# Inbound: allow 443 only
# Outbound: allow all
############################################

resource "aws_network_acl" "vpc_acl" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-nacl"
    Service = "NACL"
  })
}

# Inbound allow HTTPS
resource "aws_network_acl_rule" "ingress_https" {
  network_acl_id = aws_network_acl.vpc_acl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# Outbound allow all
resource "aws_network_acl_rule" "egress_all" {
  network_acl_id = aws_network_acl.vpc_acl.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

# Attach the NACL to every subnet
resource "aws_network_acl_association" "assoc_public" {
  for_each = aws_subnet.public
  network_acl_id = aws_network_acl.vpc_acl.id
  subnet_id      = each.value.id
}

resource "aws_network_acl_association" "assoc_private" {
  for_each = aws_subnet.private
  network_acl_id = aws_network_acl.vpc_acl.id
  subnet_id      = each.value.id
}

############################################
# Flow Logs: role, policy, log group, flow log
############################################

data "aws_iam_policy_document" "flowlogs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flowlogs_role" {
  name               = "${local.name_prefix}-vpc-flowlogs-role"
  assume_role_policy = data.aws_iam_policy_document.flowlogs_trust.json

  tags = merge(local.common_tags, {
    Service = "FlowLogs"
  })
}

data "aws_iam_policy_document" "flowlogs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flowlogs_role_policy" {
  name   = "${local.name_prefix}-vpc-flowlogs-policy"
  role   = aws_iam_role.flowlogs_role.id
  policy = data.aws_iam_policy_document.flowlogs_policy.json
}

resource "aws_cloudwatch_log_group" "flowlogs" {
  name              = "/vpc/flowlogs/${local.name_prefix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Service = "FlowLogs"
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.this.id
  log_destination_type = "cloud-watch-logs"
  log_group_name       = aws_cloudwatch_log_group.flowlogs.name
  iam_role_arn         = aws_iam_role.flowlogs_role.arn
  traffic_type         = "ALL"

  tags = merge(local.common_tags, {
    Service = "FlowLogs"
  })
}
