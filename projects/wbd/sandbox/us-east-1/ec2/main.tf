# =========================
# EC2 stack - logic only
# =========================

# -------- Naming/tags (no name_prefix var; simple & explicit) --------
locals {
  ec2_name    = "${var.customer}_${var.environment}-ec2-app"
  common_tags = merge(
    { Customer = var.customer, Environment = var.environment },
    var.tags_extra
  )
}

# -------- Upstream remote states --------
# VPC (network) state
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox"
    key    = "wbd/sandbox/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# IAM instance profile state
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "wbd-tf-state-sandbox"
    key    = "wbd/sandbox/iam/instance_profile/terraform.tfstate"
    region = "us-east-1"
  }
}

# -------- AMI: Latest Amazon Linux via AWS public SSM Parameter --------
data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# If VPC CIDR wasn't exported, derive it by describing the VPC ID
locals {
  vpc_id = try(data.terraform_remote_state.vpc.outputs.vpc_id, null)
}

data "aws_vpc" "selected" {
  count = local.vpc_id != null ? 1 : 0
  id    = local.vpc_id
}

# -------- Resolve VPC values & choose an app subnet dynamically --------
locals {
  vpc_outputs = data.terraform_remote_state.vpc.outputs

  # CIDR from outputs, else from EC2 API (if vpc_id known)
  vpc_cidr = try(
    local.vpc_outputs.vpc_cidr,
    try(
      local.vpc_outputs.vpc_cidr_block,
      (local.vpc_id != null && length(data.aws_vpc.selected) == 1 ? data.aws_vpc.selected[0].cidr_block : null)
    )
  )

  # Map form: private_subnet_ids_by_role = { app-a = subnet-..., app-b = subnet-..., APP-HEFN-FEE = subnet-..., ... }
  subnets_by_role = try(local.vpc_outputs.private_subnet_ids_by_role, {})

  # Keys that contain "app" (case-insensitive)
  app_keys = [for k in keys(local.subnets_by_role) : k if length(regexall("(?i)app", k)) > 0]

  # If any app* keys exist, pick the first (sorted). Else check list outputs.
  chosen_key_from_map    = length(local.app_keys) > 0 ? sort(local.app_keys)[0] : null
  chosen_subnet_from_map = local.chosen_key_from_map != null ? local.subnets_by_role[local.chosen_key_from_map] : null

  # Fallback list-style outputs (if your VPC exports them)
  app_list1            = try(local.vpc_outputs.app_private_subnet_ids, [])
  app_list2            = try(local.vpc_outputs.private_app_subnet_ids, [])
  app_list_any         = length(local.app_list1) > 0 ? local.app_list1 : local.app_list2
  chosen_subnet_fallback = length(local.app_list_any) > 0 ? local.app_list_any[0] : null

  # Final chosen subnet: any “app” subnet (APP-HEFN-FEE etc.) or the first in list outputs
  chosen_subnet_id = local.chosen_subnet_from_map != null ? local.chosen_subnet_from_map : local.chosen_subnet_fallback

  iam_instance_profile = try(data.terraform_remote_state.iam.outputs.instance_profile_name, null)
}

# -------- Security Group (443 only) --------
resource "aws_security_group" "app_sg" {
  name        = "${local.ec2_name}-sg"
  description = "EC2 app SG (443 only)"
  vpc_id      = local.vpc_id
  tags        = merge(local.common_tags, { Name = "${local.ec2_name}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "https_in" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = local.vpc_cidr != null ? local.vpc_cidr : "0.0.0.0/0" # prefer VPC-only; fallback if CIDR not exported
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

# -------- User data: SSM + CloudWatch Agent --------
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
    ${"\\$"}PM -y install amazon-ssm-agent amazon-cloudwatch-agent || true
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

# -------- EC2 instance --------
resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.chosen_subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = false
  disable_api_termination     = true
  iam_instance_profile        = local.iam_instance_profile
  user_data                   = local.user_data

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

  lifecycle {
    precondition {
      condition     = local.chosen_subnet_id != null
      error_message = "No app subnet found in VPC state outputs. Expect either private_subnet_ids_by_role with an 'app*' key, or app_private_subnet_ids/private_app_subnet_ids."
    }
    precondition {
      condition     = local.iam_instance_profile != null
      error_message = "IAM instance profile not found in IAM stack outputs (expected 'instance_profile_name')."
    }
  }
}
