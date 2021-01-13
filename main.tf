### Data
data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnet_ids" "public" {
  vpc_id = "${data.aws_vpc.this.id}"
  filter {
    name   = "tag:Name"
    values = var.subnet_name
  }
}

data "aws_arn" "ecs_cluster" {
  arn = var.ecs_cluster
}

### Security
# Task security group
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name}-tasks"
  description = "allow inbound access from VPC"
  vpc_id      = data.aws_vpc.this.id

  ingress {
    protocol    = "tcp"
    from_port   = var.app_port
    to_port     = var.app_port
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

### ALB
# Target Group
resource "aws_lb_target_group" "app" {
  count = var.load_balancer == true ? 1 : 0

  name        = "${var.name}-lb"
  port        = var.lb_target_group_port
  protocol    = var.lb_target_group_protocol
  vpc_id      = data.aws_vpc.this.id
  target_type = var.lb_target_group_type

  dynamic "health_check" {
    for_each = var.health_check != null ? [1] : []

    content {
      enabled             = var.health_check.enabled
      healthy_threshold   = var.health_check.healthy_threshold
      interval            = var.health_check.interval
      matcher             = var.health_check.matcher
      path                = var.health_check.path
      port                = var.health_check.port
      protocol            = var.health_check.protocol
      timeout             = var.health_check.timeout
      unhealthy_threshold = var.health_check.unhealthy_threshold
    }
  }

  tags = var.tags
}

# Listener Rule Forward
resource "aws_lb_listener_rule" "forward" {
  count = var.load_balancer == true ? length(var.lb_listener_arn) : 0

  listener_arn = var.lb_listener_arn[count.index]
  priority     = var.lb_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.0.arn
  }

  dynamic "condition" {
    for_each = var.lb_host_header != null ? [1] : []

    content {
      host_header {
        values = var.lb_host_header
      }
    }
  }

  dynamic "condition" {
    for_each = var.lb_path_pattern != null ? [1] : []

    content {
      path_pattern {
        values = var.lb_path_pattern
      }
    }
  }
}

### CloudWatch log group
resource "aws_cloudwatch_log_group" "this" {
  name              = var.cloudwatch_log_group_name != "" ? var.cloudwatch_log_group_name : "/ecs/${var.name}"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

### Service Discovery
resource "aws_service_discovery_service" "service" {
  count = var.service_discovery_namespace_id != null ? 1 : 0

  name = var.name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

### ECS
resource "aws_iam_role" "execution_role" {
  name = "${var.name}-ecs-execution-role"

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

resource "aws_iam_role_policy" "execution_policy" {
  name = "${var.name}-ecs-execution-policy"
  role = aws_iam_role.execution_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "task_role" {
  name = "${var.name}-ecs-task-role"

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

resource "aws_iam_role_policy_attachment" "task_role" {
  count      = length(var.policies)
  role       = aws_iam_role.task_role.name
  policy_arn = var.policies[count.index]
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  dynamic "volume" {
    for_each = var.efs_volume_configuration == [] ? [] : [for v in var.efs_volume_configuration : {
      name                    = v.name
      file_system_id          = v.file_system_id
      root_directory          = v.root_directory
      transit_encryption      = v.transit_encryption
      transit_encryption_port = v.transit_encryption_port
      access_point_id         = v.authorization_config_access_point_id
      iam                     = v.authorization_config_iam
    }]

    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = volume.value.root_directory
        transit_encryption      = volume.value.transit_encryption
        transit_encryption_port = volume.value.transit_encryption_port
        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = volume.value.iam
        }
      }
    }
  }

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.fargate_cpu},
    "image": "${var.image_uri}",
    "memory": ${var.fargate_memory},
    "name": "${var.name}",
    "networkMode": "awsvpc",
    "essential": ${var.fargate_essential},
    "logConfiguration": { 
       "logDriver": "awslogs",
       "options": { 
          "awslogs-group" : "${aws_cloudwatch_log_group.this.name}",
          "awslogs-region": "${var.region}",
          "awslogs-stream-prefix": "ecs"
       }
    },
    "portMappings": [
      {
        "containerPort": ${var.app_port},
        "hostPort": ${var.app_port}
      }
    ],
    "environment": ${jsonencode(var.app_environment)},
    "mountPoints": ${jsonencode(var.efs_mount_configuration)}
  }
]
DEFINITION

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  count = var.ecs_service == true ? 1 : 0

  name             = "${var.name}-service"
  cluster          = var.ecs_cluster
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = var.ecs_service_desired_count
  launch_type      = var.capacity_provider_strategy == null ? "FARGATE" : null
  propagate_tags   = "SERVICE"
  platform_version = var.platform_version

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = data.aws_subnet_ids.public.ids
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer == true ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.app.0.id
      container_name   = var.name
      container_port   = var.app_port
    }
  }

  dynamic "service_registries" {
    for_each = var.service_discovery_namespace_id != null ? [1] : []

    content {
      registry_arn = aws_service_discovery_service.service.0.arn
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy != null ? [1] : []

    content {
      capacity_provider = var.capacity_provider_strategy.capacity_provider
      weight            = var.capacity_provider_strategy.weight
      base              = var.capacity_provider_strategy.base
    }
  }

  depends_on = [
    aws_lb_listener_rule.forward
  ]

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.tags
}

## ECS Service Autoscaling
resource "aws_appautoscaling_target" "ecs_target" {
  count = var.autoscaling == true ? 1 : 0

  max_capacity       = var.autoscaling_settings.max_capacity
  min_capacity       = var.autoscaling_settings.min_capacity
  resource_id        = "service/${trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")}/${aws_ecs_service.this.0.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy" {
  count = var.autoscaling == true ? 1 : 0

  name               = "${var.name}-scale-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.0.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.0.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.0.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.autoscaling_settings.target_cpu_value
    scale_in_cooldown  = var.autoscaling_settings.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_settings.scale_out_cooldown
  }
}
