variable "aws_region" {
  type        = string
  description = "Region AWS"
}

variable "data_bucket" {
  type        = string
  description = "Bucket con los datos de Titanic"
}

variable "data_prefix" {
  type        = string
  description = "Prefijo base de los datos en S3"
}

variable "project_name" {
  type        = string
  description = "Nombre del proyecto"
}

variable "environment" {
  type        = string
  description = "Entorno (dev, prod, etc.)"
  validation {
    condition     = contains(["dev", "prod", "staging"], var.environment)
    error_message = "environment debe ser uno de: dev, prod, staging."
  }
}
