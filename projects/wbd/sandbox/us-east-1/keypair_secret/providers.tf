terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  backend "s3" {
    bucket = "wbd-tf-state-sandbox"                 # <-- your bucket
    key    = "wbd/sandbox/keypair_secret/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}

provider "aws" { region = var.region }
