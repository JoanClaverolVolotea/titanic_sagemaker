output "foundation_account_id" {
  description = "AWS account where foundations are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "foundation_region" {
  description = "AWS region used by the stack."
  value       = data.aws_region.current.name
}

output "foundation_tags" {
  description = "Mandatory tag set applied through default_tags."
  value       = local.required_tags
}

output "data_bucket_name" {
  description = "S3 bucket used by tutorial phases 01+."
  value       = var.data_bucket_name
}

output "data_bucket_arn" {
  description = "S3 bucket ARN when created by this stack."
  value       = var.create_data_bucket ? aws_s3_bucket.tutorial_data[0].arn : "not-managed-by-this-stack"
}
