#!/usr/bin/env python3
"""Ensure the GitHub Actions deployer role exists without Terraform."""

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
    parser.add_argument("--apply", action="store_true", help="Create/update the role.")
    parser.add_argument("--check", action="store_true", help="Validate only.")
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


def role_tags(manifest: dict[str, Any]) -> dict[str, str]:
    return {
        "project": str(manifest["project_name"]),
        "env": str(manifest["environment"]),
        "owner": str(manifest["owner"]),
        "managed_by": str(manifest["managed_by"]),
        "cost_center": str(manifest["cost_center"]),
        "module": "scripts-bootstrap",
        "usage": "github-actions-deployer",
    }


def trust_policy(env: dict[str, str]) -> str:
    repo = env["GITHUB_REPOSITORY"]
    account_id = env["ACCOUNT_ID"]
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowGitHubActionsOidcAssumeRole",
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": (
                            f"arn:aws:iam::{account_id}:oidc-provider/"
                            "token.actions.githubusercontent.com"
                        )
                    },
                    "Action": "sts:AssumeRoleWithWebIdentity",
                    "Condition": {
                        "StringEquals": {
                            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                        },
                        "StringLike": {
                            "token.actions.githubusercontent.com:sub": [
                                f"repo:{repo}:pull_request",
                                f"repo:{repo}:ref:refs/heads/main",
                                f"repo:{repo}:environment:dev",
                                f"repo:{repo}:environment:prod",
                            ]
                        },
                    },
                }
            ],
        }
    )


def permissions_policy(env: dict[str, str]) -> str:
    bucket = env["DATA_BUCKET"]
    account_id = env["ACCOUNT_ID"]
    region = env["AWS_REGION"]
    pipeline_role_arn = env["SAGEMAKER_PIPELINE_ROLE_ARN"]
    execution_role_arn = env["SAGEMAKER_EXECUTION_ROLE_ARN"]

    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowIdentityCheck",
                    "Effect": "Allow",
                    "Action": ["sts:GetCallerIdentity"],
                    "Resource": "*",
                },
                {
                    "Sid": "AllowTutorialBucketReadWrite",
                    "Effect": "Allow",
                    "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
                    "Resource": f"arn:aws:s3:::{bucket}",
                    "Condition": {
                        "StringLike": {
                            "s3:prefix": [
                                "curated/*",
                                "training/*",
                                "evaluation/*",
                                "pipeline/*",
                            ]
                        }
                    },
                },
                {
                    "Sid": "AllowTutorialBucketObjectReadWrite",
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
                    "Resource": [
                        f"arn:aws:s3:::{bucket}/curated/*",
                        f"arn:aws:s3:::{bucket}/training/*",
                        f"arn:aws:s3:::{bucket}/evaluation/*",
                        f"arn:aws:s3:::{bucket}/pipeline/*",
                    ],
                },
                {
                    "Sid": "AllowSageMakerReadForWorkflowCoordinationInEuWest1",
                    "Effect": "Allow",
                    "Action": ["sagemaker:Describe*", "sagemaker:List*"],
                    "Resource": "*",
                    "Condition": {"StringEquals": {"aws:RequestedRegion": region}},
                },
                {
                    "Sid": "AllowSageMakerBuildDeployActionsInEuWest1",
                    "Effect": "Allow",
                    "Action": [
                        "sagemaker:AddTags",
                        "sagemaker:CreateEndpoint",
                        "sagemaker:CreateEndpointConfig",
                        "sagemaker:CreateModel",
                        "sagemaker:CreatePipeline",
                        "sagemaker:InvokeEndpoint",
                        "sagemaker:StartPipelineExecution",
                        "sagemaker:UpdateEndpoint",
                        "sagemaker:UpdateModelPackage",
                        "sagemaker:UpdatePipeline",
                    ],
                    "Resource": "*",
                    "Condition": {"StringEquals": {"aws:RequestedRegion": region}},
                },
                {
                    "Sid": "PassOnlyProjectSageMakerRoles",
                    "Effect": "Allow",
                    "Action": "iam:PassRole",
                    "Resource": [pipeline_role_arn, execution_role_arn],
                    "Condition": {
                        "StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}
                    },
                },
                {
                    "Sid": "AllowModelPackageApproval",
                    "Effect": "Allow",
                    "Action": ["sagemaker:UpdateModelPackage"],
                    "Resource": (
                        f"arn:aws:sagemaker:{region}:{account_id}:model-package/"
                        f"{env['MODEL_PACKAGE_GROUP_NAME']}/*"
                    ),
                },
            ],
        }
    )


def ensure_oidc_provider(iam_client: Any, env: dict[str, str]) -> None:
    arn = (
        f"arn:aws:iam::{env['ACCOUNT_ID']}:oidc-provider/token.actions.githubusercontent.com"
    )
    try:
        iam_client.get_open_id_connect_provider(OpenIDConnectProviderArn=arn)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "NoSuchEntity":
            raise SystemExit(
                "Missing GitHub OIDC provider. Create it once in IAM before bootstrapping the role."
            ) from exc
        raise


def ensure_role(
    iam_client: Any,
    manifest: dict[str, Any],
    env: dict[str, str],
    mode: str,
) -> None:
    role_name = env["GITHUB_ACTIONS_ROLE_NAME"]
    inline_policy_name = f"{role_name}-policy"
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
            AssumeRolePolicyDocument=trust_policy(env),
            Description="Bootstrap-managed GitHub Actions deployer role.",
            Tags=tags_to_aws(role_tags(manifest)),
        )

    if mode == "apply":
        iam_client.update_assume_role_policy(
            RoleName=role_name,
            PolicyDocument=trust_policy(env),
        )
        iam_client.put_role_policy(
            RoleName=role_name,
            PolicyName=inline_policy_name,
            PolicyDocument=permissions_policy(env),
        )
        iam_client.tag_role(RoleName=role_name, Tags=tags_to_aws(role_tags(manifest)))

    iam_client.get_role(RoleName=role_name)
    iam_client.get_role_policy(RoleName=role_name, PolicyName=inline_policy_name)


def main() -> None:
    args = parse_args()
    mode = require_mode(args)
    manifest = load_manifest(args.manifest)
    env = build_env(manifest)

    session = build_boto_session(env)
    iam_client = session.client("iam")
    ensure_oidc_provider(iam_client, env)
    ensure_role(iam_client, manifest, env, mode)
    print(f"[INFO] GitHub Actions role {mode} complete.")


if __name__ == "__main__":
    main()
