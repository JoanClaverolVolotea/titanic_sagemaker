data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "pipeline_assume_role" {
  statement {
    sid     = "AllowSageMakerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline_execution" {
  name               = var.pipeline_role_name
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume_role.json

  tags = merge(local.required_tags, {
    module = "03_sagemaker_pipeline"
    usage  = "pipeline-execution-role"
  })
}

data "aws_iam_policy_document" "pipeline_permissions" {
  statement {
    sid    = "ReadCuratedAndPipelineCode"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${var.data_bucket_name}/curated/*",
      "arn:aws:s3:::${var.data_bucket_name}/pipeline/code/*"
    ]
  }

  statement {
    sid    = "ListDataBucketPrefixes"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      "arn:aws:s3:::${var.data_bucket_name}"
    ]
  }

  statement {
    sid    = "WriteRuntimeArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      "arn:aws:s3:::${var.data_bucket_name}/pipeline/runtime/*"
    ]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*:log-stream:*"
    ]
  }

  statement {
    sid    = "AllowEcrImagePull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowSageMakerRuntimeActions"
    effect = "Allow"
    actions = [
      "sagemaker:AddTags",
      "sagemaker:CreateExperiment",
      "sagemaker:CreateModel",
      "sagemaker:CreateModelPackage",
      "sagemaker:CreateModelPackageGroup",
      "sagemaker:CreateProcessingJob",
      "sagemaker:CreateTrainingJob",
      "sagemaker:CreateTrial",
      "sagemaker:CreateTrialComponent",
      "sagemaker:Describe*",
      "sagemaker:List*",
      "sagemaker:StopProcessingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:UpdateModelPackage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowPassRoleToSageMaker"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.pipeline_execution.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "pipeline_permissions" {
  name   = "${var.pipeline_role_name}-policy"
  role   = aws_iam_role.pipeline_execution.id
  policy = data.aws_iam_policy_document.pipeline_permissions.json
}
