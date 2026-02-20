resource "aws_sagemaker_model_package_group" "this" {
  model_package_group_name        = var.model_package_group_name
  model_package_group_description = "Model packages for Titanic survival model (${var.environment})"

  tags = merge(local.required_tags, {
    module = "03_sagemaker_pipeline"
    usage  = "model-registry"
  })
}
