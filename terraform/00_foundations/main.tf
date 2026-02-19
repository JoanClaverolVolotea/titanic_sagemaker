data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "tutorial_data" {
  count  = var.create_data_bucket ? 1 : 0
  bucket = var.data_bucket_name

  tags = merge(
    local.required_tags,
    {
      module = "00_foundations"
      usage  = "datasets-and-artifacts"
    }
  )
}

resource "aws_s3_bucket_ownership_controls" "tutorial_data" {
  count  = var.create_data_bucket ? 1 : 0
  bucket = aws_s3_bucket.tutorial_data[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "tutorial_data" {
  count  = var.create_data_bucket ? 1 : 0
  bucket = aws_s3_bucket.tutorial_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tutorial_data" {
  count  = var.create_data_bucket ? 1 : 0
  bucket = aws_s3_bucket.tutorial_data[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tutorial_data" {
  count  = var.create_data_bucket ? 1 : 0
  bucket = aws_s3_bucket.tutorial_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "enforce_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      "arn:aws:s3:::${var.data_bucket_name}",
      "arn:aws:s3:::${var.data_bucket_name}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tutorial_data" {
  count  = var.create_data_bucket ? 1 : 0
  bucket = aws_s3_bucket.tutorial_data[0].id
  policy = data.aws_iam_policy_document.enforce_tls.json
}
