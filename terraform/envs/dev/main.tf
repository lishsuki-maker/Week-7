terraform {
  required_version = ">= 1.10.0"

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

  backend "s3" {
    bucket       = "feedback-tracker-bucket"
    key          = "dev/feedback_tracker/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

module "feedback_tracker" {
  source = "../../modules/feedback_tracker"

  vpc_cidr      = "10.1.0.0/16"
  env           = "dev"
  DB_NAME       = var.DB_NAME
  MYSQL_USER    = var.MYSQL_USER
  db_max_acu    = 1
  task_cpu      = 256
  task_memory   = 512
  image_tag     = var.image_tag
  DB_PORT       = var.DB_PORT
  desired_count = 1
}

output "ecr_repository-url" {
  value = module.feedback_tracker.ecr_repository-url
}

output "feedback_tracker-url" {
  value = module.feedback_tracker.feedback_tracker-url
}
