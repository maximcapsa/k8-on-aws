terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Local state — fine for a single-person free-tier project.
  # (tfstate is gitignored.) Switch to an S3 backend if you ever
  # collaborate or want remote locking.
}

provider "aws" {
  region = var.aws_region
}
