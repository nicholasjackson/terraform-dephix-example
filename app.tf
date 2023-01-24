resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name}-ecsTaskRole"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.name}-ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_policy" "exec" {
  name        = "${var.name}-ecsTaskExecPolicy"
  path        = "/"
  description = "Exec policy allowing access to containers"

  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
       "Effect": "Allow",
       "Action": [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
       ],
      "Resource": "*"
      }
   ]
}
  EOF
}

resource "aws_security_group" "alb" {
  name        = "alb_ingress_${var.name}"
  description = "Allow Ingress inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "DB port from public"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = resource.aws_iam_policy.exec.arn
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "random_id" "sd_namespace" {
  byte_length = 8
}

resource "aws_service_discovery_http_namespace" "app" {
  name        = random_id.sd_namespace.hex
  description = "Service discovery namespace for app"
}

module "api" {
  source = "./task_def"

  name       = "api"
  image      = "nicholasjackson/payments-api:v0.1.3"
  port       = 3000
  region     = var.region
  cluster_id = module.ecs.cluster_id
  env_vars = {
    "DB_HOST" = "db.${random_id.sd_namespace.hex}"
    "DB_PORT" = "5432"
    "DB_USER" = "admin"
    "DB_PASS" = "password"
  }

  sd_namespace = aws_service_discovery_http_namespace.app.arn

  cidr            = "10.1.0.0/16"
  private_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  alb_arn = aws_lb.main.id
}

module "processor" {
  source = "./task_def"

  name       = "processor"
  image      = "nicholasjackson/payments-processor:v0.1.4"
  port       = 3001
  region     = var.region
  cluster_id = module.ecs.cluster_id
  env_vars = {
    "DB_HOST" = "db.${random_id.sd_namespace.hex}"
    "DB_PORT" = "5432"
    "DB_USER" = "admin"
    "DB_PASS" = "password"
  }

  sd_namespace = aws_service_discovery_http_namespace.app.arn

  cidr            = "10.1.0.0/16"
  private_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  alb_arn = aws_lb.main.id
}

module "traffic-generator" {
  source = "./task_def"

  name       = "generator"
  image      = "nicholasjackson/payments-generator:v0.1.4"
  port       = 3002
  region     = var.region
  cluster_id = module.ecs.cluster_id
  env_vars = {
    "API_HOST" = "http://api.${random_id.sd_namespace.hex}:3000"
  }

  sd_namespace = aws_service_discovery_http_namespace.app.arn

  cidr            = "10.1.0.0/16"
  private_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  alb_arn = aws_lb.main.id
}

module "delphix_db" {
  source = "./dev_db/"

  name        = var.name
  dct_host    = var.dct_host
  dct_api_key = var.dct_api_key
}

module "db" {
  source = "./task_def"

  name       = "db"
  image      = "postgres:15.1"
  port       = 5432
  region     = var.region
  cluster_id = module.ecs.cluster_id
  env_vars = {
    "POSTGRES_DB"       = "payments"
    "POSTGRES_USER"     = "admin"
    "POSTGRES_PASSWORD" = "password"
  }

  sd_namespace = aws_service_discovery_http_namespace.app.arn

  cidr            = "10.1.0.0/16"
  private_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  alb_arn = aws_lb.main.id
}
