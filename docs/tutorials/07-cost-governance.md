# 07 Cost and Governance

## Objetivo y contexto

Aplicar un patron simple de inventario y cleanup para los recursos que realmente genera este
tutorial: training jobs, endpoints, pipeline executions, model packages y artefactos en S3.

## Resultado minimo esperado

1. Inventario actual de recursos activos.
2. Checklist de costo minimo aplicado.
3. Cleanup manual reproducible para `staging`, `prod`, modelos, pipeline y objetos S3.

## Prerequisitos concretos

1. Fases 00-04 completadas.
2. Bundle IAM disponible para esta fase:
   - `DataScienceTutorialOperator` para inventario
   - `DataScienceTutorialCleanup` para borrado

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Inventario de recursos activos

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")

print("[training-jobs]")
for item in sm_client.list_training_jobs(
    NameContains="titanic-",
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=10,
)["TrainingJobSummaries"]:
    print(item["TrainingJobName"], item["TrainingJobStatus"])

print("[pipelines]")
for item in sm_client.list_pipelines(
    PipelineNamePrefix="titanic-",
    MaxResults=10,
)["PipelineSummaries"]:
    print(item["PipelineName"])

print("[model-packages]")
for item in sm_client.list_model_packages(
    ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"],
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=10,
)["ModelPackageSummaryList"]:
    print(item["ModelPackageArn"], item["ModelApprovalStatus"])

print("[endpoints]")
for endpoint_name in [os.environ["STAGING_ENDPOINT_NAME"], os.environ["PROD_ENDPOINT_NAME"]]:
    try:
        desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
        print(endpoint_name, desc["EndpointStatus"])
    except sm_client.exceptions.ClientError as exc:
        print(endpoint_name, f"not_found={exc.response['Error']['Code']}")
PY
```

### 2. Inventario rapido de artefactos S3

```bash
aws s3 ls "s3://$DATA_BUCKET/raw/" --profile "$AWS_PROFILE"
aws s3 ls "s3://$DATA_BUCKET/curated/" --profile "$AWS_PROFILE"
aws s3 ls "s3://$DATA_BUCKET/training/" --recursive --summarize --profile "$AWS_PROFILE"
aws s3 ls "s3://$DATA_BUCKET/evaluation/" --recursive --summarize --profile "$AWS_PROFILE"
aws s3 ls "s3://$DATA_BUCKET/pipeline/" --recursive --summarize --profile "$AWS_PROFILE"
```

### 3. Checklist minimo de costo

1. Mantener `ml.m5.large` y `instance_count=1` salvo necesidad real.
2. Borrar `staging` cuando ya no estes validando.
3. No mantener paquetes no usados sin motivo.
4. Evitar relanzar training o pipeline si la evidencia actual ya sirve.

### 4. Borrar `staging`

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")

endpoint_name = os.environ["STAGING_ENDPOINT_NAME"]
config_name = None
model_name = None

try:
    endpoint_desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
    config_name = endpoint_desc["EndpointConfigName"]
    config_desc = sm_client.describe_endpoint_config(EndpointConfigName=config_name)
    model_name = config_desc["ProductionVariants"][0]["ModelName"]
    sm_client.delete_endpoint(EndpointName=endpoint_name)
    print(f"deleted_endpoint={endpoint_name}")
except Exception as exc:
    print(f"skip_endpoint={exc}")

if config_name:
    try:
        sm_client.delete_endpoint_config(EndpointConfigName=config_name)
        print(f"deleted_endpoint_config={config_name}")
    except Exception as exc:
        print(f"skip_endpoint_config={exc}")

if model_name:
    try:
        sm_client.delete_model(ModelName=model_name)
        print(f"deleted_model={model_name}")
    except Exception as exc:
        print(f"skip_model={exc}")
PY
```

### 5. Borrar `prod`

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")

endpoint_name = os.environ["PROD_ENDPOINT_NAME"]
config_name = None
model_name = None

try:
    endpoint_desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
    config_name = endpoint_desc["EndpointConfigName"]
    config_desc = sm_client.describe_endpoint_config(EndpointConfigName=config_name)
    model_name = config_desc["ProductionVariants"][0]["ModelName"]
    sm_client.delete_endpoint(EndpointName=endpoint_name)
    print(f"deleted_endpoint={endpoint_name}")
except Exception as exc:
    print(f"skip_endpoint={exc}")

if config_name:
    try:
        sm_client.delete_endpoint_config(EndpointConfigName=config_name)
        print(f"deleted_endpoint_config={config_name}")
    except Exception as exc:
        print(f"skip_endpoint_config={exc}")

if model_name:
    try:
        sm_client.delete_model(ModelName=model_name)
        print(f"deleted_model={model_name}")
    except Exception as exc:
        print(f"skip_model={exc}")
PY
```

### 6. Borrar el pipeline y los model packages

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")

packages = sm_client.list_model_packages(
    ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"],
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=50,
)["ModelPackageSummaryList"]
for item in packages:
    try:
        sm_client.delete_model_package(ModelPackageName=item["ModelPackageArn"])
        print(f"deleted_model_package={item['ModelPackageArn']}")
    except Exception as exc:
        print(f"skip_model_package={exc}")

try:
    sm_client.delete_pipeline(PipelineName=os.environ["PIPELINE_NAME"])
    print(f"deleted_pipeline={os.environ['PIPELINE_NAME']}")
except Exception as exc:
    print(f"skip_pipeline={exc}")

try:
    sm_client.delete_model_package_group(ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"])
    print(f"deleted_model_package_group={os.environ['MODEL_PACKAGE_GROUP_NAME']}")
except Exception as exc:
    print(f"skip_model_package_group={exc}")
PY
```

### 7. Limpiar artefactos S3 del tutorial

```bash
aws s3 rm "s3://$DATA_BUCKET/raw/" --recursive --profile "$AWS_PROFILE"
aws s3 rm "s3://$DATA_BUCKET/curated/" --recursive --profile "$AWS_PROFILE"
aws s3 rm "s3://$DATA_BUCKET/training/" --recursive --profile "$AWS_PROFILE"
aws s3 rm "s3://$DATA_BUCKET/evaluation/" --recursive --profile "$AWS_PROFILE"
aws s3 rm "s3://$DATA_BUCKET/pipeline/" --recursive --profile "$AWS_PROFILE"
```

## IAM usado

- `DataScienceTutorialOperator` para inventario.
- `DataScienceTutorialCleanup` para borrar recursos y objetos.

## Evidencia requerida

1. Inventario antes del cleanup.
2. Salida de los borrados ejecutados.
3. Estado final del bucket y de los endpoints.

## Criterio de cierre

- Sabes que recursos siguen costando dinero.
- Puedes borrar el footprint del tutorial sin recurrir a archivos externos.

## Riesgos/pendientes

- Borrar `prod` sin confirmar el entorno correcto es destructivo.
- Si eliminas el Model Package Group, la fase 03 necesitara bootstrap de nuevo antes de
  registrar otro modelo.

## Proximo paso

Repetir el roadmap desde [`00-foundations.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/00-foundations.md) cuando quieras reconstruir el entorno desde cero.
