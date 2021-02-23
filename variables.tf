variable "name" {
  type        = string
  description = "Used to name resources and prefixes."
}

variable "tags" {
  description = "A mapping of tags to assign to all resources."
  type        = map(string)
  default     = {}
}

variable "image_uri" {
  type        = string
  description = "The container image URI."
}

variable "app_port" {
  type        = number
  description = "The application TCP port number."
}

variable "app_environment" {
  type        = list(any)
  default     = []
  description = "List of one or more environment variables to be inserted in the container."
}

variable "region" {
  type        = string
  description = "The AWS region."
}

variable "fargate_cpu" {
  type        = number
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)."
  default     = 256
}

variable "fargate_memory" {
  type        = number
  description = "Fargate instance memory to provision (in MiB)."
  default     = 512
}

variable "vpc_name" {
  type        = string
  description = "The VPC name where the task will be performed."
}

variable "subnet_name" {
  type        = list(any)
  description = "List of one or more subnet names where the task will be performed."
}

variable "ecs_cluster" {
  type        = string
  default     = ""
  description = "The ARN of ECS cluster."
}

variable "load_balancer" {
  type        = bool
  default     = false
  description = "Boolean designating a load balancer."
}

variable "ecs_service" {
  type        = bool
  default     = false
  description = "Boolean designating a service."
}

variable "policies" {
  type        = list(any)
  default     = []
  description = "List of one or more IAM policy ARN to be used in the Task execution IAM role."
}

variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "The number of days to retain log in CloudWatch."
}

variable "cloudwatch_log_group_name" {
  type        = string
  default     = ""
  description = "The name of an existing CloudWatch group."
}

variable "health_check" {
  type        = map(any)
  default     = null
  description = "Health check in Load Balance target group."
}

variable "service_discovery_namespace_id" {
  type        = string
  default     = null
  description = "Service Discovery Namespace ID."
}

variable "ecs_service_desired_count" {
  type        = number
  default     = 1
  description = "The number of instances of the task definition to place and keep running."
}

variable "fargate_essential" {
  type        = bool
  default     = true
  description = "Boolean designating a Fargate essential container."
}

variable "lb_target_group_protocol" {
  type        = string
  default     = "HTTP"
  description = "The protocol to use for routing traffic to the targets. Should be one of TCP, TLS, UDP, TCP_UDP, HTTP or HTTPS."
}

variable "lb_target_group_port" {
  type        = number
  default     = 80
  description = "The port on which targets receive traffic, unless overridden when registering a specific target."
}

variable "lb_target_group_type" {
  type        = string
  default     = "ip"
  description = "The type of target that you must specify when registering targets with this target group."
}

variable "lb_listener_arn" {
  type        = list(any)
  default     = [""]
  description = "List of ARN LB listeners"
}

variable "lb_host_header" {
  type        = list(any)
  default     = null
  description = "List of host header patterns to match."
}

variable "lb_path_pattern" {
  type        = list(any)
  default     = null
  description = "List of path patterns to match."
}

variable "capacity_provider_strategy" {
  type        = map(any)
  default     = null
  description = "The capacity provider strategy to use for the service."
}

variable "lb_priority" {
  type        = number
  default     = null
  description = "The priority for the rule between 1 and 50000."
}

variable "autoscaling" {
  type        = bool
  default     = false
  description = "Boolean designating an Auto Scaling."
}

variable "autoscaling_settings" {
  type = map(any)
  default = {
    max_capacity       = 0
    min_capacity       = 0
    target_cpu_value   = 0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
  description = "Settings of Auto Scaling."
}

variable "platform_version" {
  type        = string
  default     = "LATEST"
  description = "The Fargate platform version on which to run your service."
}

variable "efs_volume_configuration" {
  type        = list(any)
  default     = []
  description = "Settings of EFS volume configuration."
}

variable "efs_mount_configuration" {
  type        = list(any)
  default     = []
  description = "Settings of EFS mount configuration."
}

variable "lb_stickiness" {
  type        = map(any)
  default     = null
  description = "LB Stickiness block."
}
