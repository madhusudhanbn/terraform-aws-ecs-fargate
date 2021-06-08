### Data
data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnet_ids" "public" {
  vpc_id = data.aws_vpc.this.id
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

  dynamic "stickiness" {
    for_each = var.lb_stickiness != null ? [1] : []

    content {
      type            = var.lb_stickiness.type
      cookie_duration = var.lb_stickiness.cookie_duration
      enabled         = var.lb_stickiness.enabled
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

resource "aws_iam_policy" "ssm_policy" {
  name = "${var.name}-ecs-ssm-policy"

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

resource "aws_iam_role_policy_attachment" "task_role_ssm" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
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

  name                   = "${var.name}-service"
  cluster                = var.ecs_cluster
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.ecs_service_desired_count
  launch_type            = var.capacity_provider_strategy == null ? "FARGATE" : null
  propagate_tags         = "SERVICE"
  platform_version       = var.platform_version
  enable_execute_command = true

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker == true ? [1] : []

    content {
      enable   = true
      rollback = true
    }
  }

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = data.aws_subnet_ids.public.ids
    assign_public_ip = var.assign_public_ip
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

  max_capacity       = lookup(var.autoscaling_settings, "max_capacity", 1)
  min_capacity       = lookup(var.autoscaling_settings, "min_capacity", 1)
  resource_id        = "service/${trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")}/${aws_ecs_service.this.0.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  count = var.autoscaling == true && lookup(var.autoscaling_settings, "target_cpu_value", null) != null ? 1 : 0

  name               = "${var.name}-scale-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.0.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.0.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.0.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = lookup(var.autoscaling_settings, "target_cpu_value", 0)
    scale_in_cooldown  = var.autoscaling_settings.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_settings.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "ecs_policy_memory" {
  count = var.autoscaling == true && lookup(var.autoscaling_settings, "target_memory_value", null) != null ? 1 : 0

  name               = "${var.name}-scale-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.0.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.0.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.0.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = lookup(var.autoscaling_settings, "target_memory_value", 0)
    scale_in_cooldown  = var.autoscaling_settings.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_settings.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "ecs_policy_requests" {
  count = var.autoscaling == true && lookup(var.autoscaling_settings, "target_request_value", null) != null ? 1 : 0

  name               = "${var.name}-scale-request"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.0.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.0.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.0.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.lb_arn_suffix}/${aws_lb_target_group.app.0.arn_suffix}"
    }

    target_value       = lookup(var.autoscaling_settings, "target_request_value", 0)
    scale_in_cooldown  = var.autoscaling_settings.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_settings.scale_out_cooldown
  }
}

## CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "ecs_service_cpu" {
  count = lookup(var.cloudwatch_settings, "enabled", false) == true && lookup(var.cloudwatch_settings, "cpu_threshold", false) != false ? 1 : 0

  alarm_name          = "${var.cloudwatch_settings.prefix}-ECS-${trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")}/${aws_ecs_service.this.0.name}->High-CPU-Utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  threshold           = var.cloudwatch_settings.cpu_threshold

  metric_query {
    id          = "m0r0"
    return_data = false

    metric {
      dimensions = {
        "ClusterName" = trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")
        "ServiceName" = aws_ecs_service.this.0.name
      }
      metric_name = "CpuUtilized"
      namespace   = "ECS/ContainerInsights"
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    id          = "m0r1"
    return_data = false

    metric {
      dimensions = {
        "ClusterName" = trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")
        "ServiceName" = aws_ecs_service.this.0.name
      }
      metric_name = "CpuReserved"
      namespace   = "ECS/ContainerInsights"
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    expression  = "m0r0 * 100 / m0r1"
    id          = "e0"
    label       = aws_ecs_service.this.0.name
    return_data = true
  }

  alarm_actions = var.cloudwatch_settings.sns_topic_arn
  ok_actions    = var.cloudwatch_settings.sns_topic_arn

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_service_memory" {
  count = lookup(var.cloudwatch_settings, "enabled", false) == true && lookup(var.cloudwatch_settings, "memory_threshold", false) != false ? 1 : 0

  alarm_name          = "${var.cloudwatch_settings.prefix}-ECS-${trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")}/${aws_ecs_service.this.0.name}->High-Memory-Utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  threshold           = var.cloudwatch_settings.memory_threshold

  metric_query {
    id          = "m0r0"
    return_data = false

    metric {
      dimensions = {
        "ClusterName" = trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")
        "ServiceName" = aws_ecs_service.this.0.name
      }
      metric_name = "MemoryUtilized"
      namespace   = "ECS/ContainerInsights"
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    id          = "m0r1"
    return_data = false

    metric {
      dimensions = {
        "ClusterName" = trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")
        "ServiceName" = aws_ecs_service.this.0.name
      }
      metric_name = "MemoryReserved"
      namespace   = "ECS/ContainerInsights"
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    expression  = "m0r0 * 100 / m0r1"
    id          = "e0"
    label       = aws_ecs_service.this.0.name
    return_data = true
  }

  alarm_actions = var.cloudwatch_settings.sns_topic_arn
  ok_actions    = var.cloudwatch_settings.sns_topic_arn

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_service_max_task_count" {
  count = lookup(var.cloudwatch_settings, "enabled", false) == true && lookup(var.cloudwatch_settings, "max_task_count", false) != false ? 1 : 0

  alarm_name          = "${var.cloudwatch_settings.prefix}-ECS-${trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")}/${aws_ecs_service.this.0.name}->High-Task-Count"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = "3600"
  statistic           = "Average"
  threshold           = var.cloudwatch_settings.max_task_count

  dimensions = {
    ClusterName = trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")
    ServiceName = aws_ecs_service.this.0.name
  }

  alarm_actions = var.cloudwatch_settings.sns_topic_arn
  ok_actions    = var.cloudwatch_settings.sns_topic_arn

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_service_min_task_count" {
  count = lookup(var.cloudwatch_settings, "enabled", false) == true && lookup(var.cloudwatch_settings, "min_task_count", false) != false ? 1 : 0

  alarm_name          = "${var.cloudwatch_settings.prefix}-ECS-${trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")}/${aws_ecs_service.this.0.name}->Low-Task-Count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = "900"
  statistic           = "Average"
  threshold           = var.cloudwatch_settings.min_task_count

  dimensions = {
    ClusterName = trimprefix(data.aws_arn.ecs_cluster.resource, "cluster/")
    ServiceName = aws_ecs_service.this.0.name
  }

  alarm_actions = var.cloudwatch_settings.sns_topic_arn
  ok_actions    = var.cloudwatch_settings.sns_topic_arn

  tags = var.tags
}
