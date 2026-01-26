locals {
  s3_train_uri      = "s3://${var.data_bucket}/${var.data_prefix}/titanic.csv"
  s3_validation_uri = "s3://${var.data_bucket}/${var.data_prefix}/titanic_validation.csv"
}
