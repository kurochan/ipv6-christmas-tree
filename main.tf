terraform {
  # backend "local" {}
  backend "s3" {
    bucket = ""
    key    = "terraform.tfstate"
    region = "ap-northeast-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      Environment = local.project_name
      Description = "for CyberAgent Developers Advent Calendar 2025"
    }
  }
}

resource "random_string" "tfstate_suffix" {
  length  = 16
  special = false
  upper   = false
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "${local.project_name}-tfstate-${random_string.tfstate_suffix.id}"
}

output "tfstate_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  project_name = "ipv6-christmas-tree"
}
