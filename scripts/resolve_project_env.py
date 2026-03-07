#!/usr/bin/env python3
"""Resolve the no-Terraform project contract from a versioned manifest."""

from __future__ import annotations

import argparse
import json
import shlex
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST_PATH = REPO_ROOT / "config" / "project-manifest.json"


def default_manifest_path() -> Path:
    return DEFAULT_MANIFEST_PATH


def load_manifest(path: str | Path | None = None) -> dict[str, Any]:
    manifest_path = Path(path) if path else default_manifest_path()
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))

    required_keys = [
        "aws_profile",
        "aws_region",
        "account_id",
        "environment",
        "project_name",
        "owner",
        "cost_center",
        "managed_by",
        "data_bucket_name",
        "code_s3_prefix",
        "training_output_prefix",
        "evaluation_output_prefix",
        "pipeline_name",
        "model_package_group_name",
        "staging_endpoint_name",
        "prod_endpoint_name",
        "processing_image_uri",
        "training_image_uri",
        "evaluation_image_uri",
        "quality_threshold_accuracy",
        "model_approval_status",
        "sagemaker_execution_role_name",
        "sagemaker_pipeline_role_name",
        "github_actions_role_name",
    ]
    missing = [key for key in required_keys if key not in payload]
    if missing:
        raise ValueError(f"Manifest missing required keys: {', '.join(missing)}")
    return payload


def build_env(manifest: dict[str, Any]) -> dict[str, str]:
    account_id = str(manifest["account_id"])
    region = str(manifest["aws_region"])
    data_bucket = str(manifest["data_bucket_name"])
    pipeline_name = str(manifest["pipeline_name"])
    execution_role_name = str(manifest["sagemaker_execution_role_name"])
    pipeline_role_name = str(manifest["sagemaker_pipeline_role_name"])
    gha_role_name = str(manifest["github_actions_role_name"])

    env = {
        "AWS_PROFILE": str(manifest["aws_profile"]),
        "AWS_REGION": region,
        "ACCOUNT_ID": account_id,
        "ENVIRONMENT": str(manifest["environment"]),
        "PROJECT_NAME": str(manifest["project_name"]),
        "OWNER": str(manifest["owner"]),
        "COST_CENTER": str(manifest["cost_center"]),
        "MANAGED_BY": str(manifest["managed_by"]),
        "GITHUB_REPOSITORY": str(manifest.get("github_repository", "")),
        "DATA_BUCKET": data_bucket,
        "DATA_BUCKET_NAME": data_bucket,
        "CODE_S3_PREFIX": str(manifest["code_s3_prefix"]),
        "TRAINING_OUTPUT_PREFIX": str(manifest["training_output_prefix"]),
        "EVALUATION_OUTPUT_PREFIX": str(manifest["evaluation_output_prefix"]),
        "PIPELINE_RUNTIME_S3_PREFIX": f"pipeline/runtime/{pipeline_name}",
        "PIPELINE_NAME": pipeline_name,
        "MODEL_PACKAGE_GROUP_NAME": str(manifest["model_package_group_name"]),
        "STAGING_ENDPOINT_NAME": str(manifest["staging_endpoint_name"]),
        "PROD_ENDPOINT_NAME": str(manifest["prod_endpoint_name"]),
        "PROCESSING_IMAGE_URI": str(manifest["processing_image_uri"]),
        "TRAINING_IMAGE_URI": str(manifest["training_image_uri"]),
        "EVALUATION_IMAGE_URI": str(manifest["evaluation_image_uri"]),
        "QUALITY_THRESHOLD_ACCURACY": str(manifest["quality_threshold_accuracy"]),
        "MODEL_APPROVAL_STATUS": str(manifest["model_approval_status"]),
        "SAGEMAKER_EXECUTION_ROLE_NAME": execution_role_name,
        "SAGEMAKER_EXECUTION_ROLE_ARN": f"arn:aws:iam::{account_id}:role/{execution_role_name}",
        "SAGEMAKER_PIPELINE_ROLE_NAME": pipeline_role_name,
        "SAGEMAKER_PIPELINE_ROLE_ARN": f"arn:aws:iam::{account_id}:role/{pipeline_role_name}",
        "GITHUB_ACTIONS_ROLE_NAME": gha_role_name,
        "GITHUB_ACTIONS_ROLE_ARN": f"arn:aws:iam::{account_id}:role/{gha_role_name}",
    }
    return env


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default=str(default_manifest_path()))
    parser.add_argument("--emit-exports", action="store_true")
    parser.add_argument("--format", choices=["shell", "json"], default="shell")
    parser.add_argument("--key", help="Emit only a single resolved key")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    env = build_env(load_manifest(args.manifest))

    if args.key:
        try:
            print(env[args.key])
        except KeyError as exc:
            raise SystemExit(f"Unknown key: {args.key}") from exc
        return

    if args.format == "json":
        print(json.dumps(env, indent=2, sort_keys=True))
        return

    for key in sorted(env):
        if args.emit_exports:
            print(f"export {key}={shlex.quote(env[key])}")
        else:
            print(f"{key}={env[key]}")


if __name__ == "__main__":
    main()
