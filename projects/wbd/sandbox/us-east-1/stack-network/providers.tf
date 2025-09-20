provider "aws" {
  region = var.region   # CodeBuild injects creds via env; no keys here.
}
