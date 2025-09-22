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
    key     = "wbd/sandbox/iam/instance_profile/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    # No DynamoDB table (per your requirement)
  }
}

provider "aws" {
  region = var.region
}
