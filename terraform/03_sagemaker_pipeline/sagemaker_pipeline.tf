resource "aws_sagemaker_pipeline" "this" {
  pipeline_name         = var.pipeline_name
  pipeline_display_name = var.pipeline_name
  role_arn              = aws_iam_role.pipeline_execution.arn
  pipeline_definition   = local.pipeline_definition

  tags = merge(local.required_tags, {
    module = "03_sagemaker_pipeline"
    usage  = "modelbuild-pipeline"
  })

  depends_on = [
    aws_iam_role_policy.pipeline_permissions,
    aws_sagemaker_model_package_group.this
  ]
}
