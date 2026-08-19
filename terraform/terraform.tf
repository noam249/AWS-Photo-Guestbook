terraform {
  required_providers {
    aws = {
        source = "hasicorp/aws"
        version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}