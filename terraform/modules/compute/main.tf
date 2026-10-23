resource "aws_ecr_repository" "this" {
  name                 = "${var.name}-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = merge(var.tags, { Name = "${var.name}-api" })
}
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = var.tags
}
resource "aws_iam_role" "ecs_instance" {
  name = "${var.name}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_instance_profile" "ecs" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name}-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  tags               = var.tags
}
resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = var.tags
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}
resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.name}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs.name
  }
  vpc_security_group_ids = [var.ecs_security_group_id]

  user_data = base64encode(<<-EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config

dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/ec2/${var.name}/system",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/ecs/ecs-agent.log",
            "log_group_name": "/ec2/${var.name}/ecs-agent",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-ecs-instance" })
  }
}
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.name}-ecs-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = var.private_subnet_ids
  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
  tag {
    key                 = "Name"
    value               = "${var.name}-ecs-instance"
    propagate_at_launch = true
  }
}
resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-capacity"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
    managed_termination_protection = "DISABLED"
  }
}
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }
}
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}-database-credentials"
  description             = "TaskFlow database credentials"
  recovery_window_in_days = 7
  tags                    = var.tags
}
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name}/api"
  retention_in_days = 7
  tags              = var.tags
}

data "aws_region" "current" {}

resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.name}-ecs-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn



  container_definitions = jsonencode([{
    name      = "taskflow-api"
    image     = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory

    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT", value = tostring(var.container_port) },
      { name = "DB_HOST", value = var.db_endpoint },
      { name = "DB_PORT", value = "5432" },
      { name = "DB_NAME", value = var.db_name }
    ]

    secrets = [
      {
        name      = "DB_USER"
        valueFrom = "${aws_secretsmanager_secret.db.arn}:username::"
      },
      {
        name      = "DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db.arn}:password::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "taskflow"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name            = "${var.name}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "taskflow-api"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_cluster_capacity_providers.this,
    aws_iam_role_policy.ecs_secrets
  ]
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_log_group" "ec2_system" {
  name              = "/ec2/${var.name}/system"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "ec2_agent" {
  name              = "/ec2/${var.name}/ecs-agent"
  retention_in_days = 7
  tags              = var.tags
}

