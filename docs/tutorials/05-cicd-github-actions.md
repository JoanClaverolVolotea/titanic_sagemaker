# 05 CI/CD GitHub Actions

## Objetivo y contexto

Dejar un workflow completo de GitHub Actions que replique el flujo manual del tutorial usando
OIDC, `uv`, el mismo contrato local y los mismos archivos creados en fases anteriores.

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
export REPO_ROOT="/ruta/a/este/repo/titanic_sagemaker"
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

`REPO_ROOT` debe apuntar al repo versionado que contiene `config/project-manifest.json` y
`scripts/ensure_github_actions_role.py`.

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

### 2. Validar o converger el bootstrap OIDC del runner

```bash
cd "$REPO_ROOT"
python3 -m json.tool config/project-manifest.json >/dev/null

uv run --with boto3 --with botocore python scripts/ensure_github_actions_role.py --check
# Si falta el provider o el role:
# uv run --with boto3 --with botocore python scripts/ensure_github_actions_role.py --apply

cd "$TUTORIAL_ROOT"
```

Este script es la fuente de verdad actual para el role OIDC del runner. No crees un helper
inline nuevo en el workspace del tutorial para esta parte.

### 3. Crear el workflow completo

El workflow asume que has versionado en tu repositorio estos archivos creados a lo largo del
tutorial:

- `pyproject.toml`
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

```yaml
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
          export OWNER=data-science-user
          export MANAGED_BY=scripts
          export COST_CENTER=data-science
          export GITHUB_REPOSITORY=${{ github.repository }}
          EOF_ENV

      - name: Install dependencies
        run: uv sync

      - name: Validate durable resources
        run: |
          set -a
          source .env.tutorial
          set +a
          aws sts get-caller-identity --profile "${AWS_PROFILE}"
          aws s3api get-bucket-location --bucket "${DATA_BUCKET}" --profile "${AWS_PROFILE}"
          aws sagemaker describe-model-package-group \
            --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" \
            --profile "${AWS_PROFILE}" \
            --region "${AWS_REGION}"
          test -n "${SAGEMAKER_EXECUTION_ROLE_ARN}"
          test -n "${SAGEMAKER_PIPELINE_ROLE_ARN}"

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
          export OWNER=data-science-user
          export MANAGED_BY=scripts
          export COST_CENTER=data-science
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

          boto_session = boto3.Session(profile_name=os.environ["AWS_PROFILE"], region_name=os.environ["AWS_REGION"])
          sm_client = boto_session.client("sagemaker")
          runtime_client = boto_session.client("sagemaker-runtime")
          sm_session = Session(boto_session=boto_session, default_bucket=os.environ["DATA_BUCKET"])

          sm_client.update_model_package(
              ModelPackageArn=os.environ["MODEL_PACKAGE_ARN"],
              ModelApprovalStatus="Approved",
          )

          model_package = ModelPackage.get(model_package_name=os.environ["MODEL_PACKAGE_ARN"])
          container = model_package.inference_specification.containers[0]

          staging_builder = ModelBuilder(
              s3_model_data_url=container.model_data_url,
              image_uri=container.image,
              role_arn=os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"],
              sagemaker_session=sm_session,
          )
          staging_builder.build(model_name=f"{os.environ['STAGING_ENDPOINT_NAME']}-model")
          staging_builder.deploy(
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
              s3_model_data_url=container.model_data_url,
              image_uri=container.image,
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
```

Guarda como `$TUTORIAL_ROOT/.github/workflows/sagemaker-tutorial.yml` y ejecuta:

```bash
mkdir -p "$TUTORIAL_ROOT/.github/workflows"
cat > "$TUTORIAL_ROOT/.github/workflows/sagemaker-tutorial.yml" <<'YAMLEOF'
# (pega aqui el contenido YAML de arriba)
YAMLEOF
```

### 4. Versionar el contrato del workflow

```bash
git add \
  "$TUTORIAL_ROOT/pyproject.toml" \
  "$TUTORIAL_ROOT/mlops_assets" \
  "$TUTORIAL_ROOT/.github/workflows/sagemaker-tutorial.yml"
```

`.env.tutorial` se mantiene local; no hace falta versionarlo para que el workflow funcione.

## IAM usado

- `DataScienceTutorialBootstrap` para validar o converger una sola vez el provider OIDC y el
  role del runner con `scripts/ensure_github_actions_role.py`.
- `DataScienceTutorialOperator` para reproducir localmente el contrato del workflow.

## Evidencia requerida

1. Salida de `scripts/ensure_github_actions_role.py --check` o `--apply`
2. Workflow `sagemaker-tutorial.yml`
3. Variables configuradas en GitHub

## Criterio de cierre

- Role OIDC listo.
- Workflow autocontenido creado.
- El workflow replica build + deploy con `uv`.

## Riesgos/pendientes

- Si no actualizas `GITHUB_REPOSITORY`, el trust policy no coincidira con tu repo real.
- El workflow asume que `pyproject.toml` y `mlops_assets/` se versionan en el repo.
- Si `REPO_ROOT` no apunta al repo correcto, no podras usar la fuente de verdad oficial para el
  role OIDC.

## Proximo paso

Continuar con [`06-observability-operations.md`](./06-observability-operations.md).
