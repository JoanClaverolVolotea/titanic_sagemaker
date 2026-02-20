output "pipeline_name" {
  description = "Name of the SageMaker pipeline."
  value       = aws_sagemaker_pipeline.this.pipeline_name
}

output "pipeline_arn" {
  description = "ARN of the SageMaker pipeline."
  value       = aws_sagemaker_pipeline.this.arn
}

output "pipeline_execution_role_arn" {
  description = "IAM role ARN used by the pipeline runtime."
  value       = aws_iam_role.pipeline_execution.arn
}

output "model_package_group_name" {
  description = "Model Package Group name used for registration."
  value       = aws_sagemaker_model_package_group.this.model_package_group_name
}

output "model_package_group_arn" {
  description = "Model Package Group ARN."
  value       = aws_sagemaker_model_package_group.this.arn
}
