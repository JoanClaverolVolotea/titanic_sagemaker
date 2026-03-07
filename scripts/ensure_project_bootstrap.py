#!/usr/bin/env python3
"""Ensure no-Terraform durable resources exist for the Titanic SageMaker project."""

from __future__ import annotations

import argparse
import json
from typing import Any

import boto3
from botocore.exceptions import ClientError

from resolve_project_env import build_env, load_manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", help="Path to config/project-manifest.json")
    parser.add_argument("--apply", action="store_true", help="Create/update resources.")
    parser.add_argument("--check", action="store_true", help="Validate resources only.")
    return parser.parse_args()


def require_mode(args: argparse.Namespace) -> str:
    if args.apply and args.check:
        raise SystemExit("Choose only one mode: --apply or --check")
    if args.apply:
        return "apply"
    if args.check:
        return "check"
    return "check"


def tags_to_aws(tags: dict[str, str]) -> list[dict[str, str]]:
    return [{"Key": key, "Value": value} for key, value in tags.items()]


def build_boto_session(env: dict[str, str]) -> boto3.Session:
    profile = env.get("AWS_PROFILE", "")
    region = env["AWS_REGION"]
    available_profiles = boto3.session.Session().available_profiles
    if profile and profile in available_profiles:
        return boto3.Session(profile_name=profile, region_name=region)
    return boto3.Session(region_name=region)


def resource_tags(manifest: dict[str, Any], module: str, usage: str) -> dict[str, str]:
    return {
        "project": str(manifest["project_name"]),
        "env": str(manifest["environment"]),
        "owner": str(manifest["owner"]),
        "managed_by": str(manifest["managed_by"]),
        "cost_center": str(manifest["cost_center"]),
        "module": module,
        "usage": usage,
    }


def bucket_policy(bucket_name: str) -> str:
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "DenyInsecureTransport",
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "s3:*",
                    "Resource": [
                        f"arn:aws:s3:::{bucket_name}",
                        f"arn:aws:s3:::{bucket_name}/*",
                    ],
                    "Condition": {"Bool": {"aws:SecureTransport": "false"}},
                }
            ],
        }
    )


def assume_role_policy() -> str:
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"Service": "sagemaker.amazonaws.com"},
                    "Action": "sts:AssumeRole",
                }
            ],
        }
    )


def pipeline_inline_policy(manifest: dict[str, Any], env: dict[str, str]) -> str:
    bucket_name = env["DATA_BUCKET"]
    region = env["AWS_REGION"]
    account_id = env["ACCOUNT_ID"]
    pipeline_role_arn = env["SAGEMAKER_PIPELINE_ROLE_ARN"]

    payload = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "ReadCuratedAndPipelineCode",
                "Effect": "Allow",
                "Action": ["s3:GetObject"],
                "Resource": [
                    f"arn:aws:s3:::{bucket_name}/curated/*",
                    f"arn:aws:s3:::{bucket_name}/pipeline/code/*",
                ],
            },
            {
                "Sid": "ListDataBucketPrefixes",
                "Effect": "Allow",
                "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
                "Resource": [f"arn:aws:s3:::{bucket_name}"],
            },
            {
                "Sid": "WriteRuntimeArtifacts",
                "Effect": "Allow",
                "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
                "Resource": [f"arn:aws:s3:::{bucket_name}/pipeline/runtime/*"],
            },
            {
                "Sid": "AllowCloudWatchLogs",
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:DescribeLogStreams",
                    "logs:PutLogEvents",
                ],
                "Resource": [
                    f"arn:aws:logs:{region}:{account_id}:log-group:/aws/sagemaker/*",
                    f"arn:aws:logs:{region}:{account_id}:log-group:/aws/sagemaker/*:log-stream:*",
                ],
            },
            {
                "Sid": "AllowEcrImagePull",
                "Effect": "Allow",
                "Action": [
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                ],
                "Resource": "*",
            },
            {
                "Sid": "AllowSageMakerRuntimeActions",
                "Effect": "Allow",
                "Action": [
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
                    "sagemaker:UpdateModelPackage",
                ],
                "Resource": "*",
            },
            {
                "Sid": "AllowPassRoleToSageMaker",
                "Effect": "Allow",
                "Action": ["iam:PassRole"],
                "Resource": [pipeline_role_arn],
                "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}},
            },
        ],
    }
    return json.dumps(payload)


def execution_inline_policy(env: dict[str, str]) -> str:
    bucket_name = env["DATA_BUCKET"]
    region = env["AWS_REGION"]
    account_id = env["ACCOUNT_ID"]

    payload = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "ReadCuratedAndPipelineCode",
                "Effect": "Allow",
                "Action": ["s3:GetObject"],
                "Resource": [
                    f"arn:aws:s3:::{bucket_name}/curated/*",
                    f"arn:aws:s3:::{bucket_name}/pipeline/code/*",
                ],
            },
            {
                "Sid": "ListDataBucketPrefixes",
                "Effect": "Allow",
                "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
                "Resource": [f"arn:aws:s3:::{bucket_name}"],
            },
            {
                "Sid": "WriteTrainingEvaluationAndRuntimeArtifacts",
                "Effect": "Allow",
                "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
                "Resource": [
                    f"arn:aws:s3:::{bucket_name}/training/*",
                    f"arn:aws:s3:::{bucket_name}/evaluation/*",
                    f"arn:aws:s3:::{bucket_name}/pipeline/runtime/*",
                ],
            },
            {
                "Sid": "AllowCloudWatchLogs",
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:DescribeLogStreams",
                    "logs:PutLogEvents",
                ],
                "Resource": [
                    f"arn:aws:logs:{region}:{account_id}:log-group:/aws/sagemaker/*",
                    f"arn:aws:logs:{region}:{account_id}:log-group:/aws/sagemaker/*:log-stream:*",
                ],
            },
            {
                "Sid": "AllowEcrImagePull",
                "Effect": "Allow",
                "Action": [
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                ],
                "Resource": "*",
            },
        ],
    }
    return json.dumps(payload)


def ensure_bucket(
    s3_client: Any,
    manifest: dict[str, Any],
    env: dict[str, str],
    mode: str,
) -> None:
    bucket_name = env["DATA_BUCKET"]
    exists = True
    try:
        s3_client.head_bucket(Bucket=bucket_name)
    except ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "")
        if error_code in {"404", "NoSuchBucket", "NotFound"}:
            exists = False
        else:
            raise

    if not exists and mode == "check":
        raise SystemExit(f"Missing bucket: {bucket_name}")

    if not exists:
        create_args: dict[str, Any] = {"Bucket": bucket_name}
        if env["AWS_REGION"] != "us-east-1":
            create_args["CreateBucketConfiguration"] = {
                "LocationConstraint": env["AWS_REGION"]
            }
        s3_client.create_bucket(**create_args)

    if mode == "apply":
        s3_client.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                "BlockPublicAcls": True,
                "IgnorePublicAcls": True,
                "BlockPublicPolicy": True,
                "RestrictPublicBuckets": True,
            },
        )
        s3_client.put_bucket_versioning(
            Bucket=bucket_name,
            VersioningConfiguration={"Status": "Enabled"},
        )
        s3_client.put_bucket_encryption(
            Bucket=bucket_name,
            ServerSideEncryptionConfiguration={
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
                        "BucketKeyEnabled": True,
                    }
                ]
            },
        )
        s3_client.put_bucket_ownership_controls(
            Bucket=bucket_name,
            OwnershipControls={
                "Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]
            },
        )
        s3_client.put_bucket_policy(
            Bucket=bucket_name,
            Policy=bucket_policy(bucket_name),
        )
        s3_client.put_bucket_tagging(
            Bucket=bucket_name,
            Tagging={
                "TagSet": tags_to_aws(
                    resource_tags(manifest, "scripts-bootstrap", "datasets-and-artifacts")
                )
            },
        )

    versioning = s3_client.get_bucket_versioning(Bucket=bucket_name)
    if versioning.get("Status") != "Enabled":
        raise SystemExit(f"Bucket versioning is not enabled on {bucket_name}")


def ensure_role(
    iam_client: Any,
    role_name: str,
    trust_policy_document: str,
    inline_policy_name: str,
    inline_policy_document: str,
    manifest: dict[str, Any],
    usage: str,
    mode: str,
) -> None:
    exists = True
    try:
        iam_client.get_role(RoleName=role_name)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "NoSuchEntity":
            exists = False
        else:
            raise

    if not exists and mode == "check":
        raise SystemExit(f"Missing IAM role: {role_name}")

    if not exists:
        iam_client.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=trust_policy_document,
            Description=f"Bootstrap-managed SageMaker service role for {usage}.",
            Tags=tags_to_aws(resource_tags(manifest, "scripts-bootstrap", usage)),
        )

    if mode == "apply":
        iam_client.update_assume_role_policy(
            RoleName=role_name,
            PolicyDocument=trust_policy_document,
        )
        iam_client.put_role_policy(
            RoleName=role_name,
            PolicyName=inline_policy_name,
            PolicyDocument=inline_policy_document,
        )
        iam_client.tag_role(
            RoleName=role_name,
            Tags=tags_to_aws(resource_tags(manifest, "scripts-bootstrap", usage)),
        )

    iam_client.get_role(RoleName=role_name)
    iam_client.get_role_policy(RoleName=role_name, PolicyName=inline_policy_name)


def ensure_model_package_group(
    sm_client: Any,
    manifest: dict[str, Any],
    env: dict[str, str],
    mode: str,
) -> None:
    group_name = env["MODEL_PACKAGE_GROUP_NAME"]
    exists = True
    try:
        sm_client.describe_model_package_group(ModelPackageGroupName=group_name)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in {"ResourceNotFound", "ValidationException"}:
            exists = False
        else:
            raise

    if not exists and mode == "check":
        raise SystemExit(f"Missing model package group: {group_name}")

    if not exists:
        sm_client.create_model_package_group(
            ModelPackageGroupName=group_name,
            ModelPackageGroupDescription=(
                f"Model packages for Titanic survival model ({env['ENVIRONMENT']})"
            ),
            Tags=tags_to_aws(resource_tags(manifest, "scripts-bootstrap", "model-registry")),
        )

    sm_client.describe_model_package_group(ModelPackageGroupName=group_name)


def main() -> None:
    args = parse_args()
    mode = require_mode(args)
    manifest = load_manifest(args.manifest)
    env = build_env(manifest)

    boto_session = build_boto_session(env)
    s3_client = boto_session.client("s3")
    iam_client = boto_session.client("iam")
    sm_client = boto_session.client("sagemaker")

    ensure_bucket(s3_client, manifest, env, mode)
    ensure_role(
        iam_client=iam_client,
        role_name=env["SAGEMAKER_PIPELINE_ROLE_NAME"],
        trust_policy_document=assume_role_policy(),
        inline_policy_name=f"{env['SAGEMAKER_PIPELINE_ROLE_NAME']}-policy",
        inline_policy_document=pipeline_inline_policy(manifest, env),
        manifest=manifest,
        usage="pipeline-execution-role",
        mode=mode,
    )
    ensure_role(
        iam_client=iam_client,
        role_name=env["SAGEMAKER_EXECUTION_ROLE_NAME"],
        trust_policy_document=assume_role_policy(),
        inline_policy_name=f"{env['SAGEMAKER_EXECUTION_ROLE_NAME']}-policy",
        inline_policy_document=execution_inline_policy(env),
        manifest=manifest,
        usage="sagemaker-execution-role",
        mode=mode,
    )
    ensure_model_package_group(sm_client, manifest, env, mode)
    print(f"[INFO] Bootstrap {mode} complete.")


if __name__ == "__main__":
    main()
