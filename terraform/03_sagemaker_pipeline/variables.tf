variable "aws_region" {
  description = "AWS region for the stack."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile used by Terraform."
  type        = string
  default     = "data-science-user"

  validation {
    condition     = var.aws_profile == "data-science-user"
    error_message = "aws_profile must be data-science-user according to project policy."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either dev or prod."
  }
}

variable "project_name" {
  description = "Project tag value."
  type        = string
  default     = "titanic-sagemaker"

  validation {
    condition     = var.project_name == "titanic-sagemaker"
    error_message = "project_name must be titanic-sagemaker."
  }
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "data-science-user"

  validation {
    condition     = length(trim(var.owner, " ")) > 0
    error_message = "owner cannot be empty."
  }
}

variable "cost_center" {
  description = "Cost center tag value."
  type        = string
  default     = "data-science"

  validation {
    condition     = length(trim(var.cost_center, " ")) > 0
    error_message = "cost_center cannot be empty."
  }
}

variable "data_bucket_name" {
  description = "S3 bucket that stores curated data and pipeline artifacts."
  type        = string
}

variable "code_bundle_s3_prefix" {
  description = "S3 prefix where code bundles are uploaded."
  type        = string
  default     = "pipeline/code"
}

variable "code_bundle_uri" {
  description = "Immutable S3 URI for the code bundle used as pipeline parameter default."
  type        = string

  validation {
    condition     = can(regex("^s3://", var.code_bundle_uri))
    error_message = "code_bundle_uri must start with s3://"
  }
}

variable "pipeline_name" {
  description = "Name of the SageMaker pipeline."
  type        = string
  default     = "titanic-modelbuild-dev"
}

variable "model_package_group_name" {
  description = "Name of the SageMaker Model Package Group."
  type        = string
  default     = "titanic-survival-xgboost"
}

variable "quality_threshold_accuracy" {
  description = "Accuracy threshold used by the quality gate."
  type        = number
  default     = 0.78
}

variable "model_approval_status" {
  description = "Initial approval status for registered model packages."
  type        = string
  default     = "PendingManualApproval"

  validation {
    condition = contains([
      "Approved",
      "PendingManualApproval",
      "Rejected"
    ], var.model_approval_status)
    error_message = "model_approval_status must be Approved, PendingManualApproval, or Rejected."
  }
}

variable "pipeline_role_name" {
  description = "IAM role name used by SageMaker Pipeline executions."
  type        = string
  default     = "titanic-sagemaker-pipeline-dev"
}

variable "processing_image_uri" {
  description = "Container image used by processing steps."
  type        = string
  default     = "141502667606.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
}

variable "evaluation_image_uri" {
  description = "Container image used by model evaluation processing step."
  type        = string
  default     = "141502667606.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-xgboost:1.7-1"
}

variable "training_image_uri" {
  description = "Container image used by training and registration steps."
  type        = string
  default     = "141502667606.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-xgboost:1.7-1"
}
