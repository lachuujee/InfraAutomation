terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# --- Remote state: VPC (network stack) ---
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox"
    key    = "wbd/sandbox/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# --- Remote state: key pair (keypair_secret) ---
data "terraform_remote_state" "kp" {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox"
    key    = "wbd/sandbox/keypair_secret/terraform.tfstate"
    region = "us-east-1"
  }
}

# Latest Amazon Linux via SSM Parameter
data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# Choose app private subnet from VPC outputs (1a or 1b). Try common output names; fallback to override.
locals {
  app_private_subnets = try(
    data.terraform_remote_state.vpc.outputs.app_private_subnet_ids,
    try(data.terraform_remote_state.vpc.outputs.private_app_subnet_ids, [] )
  )

  chosen_subnet_id = coalesce(
    var.subnet_id_override,
    try(local.app_private_subnets[0], null)
  )

  vpc_id       = try(data.terraform_remote_state.vpc.outputs.vpc_id, null)
  vpc_cidr     = try(data.terraform_remote_state.vpc.outputs.vpc_cidr_block, null)
  key_name_rsx = var.use_key_pair ? try(data.terraform_remote_state.kp.outputs.key_name, null) : null
}

# Security Group: only 443 inbound, all egress
resource "aws_security_group" "app_sg" {
  name        = local.sg_name
  description = "App SG (443 only)"
  vpc_id      = local.vpc_id
  tags        = merge(local.common_tags, { Name = local.sg_name })
}

resource "aws_vpc_security_group_ingress_rule" "https_in" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = coalesce(local.vpc_cidr, "0.0.0.0/0")
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

# IAM instance profile for SSM & CloudWatch (module below)
module "iam_profile" {
  source      = "../../../modules/iam_instance_profile"
  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# User data: ensure SSM + CloudWatch Agent are installed and running (AL2023 uses dnf)
locals {
  cwagent_cfg = jsonencode({
    agent = { metrics_collection_interval = 60, logfile = "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log" }
    metrics = {
      append_dimensions = { InstanceId = "${"\\$"}{aws:InstanceId}" }
      metrics_collected = { mem = { measurement = ["mem_used_percent"] }, disk = { resources = ["*"], measurement = ["used_percent"] }, cpu = { measurement = ["cpu_usage_idle","cpu_usage_user","cpu_usage_system"], totalcpu = true } }
    }
  })

  user_data = <<-EOF
    #!/bin/bash -xe
    # Detect package manager
    if command -v dnf >/dev/null 2>&1; then PM=dnf; elif command -v yum >/dev/null 2>&1; then PM=yum; else PM=microdnf; fi

    # Update and install agents
    ${"\\$"}PM -y update || true
    ${"\\$"}PM -y install amazon-ssm-agent || true
    ${"\\$"}PM -y install amazon-cloudwatch-agent || true

    systemctl enable --now amazon-ssm-agent || true

    # Write CloudWatch Agent config
    mkdir -p /opt/aws/amazon-cloudwatch-agent/bin /opt/aws/amazon-cloudwatch-agent/etc
    cat > /opt/aws/amazon-cloudwatch-agent/bin/config.json <<'CFG'
    ${local.cwagent_cfg}
    CFG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop || true
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s

    # Ensure IMDSv2-only works fine for SSM & CW
    exit 0
  EOF
}

# EC2 Instance
resource "aws_instance" "app" {
  ami                                  = data.aws_ssm_parameter.ami.value
  instance_type                        = var.instance_type
  subnet_id                            = local.chosen_subnet_id
  vpc_security_group_ids               = [aws_security_group.app_sg.id]
  key_name                             = local.key_name_rsx
  associate_public_ip_address          = false
  disable_api_termination              = true
  iam_instance_profile                 = module.iam_profile.instance_profile_name
  user_data                            = local.user_data

  # Block device
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  # Metadata options
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  tags = merge(local.common_tags, { Name = local.ec2_name })
}
