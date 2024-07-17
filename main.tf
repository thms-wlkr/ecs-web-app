########################################################################
####################       VPC + SUBNETS      ##########################
########################################################################

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/27"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    name      = "vpc"
    terraform = "true"
  }
}

resource "aws_subnet" "public_subnet" {
  count             = length(var.subnet_cidr_blocks)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    name      = "public-subnet-${count.index + 1}" # sets the name from the current iteration of var.public_cidr_blocks
    terraform = "true"
  }
}

########################################################################
####################            IGW            #########################
########################################################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    name      = "igw"
    terraform = "true"
  }
}

########################################################################
####################        ROUTE TABLE       ##########################
########################################################################

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    name      = "public-route-table"
    terraform = "true"
  }
}

resource "aws_route_table_association" "subnet_association" {
  count          = length(var.subnet_cidr_blocks)
  subnet_id      = element(aws_subnet.public_subnet[*].id, count.index)
  route_table_id = aws_route_table.route_table.id
}

########################################################################
####################       LOAD BALANCER      ##########################
########################################################################

resource "aws_lb" "alb" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  tags = {
    name      = "alb"
    terraform = "true"
  }
}

resource "aws_lb_target_group" "ecs_target_group" {
  name     = "target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    path = "/"
    port = "80"
    protocol = "HTTP"
  }

  tags = {
    name      = "alb-tg"
    terraform = "true"
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
  }
}

########################################################################
####################      SECURITY GROUP       #########################
########################################################################

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "security group for ECS containers"
  vpc_id      = aws_vpc.vpc.id

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

  tags = {
    name      = "ecs-SG"
    terraform = "true"
  }
}

########################################################################
####################            ECR            #########################
########################################################################

resource "aws_ecr_repository" "ecr_repo" {
  name = "ecr-repo"

  tags = {
    name      = "ecr-repo"
    terraform = "true"
  }
}

########################################################################
####################            ECS            #########################
########################################################################

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster"

  tags = {
    name      = "ecs-cluster"
    terraform = "true"
  }
}


resource "aws_ecs_service" "ecs_service" {
  name            = "ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    container_name   = var.app_name
    container_port   = 80
  }

  depends_on = [aws_lb_listener.alb_listener]

  tags = {
    Name      = "ecs-service"
    Terraform = "true"
  }
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "ecs-task"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name        = "nodejs-app"
      image       = "${aws_ecr_repository.ecr_repo.repository_url}:latest"
      memory      = 512
      cpu         = 256
      essential   = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    name      = "ecs-task-definition"
    terraform = "true"
  }
}

########################################################################
####################            IAM            #########################
########################################################################

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = {
    name      = "ecs-task-execution-role"
    terraform = "true"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

########################################################################
####################         CLOUDWATCH        #########################
########################################################################

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/my-service"
  retention_in_days = 1 

  tags = {
    name      = "ecs-log-group"
    terraform = "true"
  }
}
