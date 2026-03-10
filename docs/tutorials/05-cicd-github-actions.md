# 05 CI/CD GitHub Actions

## Objetivo y contexto

Dejar un workflow completo de GitHub Actions que replique el flujo manual del tutorial usando
OIDC, `uv`, el mismo bootstrap local y los mismos archivos creados en fases anteriores.

## Resultado minimo esperado

1. Provider OIDC y role de GitHub Actions listos.
2. Workflow YAML autocontenido creado.
3. Job `build` que publica el pipeline y obtiene `ModelPackageArn`.
4. Job `deploy` que despliega `staging`, ejecuta smoke test y luego `prod`.

## Prerequisitos concretos

1. Fases 00-04 completadas.
2. `GITHUB_REPOSITORY` actualizado en `.env.tutorial` con el repo real.
3. Bundle IAM disponible para esta fase:
   - `DataScienceTutorialBootstrap` para el bootstrap OIDC one-time
   - `DataScienceTutorialOperator` para validar el contrato

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Actualizar el repo GitHub en `.env.tutorial`

```bash
sed -i.bak "s#^export GITHUB_REPOSITORY=.*#export GITHUB_REPOSITORY=<tu-org-o-user>/<tu-repo>#g" \
  "$TUTORIAL_ROOT/.env.tutorial"

set -a
source "$TUTORIAL_ROOT/.env.tutorial"
set +a

echo "GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
```

### 2. Crear el bootstrap OIDC del runner

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/bootstrap_github_actions_role.py" <<'EOF'
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


def role_tags() -> list[dict[str, str]]:
    payload = {
        "project": env("PROJECT_NAME"),
        "env": env("ENVIRONMENT"),
        "owner": env("OWNER"),
        "managed_by": env("MANAGED_BY"),
        "cost_center": env("COST_CENTER"),
        "module": "tutorial-bootstrap",
        "usage": "github-actions-deployer",
    }
    return [{"Key": key, "Value": value} for key, value in payload.items()]


def oidc_provider_arn() -> str:
    return f"arn:aws:iam::{env('ACCOUNT_ID')}:oidc-provider/token.actions.githubusercontent.com"


def trust_policy() -> str:
    repo = env("GITHUB_REPOSITORY")
    return json.dumps(
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowGitHubActionsOidcAssumeRole",
                    "Effect": "Allow",
                    "Principal": {"Federated": oidc_provider_arn()},
                    "Action": "sts:AssumeRoleWithWebIdentity",
                    "Condition": {
                        "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
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


def permissions_policy() -> str:
    bucket = env("DATA_BUCKET")
    region = env("AWS_REGION")
    account_id = env("ACCOUNT_ID")
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
                            "s3:prefix": ["curated/*", "training/*", "evaluation/*", "pipeline/*"]
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
                    "Sid": "AllowSageMakerRead",
                    "Effect": "Allow",
                    "Action": ["sagemaker:Describe*", "sagemaker:List*"],
                    "Resource": "*",
                    "Condition": {"StringEquals": {"aws:RequestedRegion": region}},
                },
                {
                    "Sid": "AllowSageMakerBuildDeploy",
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
                    "Sid": "PassOnlySageMakerRoles",
                    "Effect": "Allow",
                    "Action": "iam:PassRole",
                    "Resource": [
                        env("SAGEMAKER_PIPELINE_ROLE_ARN"),
                        env("SAGEMAKER_EXECUTION_ROLE_ARN"),
                    ],
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
                        f"{env('MODEL_PACKAGE_GROUP_NAME')}/*"
                    ),
                },
            ],
        }
    )


def ensure_oidc_provider(iam_client, mode: str) -> None:
    arn = oidc_provider_arn()
    try:
        iam_client.get_open_id_connect_provider(OpenIDConnectProviderArn=arn)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") != "NoSuchEntity":
            raise
        if mode == "check":
            raise SystemExit("Falta el provider OIDC token.actions.githubusercontent.com") from exc
        iam_client.create_open_id_connect_provider(
            Url="https://token.actions.githubusercontent.com",
            ClientIDList=["sts.amazonaws.com"],
            ThumbprintList=["6938fd4d98bab03faadb97b34396831e3780aea1"],
            Tags=role_tags(),
        )


def ensure_role(iam_client, mode: str) -> None:
    role_name = env("GITHUB_ACTIONS_ROLE_NAME")
    policy_name = f"{role_name}-policy"
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
            AssumeRolePolicyDocument=trust_policy(),
            Description="Tutorial-managed GitHub Actions deployer role.",
            Tags=role_tags(),
        )

    if mode == "apply":
        iam_client.update_assume_role_policy(RoleName=role_name, PolicyDocument=trust_policy())
        iam_client.put_role_policy(
            RoleName=role_name,
            PolicyName=policy_name,
            PolicyDocument=permissions_policy(),
        )
        iam_client.tag_role(RoleName=role_name, Tags=role_tags())

    iam_client.get_role(RoleName=role_name)
    iam_client.get_role_policy(RoleName=role_name, PolicyName=policy_name)


def main() -> None:
    args = parse_args()
    mode = require_mode(args)
    session = boto3.Session(profile_name=env("AWS_PROFILE"), region_name=env("AWS_REGION"))
    iam_client = session.client("iam")
    ensure_oidc_provider(iam_client, mode)
    ensure_role(iam_client, mode)
    print(f"[INFO] github-actions-role {mode} complete")


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/bootstrap_github_actions_role.py"
```

### 3. Validar o converger el OIDC role

```bash
uv run python "$TUTORIAL_ROOT/mlops_assets/bootstrap_github_actions_role.py" --check
# Si falta el provider o el role:
# uv run python "$TUTORIAL_ROOT/mlops_assets/bootstrap_github_actions_role.py" --apply
```

### 4. Crear el workflow completo

El workflow asume que has versionado en tu repositorio estos archivos creados a lo largo del
tutorial:

- `pyproject.toml`
- `mlops_assets/bootstrap.py`
- `mlops_assets/evaluate.py`
- `mlops_assets/preprocess.py`
- `mlops_assets/upsert_pipeline.py`

Tambien asume estas repository variables en GitHub:

- `AWS_REGION`
- `AWS_PROFILE`
- `DATA_BUCKET`
- `MODEL_PACKAGE_GROUP_NAME`
- `SAGEMAKER_EXECUTION_ROLE_ARN`
- `SAGEMAKER_PIPELINE_ROLE_ARN`
- `PIPELINE_NAME`
- `STAGING_ENDPOINT_NAME`
- `PROD_ENDPOINT_NAME`
- `GHA_ROLE_ARN`
- `ACCURACY_THRESHOLD`

```bash
cat > "$TUTORIAL_ROOT/.github/workflows/sagemaker-tutorial.yml" <<'EOF'
name: Titanic SageMaker Tutorial

on:
  workflow_dispatch:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502 # v4.0.2
        with:
          role-to-assume: ${{ vars.GHA_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Build data-science-user profile
        run: |
          aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile data-science-user
          aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile data-science-user
          aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile data-science-user
          aws configure set region "${{ vars.AWS_REGION }}" --profile data-science-user
          aws configure set output json --profile data-science-user

      - name: Install uv
        run: |
          curl -LsSf https://astral.sh/uv/install.sh | sh
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Create tutorial env file
        run: |
          cat > .env.tutorial <<EOF_ENV
          export AWS_PROFILE=data-science-user
          export AWS_REGION=${{ vars.AWS_REGION }}
          export ACCOUNT_ID=$(aws sts get-caller-identity --profile data-science-user --query Account --output text)
          export TUTORIAL_ROOT=$PWD
          export DATA_BUCKET=${{ vars.DATA_BUCKET }}
          export MODEL_PACKAGE_GROUP_NAME=${{ vars.MODEL_PACKAGE_GROUP_NAME }}
          export SAGEMAKER_EXECUTION_ROLE_ARN=${{ vars.SAGEMAKER_EXECUTION_ROLE_ARN }}
          export SAGEMAKER_EXECUTION_ROLE_NAME=$(basename "${{ vars.SAGEMAKER_EXECUTION_ROLE_ARN }}")
          export SAGEMAKER_PIPELINE_ROLE_ARN=${{ vars.SAGEMAKER_PIPELINE_ROLE_ARN }}
          export SAGEMAKER_PIPELINE_ROLE_NAME=$(basename "${{ vars.SAGEMAKER_PIPELINE_ROLE_ARN }}")
          export GITHUB_ACTIONS_ROLE_ARN=${{ vars.GHA_ROLE_ARN }}
          export GITHUB_ACTIONS_ROLE_NAME=$(basename "${{ vars.GHA_ROLE_ARN }}")
          export PIPELINE_NAME=${{ vars.PIPELINE_NAME }}
          export STAGING_ENDPOINT_NAME=${{ vars.STAGING_ENDPOINT_NAME }}
          export PROD_ENDPOINT_NAME=${{ vars.PROD_ENDPOINT_NAME }}
          export ACCURACY_THRESHOLD=${{ vars.ACCURACY_THRESHOLD }}
          export PROJECT_NAME=titanic-sagemaker
          export ENVIRONMENT=dev
          export OWNER=github-actions
          export MANAGED_BY=tutorials
          export COST_CENTER=tutorial
          export GITHUB_REPOSITORY=${{ github.repository }}
          EOF_ENV

      - name: Install dependencies
        run: uv sync

      - name: Validate durable resources
        run: |
          set -a
          source .env.tutorial
          set +a
          uv run python mlops_assets/bootstrap.py --check

      - name: Publish pipeline assets
        run: |
          set -a
          source .env.tutorial
          set +a
          mkdir -p artifacts
          CODE_VERSION=$(date +%Y%m%d%H%M%S)
          echo "CODE_VERSION=${CODE_VERSION}" >> "$GITHUB_ENV"
          echo "CODE_PREFIX=pipeline/source/${CODE_VERSION}" >> "$GITHUB_ENV"
          tar -czf artifacts/pipeline_code.tar.gz -C mlops_assets preprocess.py evaluate.py requirements.txt
          aws s3 cp artifacts/pipeline_code.tar.gz "s3://${DATA_BUCKET}/pipeline/source/${CODE_VERSION}/pipeline_code.tar.gz" --profile "${AWS_PROFILE}"
          aws s3 cp mlops_assets/preprocess.py "s3://${DATA_BUCKET}/pipeline/source/${CODE_VERSION}/source/preprocess.py" --profile "${AWS_PROFILE}"
          aws s3 cp mlops_assets/evaluate.py "s3://${DATA_BUCKET}/pipeline/source/${CODE_VERSION}/source/evaluate.py" --profile "${AWS_PROFILE}"

      - name: Upsert pipeline and start execution
        run: |
          set -a
          source .env.tutorial
          set +a
          export CODE_BUNDLE_URI="s3://${DATA_BUCKET}/pipeline/source/${CODE_VERSION}/pipeline_code.tar.gz"
          export PREPROCESS_SCRIPT_S3_URI="s3://${DATA_BUCKET}/pipeline/source/${CODE_VERSION}/source/preprocess.py"
          export EVALUATE_SCRIPT_S3_URI="s3://${DATA_BUCKET}/pipeline/source/${CODE_VERSION}/source/evaluate.py"

          uv run python mlops_assets/upsert_pipeline.py \
            --code-bundle-uri "${CODE_BUNDLE_URI}" \
            --preprocess-script-uri "${PREPROCESS_SCRIPT_S3_URI}" \
            --evaluate-script-uri "${EVALUATE_SCRIPT_S3_URI}"

          uv run python - <<'PY'
          import json
          import os
          from pathlib import Path

          import boto3

          session = boto3.Session(profile_name=os.environ["AWS_PROFILE"], region_name=os.environ["AWS_REGION"])
          sm_client = session.client("sagemaker")
          response = sm_client.start_pipeline_execution(
              PipelineName=os.environ["PIPELINE_NAME"],
              PipelineParameters=[
                  {"Name": "CodeBundleUri", "Value": os.environ["CODE_BUNDLE_URI"]},
                  {"Name": "InputTrainUri", "Value": f"s3://{os.environ['DATA_BUCKET']}/curated/train.csv"},
                  {"Name": "InputValidationUri", "Value": f"s3://{os.environ['DATA_BUCKET']}/curated/validation.csv"},
                  {"Name": "AccuracyThreshold", "Value": os.environ["ACCURACY_THRESHOLD"]},
              ],
          )
          Path("artifacts/pipeline_execution_arn.txt").write_text(
              response["PipelineExecutionArn"] + "\n",
              encoding="utf-8",
          )
          print(json.dumps(response, indent=2))
          PY

      - name: Wait for pipeline and capture package
        run: |
          set -a
          source .env.tutorial
          set +a
          uv run python - <<'PY'
          import os
          import time
          from pathlib import Path

          import boto3

          session = boto3.Session(profile_name=os.environ["AWS_PROFILE"], region_name=os.environ["AWS_REGION"])
          sm_client = session.client("sagemaker")
          execution_arn = Path("artifacts/pipeline_execution_arn.txt").read_text(encoding="utf-8").strip()
          terminal = {"Succeeded", "Failed", "Stopped"}

          while True:
              desc = sm_client.describe_pipeline_execution(PipelineExecutionArn=execution_arn)
              status = desc["PipelineExecutionStatus"]
              print(f"pipeline_status={status}")
              steps = sm_client.list_pipeline_execution_steps(
                  PipelineExecutionArn=execution_arn,
                  SortOrder="Ascending",
              )["PipelineExecutionSteps"]
              for step in steps:
                  print(f"  {step['StepName']} -> {step['StepStatus']}")
              if status in terminal:
                  if status != "Succeeded":
                      raise SystemExit(f"Pipeline finalizo en {status}")
                  break
              time.sleep(30)

          packages = sm_client.list_model_packages(
              ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"],
              SortBy="CreationTime",
              SortOrder="Descending",
              MaxResults=1,
          )["ModelPackageSummaryList"]
          if not packages:
              raise SystemExit("No se encontro ModelPackageArn")
          Path("artifacts/latest_model_package_arn.txt").write_text(
              packages[0]["ModelPackageArn"] + "\n",
              encoding="utf-8",
          )
          PY

      - name: Upload build artifacts
        uses: actions/upload-artifact@b4b15b8c7c6ac21ea08fcf65892d2ee8f75cf882 # v4.4.3
        with:
          name: titanic-build-artifacts
          path: artifacts/

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Download build artifacts
        uses: actions/download-artifact@fa0a91b85d4f404e444e00e005971372dc801d16 # v4.1.8
        with:
          name: titanic-build-artifacts
          path: artifacts

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502 # v4.0.2
        with:
          role-to-assume: ${{ vars.GHA_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Build data-science-user profile
        run: |
          aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile data-science-user
          aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile data-science-user
          aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile data-science-user
          aws configure set region "${{ vars.AWS_REGION }}" --profile data-science-user
          aws configure set output json --profile data-science-user

      - name: Install uv
        run: |
          curl -LsSf https://astral.sh/uv/install.sh | sh
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Create tutorial env file
        run: |
          cat > .env.tutorial <<EOF_ENV
          export AWS_PROFILE=data-science-user
          export AWS_REGION=${{ vars.AWS_REGION }}
          export ACCOUNT_ID=$(aws sts get-caller-identity --profile data-science-user --query Account --output text)
          export TUTORIAL_ROOT=$PWD
          export DATA_BUCKET=${{ vars.DATA_BUCKET }}
          export MODEL_PACKAGE_GROUP_NAME=${{ vars.MODEL_PACKAGE_GROUP_NAME }}
          export SAGEMAKER_EXECUTION_ROLE_ARN=${{ vars.SAGEMAKER_EXECUTION_ROLE_ARN }}
          export SAGEMAKER_PIPELINE_ROLE_ARN=${{ vars.SAGEMAKER_PIPELINE_ROLE_ARN }}
          export PIPELINE_NAME=${{ vars.PIPELINE_NAME }}
          export STAGING_ENDPOINT_NAME=${{ vars.STAGING_ENDPOINT_NAME }}
          export PROD_ENDPOINT_NAME=${{ vars.PROD_ENDPOINT_NAME }}
          export ACCURACY_THRESHOLD=${{ vars.ACCURACY_THRESHOLD }}
          export PROJECT_NAME=titanic-sagemaker
          export ENVIRONMENT=dev
          export OWNER=github-actions
          export MANAGED_BY=tutorials
          export COST_CENTER=tutorial
          export GITHUB_REPOSITORY=${{ github.repository }}
          EOF_ENV

      - name: Install dependencies
        run: uv sync

      - name: Approve package, deploy staging and prod
        run: |
          set -a
          source .env.tutorial
          set +a
          export MODEL_PACKAGE_ARN=$(cat artifacts/latest_model_package_arn.txt)

          uv run python - <<'PY'
          import os

          import boto3
          from sagemaker.core.helper.session_helper import Session
          from sagemaker.core.resources import ModelPackage
          from sagemaker.serve.model_builder import ModelBuilder

          session = boto3.Session(profile_name=os.environ["AWS_PROFILE"], region_name=os.environ["AWS_REGION"])
          sm_client = session.client("sagemaker")
          runtime_client = session.client("sagemaker-runtime")
          sm_session = Session(boto_session=session)

          sm_client.update_model_package(
              ModelPackageArn=os.environ["MODEL_PACKAGE_ARN"],
              ModelApprovalStatus="Approved",
          )

          model_package = ModelPackage.get(model_package_name=os.environ["MODEL_PACKAGE_ARN"])
          builder = ModelBuilder(
              model=model_package,
              role_arn=os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"],
              sagemaker_session=sm_session,
          )
          builder.build(model_name=f"{os.environ['STAGING_ENDPOINT_NAME']}-model")
          builder.deploy(
              endpoint_name=os.environ["STAGING_ENDPOINT_NAME"],
              instance_type="ml.m5.large",
              initial_instance_count=1,
          )

          smoke = runtime_client.invoke_endpoint(
              EndpointName=os.environ["STAGING_ENDPOINT_NAME"],
              ContentType="text/csv",
              Body="3,0,22,1,0,7.25,2\n1,1,38,1,0,71.2833,0\n".encode("utf-8"),
          )["Body"].read().decode("utf-8")
          print(smoke)
          if not smoke.strip():
              raise SystemExit("Smoke test vacio")

          prod_builder = ModelBuilder(
              model=model_package,
              role_arn=os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"],
              sagemaker_session=sm_session,
          )
          prod_builder.build(model_name=f"{os.environ['PROD_ENDPOINT_NAME']}-model")
          prod_builder.deploy(
              endpoint_name=os.environ["PROD_ENDPOINT_NAME"],
              instance_type="ml.m5.large",
              initial_instance_count=1,
          )
          PY
EOF
```

### 5. Versionar el contrato del workflow

```bash
git add \
  "$TUTORIAL_ROOT/pyproject.toml" \
  "$TUTORIAL_ROOT/mlops_assets" \
  "$TUTORIAL_ROOT/.github/workflows/sagemaker-tutorial.yml"
```

`.env.tutorial` se mantiene local; no hace falta versionarlo para que el workflow funcione.

## IAM usado

- `DataScienceTutorialBootstrap` para crear el provider OIDC y el role del runner.
- `DataScienceTutorialOperator` para reproducir localmente el contrato del workflow.

## Evidencia requerida

1. Salida de `bootstrap_github_actions_role.py`
2. Workflow `sagemaker-tutorial.yml`
3. Variables configuradas en GitHub

## Criterio de cierre

- Role OIDC listo.
- Workflow autocontenido creado.
- El workflow replica build + deploy con `uv`.

## Riesgos/pendientes

- Si no actualizas `GITHUB_REPOSITORY`, el trust policy no coincidira con tu repo real.
- El workflow asume que `pyproject.toml` y `mlops_assets/` se versionan en el repo.

## Proximo paso

Continuar con [`06-observability-operations.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/06-observability-operations.md).
