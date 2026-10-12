terraform {
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
}

resource "aws_vpc" "feedback_tracker-vpc" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "feedback_tracker-igw" {
  vpc_id = aws_vpc.feedback_tracker-vpc.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.feedback_tracker-vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.feedback_tracker-vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = "ap-southeast-2b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_app_a" {
  vpc_id            = aws_vpc.feedback_tracker-vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = "ap-southeast-2a"
}

resource "aws_subnet" "private_app_b" {
  vpc_id            = aws_vpc.feedback_tracker-vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 4)
  availability_zone = "ap-southeast-2b"
}

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.feedback_tracker-vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 5)
  availability_zone = "ap-southeast-2a"
}

resource "aws_subnet" "private_db_b" {
  vpc_id            = aws_vpc.feedback_tracker-vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 6)
  availability_zone = "ap-southeast-2b"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.feedback_tracker-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.feedback_tracker-igw.id
  }
}

resource "aws_route_table_association" "public_a" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_a.id
}

resource "aws_route_table_association" "public_b" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public_b.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "feedback_tracker-ngw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  depends_on = [
    aws_internet_gateway.feedback_tracker-igw
  ]
}

resource "aws_route_table" "private_app_a" {
  vpc_id = aws_vpc.feedback_tracker-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.feedback_tracker-ngw.id
  }
}

resource "aws_route_table" "private_app_b" {
  vpc_id = aws_vpc.feedback_tracker-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.feedback_tracker-ngw.id
  }
}

resource "aws_route_table_association" "private_app_a" {
  route_table_id = aws_route_table.private_app_a.id
  subnet_id      = aws_subnet.private_app_a.id
}

resource "aws_route_table_association" "private_app_b" {
  route_table_id = aws_route_table.private_app_b.id
  subnet_id      = aws_subnet.private_app_b.id
}

resource "aws_security_group" "alb" {
  name   = "${var.env}-feedback-tracker-alb-sg"
  vpc_id = aws_vpc.feedback_tracker-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name   = "${var.env}-feedback-tracker-app-sg"
  vpc_id = aws_vpc.feedback_tracker-vpc.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name   = "${var.env}-feedback-tracker-db-sg"
  vpc_id = aws_vpc.feedback_tracker-vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

resource "aws_ecr_repository" "feedback_tracker" {
  name                 = "${var.env}-feedback-tracker-ecr"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "feedback_tracker" {
  repository = aws_ecr_repository.feedback_tracker.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the latest 10 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_lb" "feedback_tracker" {
  name               = "${var.env}-feedback-tracker-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
}

resource "aws_lb_target_group" "feedback_tracker" {
  name        = "${var.env}-feedback-tracker-tg"
  port        = 5000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.feedback_tracker-vpc.id

  health_check {
    path              = "/health"
    interval          = 10
    healthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.feedback_tracker.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.feedback_tracker.arn
  }
}

resource "aws_cloudwatch_log_group" "feedback_tracker" {
  name              = "/ecs/${var.env}-feedback-tracker"
  retention_in_days = 14
}

resource "random_password" "db_password" {
  length = 32
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.env}-feedback-tracker-db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_db_subnet_group" "feedback_tracker" {
  name = "${var.env}-feedback-tracker-db-subnets"
  subnet_ids = [
    aws_subnet.private_db_a.id,
    aws_subnet.private_db_b.id
  ]
}

resource "aws_rds_cluster" "feedback_tracker" {
  cluster_identifier = "${var.env}-feedback-tracker-db-cluster"

  engine      = "aurora-mysql"
  engine_mode = "provisioned"

  database_name   = var.DB_NAME
  master_username = var.MYSQL_USER
  master_password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.feedback_tracker.name
  vpc_security_group_ids = [aws_security_group.db.id]

  storage_encrypted   = true
  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = var.db_max_acu
  }
}

resource "aws_rds_cluster_instance" "feedback_tracker" {
  identifier         = "${var.env}-feedback-tracker-db-instance"
  cluster_identifier = aws_rds_cluster.feedback_tracker.id

  instance_class = "db.serverless"
  engine         = aws_rds_cluster.feedback_tracker.engine
}

resource "aws_ecs_cluster" "feedback_tracker" {
  name = "${var.env}-feedback-tracker-cluster"
}

resource "aws_iam_role" "task_execution" {
  name = "${var.env}-feedback-tracker-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "read_db_secret" {
  name = "${var.env}-feedback-tracker-read-db-secret"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

resource "aws_ecs_task_definition" "feedback_tracker" {
  family                   = "${var.env}-feedback-tracker-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = var.task_cpu
  memory = var.task_memory

  execution_role_arn = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "feedback-tracker"
      image     = "${aws_ecr_repository.feedback_tracker.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 5000
        }
      ]

      environment = [
        {
          name  = "APP_ENV"
          value = var.env
        },
        {
          name  = "DB_HOST"
          value = aws_rds_cluster.feedback_tracker.endpoint
        },
        {
          name  = "DB_NAME"
          value = var.DB_NAME
        },
        {
          name  = "MYSQL_USER"
          value = var.MYSQL_USER
        },
        {
          name  = "DB_PORT"
          value = tostring(var.DB_PORT)
        }
      ]

      secrets = [
        {
          name      = "MYSQL_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.feedback_tracker.name
          "awslogs-region"        = "ap-southeast-2"
          "awslogs-stream-prefix" = "feedback-tracker"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "feedback_tracker" {
  name            = "${var.env}-feedback-tracker-service"
  cluster         = aws_ecs_cluster.feedback_tracker.id
  task_definition = aws_ecs_task_definition.feedback_tracker.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.private_app_a.id,
      aws_subnet.private_app_b.id
    ]

    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.feedback_tracker.arn
    container_name   = "feedback-tracker"
    container_port   = 5000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.http,
    aws_rds_cluster_instance.feedback_tracker,
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy.read_db_secret
  ]
}
