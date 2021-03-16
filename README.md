# AWS ECS Fargate Terraform module
Terraform module which provides tasks definitions, services, scaling and load balancing to ECS powered by AWS Fargate.

## Terraform versions

Terraform >= 0.12

## Usage

```hcl
## Locals
locals {
  tags = {
    environment = "development"
  }
}

## Data
data "aws_lb" "this" {
  name = "my-alb"
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.this.arn
  port              = 443
}

data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.this.arn
  port              = 80
}

## ECS Cluster
module "ecs_cluster" {
  source  = "brunordias/ecs-cluster/aws"
  version = "~> 1.0.0"

  name               = "terraform-ecs-test"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = {
    capacity_provider = "FARGATE_SPOT"
    weight            = null
    base              = null
  }
  container_insights = "enabled"

  tags = local.tags
}

## ECS Fargate
module "ecs_fargate" {
  source  = "brunordias/ecs-fargate/aws"
  version = "~> 2.0.0"

  name                      = "nginx"
  region                    = "us-east-1"
  ecs_cluster               = module.ecs_cluster.id
  image_uri                 = "public.ecr.aws/nginx/nginx:1.19-alpine"
  platform_version          = "1.4.0"
  vpc_name                  = "default"
  subnet_name               = ["public-d", "public-e"]
  fargate_cpu               = 256
  fargate_memory            = 512
  ecs_service_desired_count = 2
  app_port                  = 80
  load_balancer             = true
  ecs_service               = true
  policies = [
    "arn:aws:iam::aws:policy/example"
  ]
  lb_listener_arn = [
    data.aws_lb_listener.https.arn,
    data.aws_lb_listener.http.arn
  ]
  lb_path_pattern = [
    "/v1"
  ]
  lb_host_header = ["app.example.com"]
  lb_priority    = 101
  health_check = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/index.html"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 10
  }
  capacity_provider_strategy = {
    capacity_provider = "FARGATE_SPOT"
    weight            = 100
    base              = null
  }
  autoscaling = true
  autoscaling_settings = {
    max_capacity       = 4
    min_capacity       = 1
    target_cpu_value   = 60
    scale_in_cooldown  = 60
    scale_out_cooldown = 900
  }
  app_environment = [
    {
      "name" : "environment",
      "value" : "development"
    },
  ]
  efs_volume_configuration = [
    {
      name                                 = "efs-example"
      file_system_id                       = "fs-xxxxxx"
      root_directory                       = "/"
      transit_encryption                   = null
      transit_encryption_port              = null
      authorization_config_access_point_id = null
      authorization_config_iam             = null
    }
  ]
  efs_mount_configuration = [
    {
      "sourceVolume" : "efs-example",
      "containerPath" : "/mount",
      "readOnly" : false
    }
  ]

  tags = local.tags
}
```

## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| aws | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| app\_environment | List of one or more environment variables to be inserted in the container. | `list(any)` | `[]` | no |
| app\_port | The application TCP port number. | `number` | n/a | yes |
| assign\_public\_ip | Assign a public IP address to the ENI | `bool` | `true` | no |
| autoscaling | Boolean designating an Auto Scaling. | `bool` | `false` | no |
| autoscaling\_settings | Settings of Auto Scaling. | `map(any)` | <pre>{<br>  "max_capacity": 0,<br>  "min_capacity": 0,<br>  "scale_in_cooldown": 300,<br>  "scale_out_cooldown": 300,<br>  "target_cpu_value": 0<br>}</pre> | no |
| capacity\_provider\_strategy | The capacity provider strategy to use for the service. | `map(any)` | `null` | no |
| cloudwatch\_log\_group\_name | The name of an existing CloudWatch group. | `string` | `""` | no |
| cloudwatch\_settings | Settings of Cloudwatch Alarms. | `any` | `{}` | no |
| ecs\_cluster | The ARN of ECS cluster. | `string` | `""` | no |
| ecs\_service | Boolean designating a service. | `bool` | `false` | no |
| ecs\_service\_desired\_count | The number of instances of the task definition to place and keep running. | `number` | `1` | no |
| efs\_mount\_configuration | Settings of EFS mount configuration. | `list(any)` | `[]` | no |
| efs\_volume\_configuration | Settings of EFS volume configuration. | `list(any)` | `[]` | no |
| fargate\_cpu | Fargate instance CPU units to provision (1 vCPU = 1024 CPU units). | `number` | `256` | no |
| fargate\_essential | Boolean designating a Fargate essential container. | `bool` | `true` | no |
| fargate\_memory | Fargate instance memory to provision (in MiB). | `number` | `512` | no |
| health\_check | Health check in Load Balance target group. | `map(any)` | `null` | no |
| image\_uri | The container image URI. | `string` | n/a | yes |
| lb\_arn\_suffix | The ARN suffix for use with Auto Scaling ALB requests per target. | `string` | `""` | no |
| lb\_host\_header | List of host header patterns to match. | `list(any)` | `null` | no |
| lb\_listener\_arn | List of ARN LB listeners | `list(any)` | <pre>[<br>  ""<br>]</pre> | no |
| lb\_path\_pattern | List of path patterns to match. | `list(any)` | `null` | no |
| lb\_priority | The priority for the rule between 1 and 50000. | `number` | `null` | no |
| lb\_stickiness | LB Stickiness block. | `map(any)` | `null` | no |
| lb\_target\_group\_port | The port on which targets receive traffic, unless overridden when registering a specific target. | `number` | `80` | no |
| lb\_target\_group\_protocol | The protocol to use for routing traffic to the targets. Should be one of TCP, TLS, UDP, TCP\_UDP, HTTP or HTTPS. | `string` | `"HTTP"` | no |
| lb\_target\_group\_type | The type of target that you must specify when registering targets with this target group. | `string` | `"ip"` | no |
| load\_balancer | Boolean designating a load balancer. | `bool` | `false` | no |
| log\_retention\_in\_days | The number of days to retain log in CloudWatch. | `number` | `7` | no |
| name | Used to name resources and prefixes. | `string` | n/a | yes |
| platform\_version | The Fargate platform version on which to run your service. | `string` | `"LATEST"` | no |
| policies | List of one or more IAM policy ARN to be used in the Task execution IAM role. | `list(any)` | `[]` | no |
| region | The AWS region. | `string` | n/a | yes |
| service\_discovery\_namespace\_id | Service Discovery Namespace ID. | `string` | `null` | no |
| subnet\_name | List of one or more subnet names where the task will be performed. | `list(any)` | n/a | yes |
| tags | A mapping of tags to assign to all resources. | `map(string)` | `{}` | no |
| vpc\_name | The VPC name where the task will be performed. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| task\_definition\_arn | The ARN of the task definition. |
| task\_security\_group\_id | The id of the Security Group used in tasks. |

## Authors

Module managed by [Bruno Dias](https://github.com/brunordias).

## License

Apache 2 Licensed. See LICENSE for full details.