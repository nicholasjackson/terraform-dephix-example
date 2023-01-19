variable "name" {
  default = ""
}

variable "region" {
  default = ""
}

variable "cluster_id" {
  default = ""
}

variable "image" {
  default = ""
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "vpc_id" {
  default = ""
}

variable "port" {
  default = 0
}

variable "cidr" {
  default = ""
}

variable "subnets" {
  default = []
}

variable "sd_namespace" {
  default = ""
}

variable "execution_role_arn" {
  default = ""
}

variable "task_role_arn" {
  default = ""
}

locals {
  envs = [for key, value in var.env_vars :
    {
      name  = key
      value = value
    }
  ]

  log_group = "/fargate/service/${var.name}"

  task = jsonencode([
    {
      name        = var.name
      image       = var.image
      environment = local.envs
      region      = var.region
      port        = var.port
      cpu         = 512
      memory      = 1024
      portMappings = [
        {
          name          = "main"
          containerPort = var.port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "logs" {
  name              = local.log_group
  retention_in_days = 1
}

resource "aws_security_group" "app" {
  name        = "app_ingress_${var.name}"
  description = "Allow Ingress inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "Container port from vpc"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  ingress {
    description      = "TLS inbound"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024

  container_definitions = local.task

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn
}

resource "aws_ecs_service" "app" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.app.arn

  desired_count = 1

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  enable_execute_command             = true

  network_configuration {
    security_groups = [aws_security_group.app.id]
    subnets         = var.subnets
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.sd_namespace

    service {
      discovery_name = var.name

      client_alias {
        port = var.port
      }

      port_name = "main"
    }
  }

  lifecycle {
    ignore_changes = [
      capacity_provider_strategy
    ]
  }
}

output "fqdn" {
  value = aws_ecs_service.app.name
}
