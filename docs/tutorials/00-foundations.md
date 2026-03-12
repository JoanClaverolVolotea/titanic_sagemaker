# 00 Foundations

## Objetivo y contexto

Dejar listo un workspace local autocontenido para el roadmap, con `uv` como unico package
manager, variables compartidas en `.env.tutorial` y validaciones AWS CLI sobre recursos
duraderos ya preparados fuera del tutorial.

Esta fase no crea el usuario `data-science-user` ni genera bootstrap AWS inline. El usuario y
las managed policies del tutorial se gestionan fuera de esta fase por el equipo de DevOps.

## Resultado minimo esperado

1. Workspace local creado en `~/titanic-sagemaker-tutorial`.
2. `pyproject.toml` creado y dependencias instaladas con `uv sync`.
3. `.env.tutorial` con nombres y ARNs canonicos del tutorial.
4. Handoff IAM claro hacia [docs/aws/policies/README.md](../aws/policies/README.md) para
   `DataScienceTutorialBootstrap`, `DataScienceTutorialOperator` y
   `DataScienceTutorialCleanup`.
5. Bucket, roles de SageMaker y Model Package Group validados por AWS CLI.
6. Imports base de SageMaker V3 verificados con `uv run python`.

## Prerequisitos concretos

1. `uv` instalado.
2. AWS CLI instalado.
3. El usuario IAM `data-science-user` ya existe y el perfil AWS CLI `data-science-user`
   funciona localmente.
4. DevOps ya aplico o valido las managed policies humanas siguiendo
   [docs/aws/policies/README.md](../aws/policies/README.md).
5. Los recursos duraderos del tutorial ya existen en AWS:
   - bucket `DATA_BUCKET`
   - role `SAGEMAKER_EXECUTION_ROLE_NAME`
   - role `SAGEMAKER_PIPELINE_ROLE_NAME`
   - Model Package Group `MODEL_PACKAGE_GROUP_NAME`

## Bootstrap local

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
requires-python = ">=3.11,<3.12"
dependencies = [
  "boto3>=1.37,<2",
  "pandas>=2.2,<3",
  "sagemaker>=3,<4",
  "scikit-learn>=1.5,<2",
  "xgboost==2.1.4",
]
EOF

cd "$TUTORIAL_ROOT"
uv python pin 3.11
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
export MANAGED_BY=scripts
export COST_CENTER=data-science
export GITHUB_REPOSITORY=replace-me/replace-me
EOF

set -a
source "$TUTORIAL_ROOT/.env.tutorial"
set +a
```

### 3. Confirmar el handoff IAM con DevOps

Usa [docs/aws/policies/README.md](../aws/policies/README.md) como fuente canonica para el
bootstrap IAM del tutorial.

Politicas humanas del tutorial:

- `DataScienceTutorialBootstrap`
- `DataScienceTutorialOperator`
- `DataScienceTutorialCleanup`

Reglas para esta fase:

1. `00-foundations` no crea `data-science-user`.
2. `00-foundations` no crea managed policies IAM.
3. El equipo DevOps aplica o actualiza esas policies por AWS CLI o AWS Console siguiendo el
   README de policies.
4. Si alguna validacion AWS CLI falla en el siguiente paso, detente y vuelve a esa guia antes
   de continuar con la fase 01.

### 4. Validar recursos duraderos por AWS CLI

```bash
set -euo pipefail

set -a
source "$TUTORIAL_ROOT/.env.tutorial"
set +a

aws sts get-caller-identity --profile "$AWS_PROFILE"

aws s3api get-bucket-location \
  --bucket "$DATA_BUCKET" \
  --profile "$AWS_PROFILE"

aws s3api get-bucket-versioning \
  --bucket "$DATA_BUCKET" \
  --profile "$AWS_PROFILE"

aws iam get-role \
  --role-name "$SAGEMAKER_EXECUTION_ROLE_NAME" \
  --profile "$AWS_PROFILE"

aws iam get-role-policy \
  --role-name "$SAGEMAKER_EXECUTION_ROLE_NAME" \
  --policy-name "${SAGEMAKER_EXECUTION_ROLE_NAME}-policy" \
  --profile "$AWS_PROFILE"

aws iam get-role \
  --role-name "$SAGEMAKER_PIPELINE_ROLE_NAME" \
  --profile "$AWS_PROFILE"

aws iam get-role-policy \
  --role-name "$SAGEMAKER_PIPELINE_ROLE_NAME" \
  --policy-name "${SAGEMAKER_PIPELINE_ROLE_NAME}-policy" \
  --profile "$AWS_PROFILE"

aws sagemaker describe-model-package-group \
  --model-package-group-name "$MODEL_PACKAGE_GROUP_NAME" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

Si alguno de estos comandos falla, el problema no esta en el tutorial local sino en el estado
IAM o en el bootstrap durable de la cuenta.

### 5. Verificar imports V3 y sesion base

```bash
uv run python - <<'PY'
from importlib.metadata import version

from sagemaker.core.helper.session_helper import Session
from sagemaker.mlops.workflow.pipeline import Pipeline
from sagemaker.serve.model_builder import ModelBuilder
from sagemaker.train import ModelTrainer

sm_version = version("sagemaker")
assert sm_version.split(".")[0] == "3", sm_version

print(f"sagemaker={sm_version}")
print("imports_ok=Session Pipeline ModelBuilder ModelTrainer")
PY
```

## IAM usado

- `DataScienceTutorialBootstrap` como policy temporal para validar el bootstrap durable de la
  fase 00 y para el bootstrap humano OIDC de la fase 05.
- `data-science-user` como identidad humana operativa del tutorial.

## Evidencia requerida

1. Salida de `uv sync`.
2. Salida del bloque AWS CLI de validacion.
3. Salida del bloque de imports y sesion.

## Criterio de cierre

- Workspace local creado.
- `.env.tutorial` listo.
- Recursos duraderos validados por AWS CLI.
- SageMaker SDK V3 instalado y verificado con `uv`.

## Riesgos/pendientes

- Si `GITHUB_REPOSITORY` sigue en `replace-me/replace-me`, la fase 05 no podra converger el
  trust OIDC correcto.
- Si DevOps no ha aplicado las policies o el bootstrap durable, las validaciones AWS CLI
  fallaran y no debes continuar con las fases 01-05.
- Esta fase no corrige recursos AWS; solo valida que ya existen y tienen el nombre esperado.

## Proximo paso

Continuar con [01-data-ingestion.md](./01-data-ingestion.md).
