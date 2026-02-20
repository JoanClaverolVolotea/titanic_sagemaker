locals {
  required_tags = {
    project     = var.project_name
    env         = var.environment
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = var.cost_center
  }

  pipeline_definition = templatefile("${path.module}/pipeline_definition.json.tpl", {
    code_bundle_uri            = var.code_bundle_uri
    data_bucket_name           = var.data_bucket_name
    pipeline_name              = var.pipeline_name
    pipeline_role_arn          = aws_iam_role.pipeline_execution.arn
    processing_image_uri       = var.processing_image_uri
    evaluation_image_uri       = var.evaluation_image_uri
    training_image_uri         = var.training_image_uri
    model_package_group_name   = aws_sagemaker_model_package_group.this.model_package_group_name
    quality_threshold_accuracy = var.quality_threshold_accuracy
    model_approval_status      = var.model_approval_status
  })
}
