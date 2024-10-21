terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.72.1"
    }
  }
}

provider "aws" {
  region = "ca-central-1"

  default_tags {
    tags = {
      Project = "satiserver"
    }
  }
}
