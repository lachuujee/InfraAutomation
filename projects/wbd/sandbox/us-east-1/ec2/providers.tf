terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket  = "wbd-tf-state-sandbox"
    key     = "wbd/sandbox/ec2/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    # (In prod, add DynamoDB table for state locking)
  }
}

provider "aws" {
  region = var.region
}
