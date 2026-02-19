terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration is intentionally empty here.
  # Provide values with:
  # terraform init -backend-config=backend-dev.hcl
  backend "s3" {}
}
