output "task_definition_arn" {
  value       = aws_ecs_task_definition.app.arn
  sensitive   = false
  description = "The ARN of the task definition."
  depends_on  = []
}

output "task_security_group_id" {
  value       = aws_security_group.ecs_tasks.id
  sensitive   = false
  description = "description"
  depends_on  = []
}
