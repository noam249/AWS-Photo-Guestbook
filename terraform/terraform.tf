terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "remote-s3-backend-noam"
    region = "eu-west-1"
    key = "photo-guestbook/terraform.tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}