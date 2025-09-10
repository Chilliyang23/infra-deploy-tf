data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.prefix}/base/vpc_id"
}
data "aws_ssm_parameter" "subnet_a" {
  name = "/${var.prefix}/base/subnet/a/id"
}
data "aws_ssm_parameter" "subnet_b" {
  name = "/${var.prefix}/base/subnet/b/id"
}
data "aws_ssm_parameter" "ecr" {
  name = "/${var.prefix}/base/ecr"
}

locals {
  vpc_id        = data.aws_ssm_parameter.vpc_id.value
  subnet_ids    = [data.aws_ssm_parameter.subnet_a.value, data.aws_ssm_parameter.subnet_b.value]
  ecr_url       = data.aws_ssm_parameter.ecr.value
  container_cpu = 256
  container_mem = 512
}

# alb provisioning

resource "aws_security_group" "alg_sg" {
  vpc_id = local.vpc_id
  name = "${var.prefix}-alb-sg"
  description = "ALB security group"

   tags = {
    Name = "ALB sg"
    createdBy = "infra-${var.prefix}/news"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_ingress" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_egress_all" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4 = "0.0.0.0./0"
  from_port = 0
  to_port = 0
  ip_protocol = "-1"
}

resource "aws_lb" "alb" {
  name = "${var.prefix}-front-end-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg.id]
  subnets = [local.subnet_ids]

  tags = {
    Name = "${var.prefix}-alb"
    createdBy = "infra-${var.prefix}/news"
  }
}

resource "aws_lb_target_group" "front_end_tg" {
  name = "${var.prefix}-front-end-tg"
  port = 8080
  protocol = "HTTP"
  target_type = "ip"
  vpc_id = local.vpc_id

  health_check {
    enabled = true
    path = "/ping"
    interval = 30
    port = "8080"
    protocol = "HTTP"
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.prefix}-front-end-tg"
    createdBy = "infra-${var.prefix}/news"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end_tg.arn
  }
}

# ecs provisioning

resource "aws_security_group" "ecs_tasks_sg" {
  vpc_id = local.vpc_id
  name = "${var.prefix}-ecs-tasks-sg"
  description = "Security group for ECS tasks"

  tags = {
    Name = "ECS tasks sg"
    createdBy = "infra-${var.prefix}/news"
  }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id = aws_security_group.ecs_tasks_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port = 8080
  to_port = 8080
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "tasks_egress_all" {
  security_group_id = aws_security_group.ecs_tasks_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 0
  to_port           = 0
  ip_protocol       = "-1"
}

resource "aws_ecs_cluster" "this" {
  name = "${var.prefix}-news"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role = aws_iam_role.ecs_task_execution_role.arn
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  static_url = "https://${aws_cloudfront_distribution.cloudfront.domain_name}"
}

resource "aws_ecs_task_definition" "front_stack" {
  requires_compatibilities = ["FARGATE"]
  family = "${var.prefix}-front-stack"
  cpu = local.container_cpu
  memory = local.container_mem
  network_mode = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
        name = "quotes"
        image = "${local.ecr_url}quotes:${var.docker_image_tag}"
        essential = true
        portMappings = [
            {
                containerPort = 8082
                hostPort      = 8082
                protocol = "tcp"
            }
        ]
    },
    {
        name = "newsfeed"
        image = "${local.ecr_url}newsfeed:${var.docker_image_tag}"
        essential = true
        portMappings = [
            {
                containerPort = 8081
                hostPort      = 8081
                protocol = "tcp"
            }
        ]
    },
    {
        name = "front_end"
        image = "${local.ecr_url}front_end:${var.docker_image_tag}"
        essential = true
        portMappings = [
            {
                containerPort = 8080 
                hostPort      = 8080
                protocol = "tcp"
            }
        ]
        environment = [
            { name = "QUOTE_SERVICE_URL", value = "http://127.0.0.1:8082" },
            { name = "NEWSFEED_SERVICE_URL", value = "http://127.0.0.1:8081" },
            { name = "STATIC_URL", value = local.static_url }
        ]
    }
  ])
}


resource "aws_ecs_service" "front_stack" {
  name = "${var.prefix}-front-stack"
  cluster = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.front_stack.arn
  desired_count = 2
  launch_type = "FARGATE"

  network_configuration {
    subnets = local.subnet_ids
    security_groups = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.front_end_tg.arn
    container_name = "front_end"
    container_port = 8080
  }

  depends_on = [ aws_lb_listener.http ]
}

output "frontend_url" {
  value = "http://${aws_lb.alb.dns_name}"
}


