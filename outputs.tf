output task_definition_arn {
  value       = aws_ecs_task_definition.app.arn
  sensitive   = false
  description = "The ARN of the task definition."
  depends_on  = []
}
