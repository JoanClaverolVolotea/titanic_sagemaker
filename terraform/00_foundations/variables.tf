variable "aws_region" {
  description = "AWS region for this environment."
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

variable "project" {
  description = "Project tag value."
  type        = string
  default     = "titanic-sagemaker"

  validation {
    condition     = var.project == "titanic-sagemaker"
    error_message = "project must be titanic-sagemaker."
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
  description = "Main S3 bucket for Titanic tutorial datasets and artifacts."
  type        = string
  default     = "titanic-data-bucket-939122281183-data-science-user"
}

variable "create_data_bucket" {
  description = "Set to false if the bucket already exists and is managed elsewhere."
  type        = bool
  default     = true
}
