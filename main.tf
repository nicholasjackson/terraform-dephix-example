terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.50.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "delphix-${var.name}"

  cidr = "10.1.0.0/16"

  azs             = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1], data.aws_availability_zones.available.names[2]]
  private_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets  = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

  enable_nat_gateway = true

  # needed otherwise the EFS volumes for the server will not mount for the Waypoint server task
  enable_dns_hostnames = true

  tags = {
    Environment = "Development"
    Owner       = "Nic Jackson"
    Project     = "Delphix Demo"
  }
}

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"

  cluster_name = "dephix-${var.name}"

  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/aws-ec2"
      }
    }
  }

  # Capacity provider
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
  }

  tags = {
    Environment = "Development"
    Owner       = "Nic Jackson"
    Project     = "Delphix Demo"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecs_subnet_1" {
  value = module.vpc.public_subnets[0]
}

output "ecs_subnet_2" {
  value = module.vpc.public_subnets[1]
}

output "ecs_subnet_3" {
  value = module.vpc.public_subnets[2]
}
output "alb_dns" {
  value = aws_lb.main.dns_name
}
