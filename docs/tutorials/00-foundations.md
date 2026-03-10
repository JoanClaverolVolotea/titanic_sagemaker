# 00 Foundations

## Objetivo y contexto

Dejar listo un workspace autocontenido para el roadmap, con `uv` como unico package manager,
variables compartidas en `.env.tutorial` y recursos AWS bootstrap creados sin depender de
archivos externos.

## Resultado minimo esperado

1. Workspace local creado en `~/titanic-sagemaker-tutorial`.
2. `pyproject.toml` creado y dependencias instaladas con `uv sync`.
3. `.env.tutorial` con nombres y ARNs canonicos del tutorial.
4. Bucket, roles de SageMaker y Model Package Group convergidos.
5. Imports base de SageMaker V3 verificados con `uv run python`.

## Prerequisitos concretos

1. `uv` instalado.
2. AWS CLI instalado.
3. Perfil `data-science-user` operativo.
4. Bundle IAM disponible para esta fase: `DataScienceTutorialBootstrap`.

## Bootstrap auto-contenido

```bash
export TUTORIAL_ROOT="$HOME/titanic-sagemaker-tutorial"
mkdir -p \
  "$TUTORIAL_ROOT/data/raw" \
  "$TUTORIAL_ROOT/data/splits" \
  "$TUTORIAL_ROOT/data/sagemaker" \
  "$TUTORIAL_ROOT/artifacts" \
  "$TUTORIAL_ROOT/mlops_assets" \
  "$TUTORIAL_ROOT/.github/workflows"
cd "$TUTORIAL_ROOT"
```

## Paso a paso

### 1. Crear `pyproject.toml`

```bash
cat > "$TUTORIAL_ROOT/pyproject.toml" <<'EOF'
[project]
name = "titanic-sagemaker-tutorial"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
  "boto3>=1.37,<2",
  "pandas>=2.2,<3",
  "sagemaker>=3,<4",
  "scikit-learn>=1.5,<2",
  "xgboost==2.1.4",
]
EOF

uv sync
```

### 2. Resolver el contrato local del tutorial

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)

cat > "$TUTORIAL_ROOT/.env.tutorial" <<EOF
export AWS_PROFILE=$AWS_PROFILE
export AWS_REGION=$AWS_REGION
export ACCOUNT_ID=$ACCOUNT_ID
export TUTORIAL_ROOT=$TUTORIAL_ROOT
export DATA_BUCKET=titanic-data-bucket-${ACCOUNT_ID}-data-science-user
export MODEL_PACKAGE_GROUP_NAME=titanic-survival-xgboost
export SAGEMAKER_EXECUTION_ROLE_NAME=titanic-sagemaker-sagemaker-execution-dev
export SAGEMAKER_EXECUTION_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/titanic-sagemaker-sagemaker-execution-dev
export SAGEMAKER_PIPELINE_ROLE_NAME=titanic-sagemaker-pipeline-dev
export SAGEMAKER_PIPELINE_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/titanic-sagemaker-pipeline-dev
export GITHUB_ACTIONS_ROLE_NAME=titanic-sagemaker-gha-deployer-dev
export GITHUB_ACTIONS_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/titanic-sagemaker-gha-deployer-dev
export PIPELINE_NAME=titanic-modelbuild-dev
export STAGING_ENDPOINT_NAME=titanic-survival-staging
export PROD_ENDPOINT_NAME=titanic-survival-prod
export ACCURACY_THRESHOLD=0.78
export PROJECT_NAME=titanic-sagemaker
export ENVIRONMENT=dev
export OWNER=data-science-user
export MANAGED_BY=tutorials
export COST_CENTER=tutorial
export GITHUB_REPOSITORY=replace-me/replace-me
EOF

set -a
source "$TUTORIAL_ROOT/.env.tutorial"
set +a
```

### 3. Crear el bootstrap local de AWS

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/bootstrap.py" <<'EOF'
#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import os

import boto3
from botocore.exceptions import ClientError


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def require_mode(args: argparse.Namespace) -> str:
    if args.apply and args.check:
        raise SystemExit("Usa solo uno: --check o --apply")
    if args.apply:
        return "apply"
    return "check"


def env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"Falta la variable {name}")
    return value


def tags(module: str, usage: str) -> list[dict[str, str]]:
    payload = {
        "project": env("PROJECT_NAME"),
        "env": env("ENVIRONMENT"),
        "owner": env("OWNER"),
        "managed_by": env("MANAGED_BY"),
        "cost_center": env("COST_CENTER"),
        "module": module,
        "usage": usage,
    }
    return [{"Key": key, "Value": value} for key, value in payload.items()]


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


def execution_inline_policy() -> str:
    bucket_name = env("DATA_BUCKET")
    region = env("AWS_REGION")
    account_id = env("ACCOUNT_ID")
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "ReadCuratedAndCode",
                    "Effect": "Allow",
                    "Action": ["s3:GetObject"],
                    "Resource": [
                        f"arn:aws:s3:::{bucket_name}/curated/*",
                        f"arn:aws:s3:::{bucket_name}/pipeline/*",
                    ],
                },
                {
                    "Sid": "ListTutorialBucket",
                    "Effect": "Allow",
                    "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
                    "Resource": [f"arn:aws:s3:::{bucket_name}"],
                },
                {
                    "Sid": "WriteRuntimeArtifacts",
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
                    "Resource": [
                        f"arn:aws:s3:::{bucket_name}/training/*",
                        f"arn:aws:s3:::{bucket_name}/evaluation/*",
                        f"arn:aws:s3:::{bucket_name}/pipeline/*",
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
    )


def pipeline_inline_policy() -> str:
    bucket_name = env("DATA_BUCKET")
    region = env("AWS_REGION")
    account_id = env("ACCOUNT_ID")
    pipeline_role_arn = env("SAGEMAKER_PIPELINE_ROLE_ARN")
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "ReadCuratedAndCode",
                    "Effect": "Allow",
                    "Action": ["s3:GetObject"],
                    "Resource": [
                        f"arn:aws:s3:::{bucket_name}/curated/*",
                        f"arn:aws:s3:::{bucket_name}/pipeline/*",
                    ],
                },
                {
                    "Sid": "ListTutorialBucket",
                    "Effect": "Allow",
                    "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
                    "Resource": [f"arn:aws:s3:::{bucket_name}"],
                },
                {
                    "Sid": "WriteRuntimeArtifacts",
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
                    "Resource": [f"arn:aws:s3:::{bucket_name}/pipeline/*"],
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
                    "Sid": "AllowPipelineRuntime",
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
                    "Sid": "PassPipelineRoleToSageMaker",
                    "Effect": "Allow",
                    "Action": ["iam:PassRole"],
                    "Resource": [pipeline_role_arn],
                    "Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}},
                },
            ],
        }
    )


def ensure_bucket(s3_client, mode: str) -> None:
    bucket_name = env("DATA_BUCKET")
    region = env("AWS_REGION")
    exists = True
    try:
        s3_client.head_bucket(Bucket=bucket_name)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in {"404", "NoSuchBucket", "NotFound"}:
            exists = False
        else:
            raise

    if not exists and mode == "check":
        raise SystemExit(f"Falta bucket: {bucket_name}")

    if not exists:
        params = {"Bucket": bucket_name}
        if region != "us-east-1":
            params["CreateBucketConfiguration"] = {"LocationConstraint": region}
        s3_client.create_bucket(**params)

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
            OwnershipControls={"Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]},
        )
        s3_client.put_bucket_policy(Bucket=bucket_name, Policy=bucket_policy(bucket_name))
        s3_client.put_bucket_tagging(
            Bucket=bucket_name,
            Tagging={"TagSet": tags("tutorial-bootstrap", "datasets-and-artifacts")},
        )


def ensure_role(iam_client, role_name: str, policy_name: str, policy_document: str, usage: str, mode: str) -> None:
    exists = True
    try:
        iam_client.get_role(RoleName=role_name)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "NoSuchEntity":
            exists = False
        else:
            raise

    if not exists and mode == "check":
        raise SystemExit(f"Falta role: {role_name}")

    if not exists:
        iam_client.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=assume_role_policy(),
            Description=f"Tutorial-managed role {usage}",
            Tags=tags("tutorial-bootstrap", usage),
        )

    if mode == "apply":
        iam_client.update_assume_role_policy(
            RoleName=role_name,
            PolicyDocument=assume_role_policy(),
        )
        iam_client.put_role_policy(
            RoleName=role_name,
            PolicyName=policy_name,
            PolicyDocument=policy_document,
        )
        iam_client.tag_role(RoleName=role_name, Tags=tags("tutorial-bootstrap", usage))

    iam_client.get_role(RoleName=role_name)
    iam_client.get_role_policy(RoleName=role_name, PolicyName=policy_name)


def ensure_model_package_group(sm_client, mode: str) -> None:
    group_name = env("MODEL_PACKAGE_GROUP_NAME")
    try:
        sm_client.describe_model_package_group(ModelPackageGroupName=group_name)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") != "ValidationException":
            raise
        if mode == "check":
            raise SystemExit(f"Falta Model Package Group: {group_name}") from exc
        sm_client.create_model_package_group(
            ModelPackageGroupName=group_name,
            ModelPackageGroupDescription="Model registry group for the Titanic tutorial.",
            Tags=tags("tutorial-bootstrap", "model-registry"),
        )


def main() -> None:
    args = parse_args()
    mode = require_mode(args)
    session = boto3.Session(profile_name=env("AWS_PROFILE"), region_name=env("AWS_REGION"))
    s3_client = session.client("s3")
    iam_client = session.client("iam")
    sm_client = session.client("sagemaker")

    ensure_bucket(s3_client, mode)
    ensure_role(
        iam_client,
        env("SAGEMAKER_EXECUTION_ROLE_NAME"),
        f"{env('SAGEMAKER_EXECUTION_ROLE_NAME')}-policy",
        execution_inline_policy(),
        "sagemaker-execution-role",
        mode,
    )
    ensure_role(
        iam_client,
        env("SAGEMAKER_PIPELINE_ROLE_NAME"),
        f"{env('SAGEMAKER_PIPELINE_ROLE_NAME')}-policy",
        pipeline_inline_policy(),
        "pipeline-execution-role",
        mode,
    )
    ensure_model_package_group(sm_client, mode)
    print(f"[INFO] bootstrap {mode} complete")


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/bootstrap.py"
```

### 4. Validar y converger recursos duraderos

```bash
set -a
source "$TUTORIAL_ROOT/.env.tutorial"
set +a

uv run python "$TUTORIAL_ROOT/mlops_assets/bootstrap.py" --check
# Si falta algun recurso:
# uv run python "$TUTORIAL_ROOT/mlops_assets/bootstrap.py" --apply
```

### 5. Verificar imports V3 y sesion base

```bash
uv run python - <<'PY'
from importlib.metadata import version

from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.mlops.workflow.pipeline import Pipeline
from sagemaker.serve.model_builder import ModelBuilder
from sagemaker.train import ModelTrainer

sm_version = version("sagemaker")
assert sm_version.split(".")[0] == "3", sm_version
session = Session()
print(f"sagemaker={sm_version}")
print(f"region={session.boto_region_name}")
try:
    print(f"default_bucket={session.default_bucket()}")
except Exception as exc:
    print(f"default_bucket_unavailable={exc}")
try:
    print(f"execution_role={get_execution_role()}")
except Exception:
    print("execution_role=use .env.tutorial outside managed runtimes")
print("imports_ok=Session ModelTrainer ModelBuilder Pipeline")
PY
```

## IAM usado

- `DataScienceTutorialBootstrap` para bucket, roles y Model Package Group.
- `data-science-user` como identidad humana operativa.

## Evidencia requerida

1. Salida de `uv sync`.
2. Salida de `bootstrap.py --check` o `--apply`.
3. Salida del bloque de imports y sesion.

## Criterio de cierre

- Workspace local creado.
- `.env.tutorial` listo.
- Recursos duraderos presentes.
- SageMaker SDK V3 instalado y verificado con `uv`.

## Riesgos/pendientes

- Si `GITHUB_REPOSITORY` sigue en `replace-me/replace-me`, la fase 05 no podra crear el trust
  OIDC correcto.
- Si no ejecutas `bootstrap.py --apply` cuando faltan recursos, las fases 01-05 fallaran.

## Proximo paso

Continuar con [`01-data-ingestion.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/01-data-ingestion.md).
