# ---- Upstream remote states ----
# VPC / network
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox"
    key    = "wbd/sandbox/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# IAM instance profile
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox"
    key    = "wbd/sandbox/iam/instance_profile/terraform.tfstate"
    region = "us-east-1"
  }
}

# ---- Inputs resolved from upstream ----
locals {
  # Try common output names; fall back gracefully
  app_private_subnets = try(
    data.terraform_remote_state.vpc.outputs.app_private_subnet_ids,
    try(data.terraform_remote_state.vpc.outputs.private_app_subnet_ids, [] )
  )

  chosen_subnet_id = coalesce(
    var.subnet_id_override,
    try(local.app_private_subnets[0], null)
  )

  vpc_id   = try(data.terraform_remote_state.vpc.outputs.vpc_id, null)
  vpc_cidr = try(data.terraform_remote_state.vpc.outputs.vpc_cidr_block, null)

  iam_instance_profile = try(data.terraform_remote_state.iam.outputs.instance_profile_name, null)
}

# Fail early if we couldn't resolve required values
locals {
  _require_vpc_ok   = local.vpc_id != null && local.chosen_subnet_id != null
  _require_iam_ok   = local.iam_instance_profile != null
}

# Latest Amazon Linux AMI via SSM Parameter
data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# ---- Security Group (443 only) ----
resource "aws_security_group" "app_sg" {
  name        = "${local.ec2_name}-sg"
  description = "EC2 app SG (443 only)"
  vpc_id      = local.vpc_id
  tags        = merge(local.common_tags, { Name = "${local.ec2_name}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "https_in" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = local.vpc_cidr != null ? local.vpc_cidr : "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS only"
}

resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All egress"
}

# ---- User data: ensure SSM + CloudWatch Agent ----
locals {
  cwagent_cfg = jsonencode({
    agent = { metrics_collection_interval = 60 }
    metrics = {
      append_dimensions = { InstanceId = "${"\\$"}{aws:InstanceId}" }
      metrics_collected = {
        mem  = { measurement = ["mem_used_percent"] }
        disk = { resources = ["*"], measurement = ["used_percent"] }
        cpu  = { measurement = ["cpu_usage_idle","cpu_usage_user","cpu_usage_system"], totalcpu = true }
      }
    }
  })

  user_data = <<-EOF
    #!/bin/bash -xe
    if command -v dnf >/dev/null 2>&1; then PM=dnf; elif command -v yum >/dev/null 2>&1; then PM=yum; else PM=microdnf; fi
    ${"\\$"}PM -y update || true
    ${"\\$"}PM -y install amazon-ssm-agent || true
    ${"\\$"}PM -y install amazon-cloudwatch-agent || true
    systemctl enable --now amazon-ssm-agent || true

    mkdir -p /opt/aws/amazon-cloudwatch-agent/bin
    cat > /opt/aws/amazon-cloudwatch-agent/bin/config.json <<'CFG'
    ${local.cwagent_cfg}
    CFG
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop || true
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
    exit 0
  EOF
}

# ---- EC2 instance ----
resource "aws_instance" "app" {
  ami                                  = data.aws_ssm_parameter.ami.value
  instance_type                        = var.instance_type
  subnet_id                            = local.chosen_subnet_id
  vpc_security_group_ids               = [aws_security_group.app_sg.id]
  associate_public_ip_address          = false
  disable_api_termination              = true
  iam_instance_profile                 = local.iam_instance_profile
  user_data                            = local.user_data

  # Root volume
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  # Metadata (IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(local.common_tags, { Name = local.ec2_name })
}
