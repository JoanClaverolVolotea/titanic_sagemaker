# 03 SageMaker Pipeline

## Objetivo y contexto

Construir y publicar el flujo `DataPreProcessing -> TrainModel -> ModelEvaluation ->
QualityGateAccuracy -> RegisterModel` sin depender del bucket por defecto de SageMaker para
staging implicito de scripts.

Los examples V3 vendoreados siguen siendo la referencia conceptual para `PipelineSession`,
`ProcessingStep`, `TrainingStep`, `ConditionStep` y `ModelStep`. En este repo, el camino
canonico de publicacion es:

1. empaquetar `pipeline/code/`,
2. subir scripts y bundle a `s3://$DATA_BUCKET/pipeline/code/...`,
3. actualizar la definicion durable en `terraform/03_sagemaker_pipeline`,
4. iniciar y monitorear la ejecucion del pipeline.

Este refactor alinea la fase 03 con la arquitectura del proyecto: pipeline definition durable
via Terraform y artefactos runtime via SageMaker.

## Resultado minimo esperado

1. El bundle de codigo y los scripts quedan publicados en el bucket del proyecto.
2. `terraform/03_sagemaker_pipeline` actualiza la definicion durable del pipeline con un
   `CodeBundleUri` trazable.
3. La ejecucion procesa datos desde `curated/`, evalua `metrics.accuracy` y registra el modelo
   solo si el gate pasa.
4. Queda evidencia de `PipelineExecutionArn`, estados por step y `ModelPackageArn`.

## Fuentes locales alineadas con SDK V3

1. `vendor/sagemaker-python-sdk/docs/overview.rst`
2. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
3. `vendor/sagemaker-python-sdk/docs/ml_ops/index.rst`
4. `vendor/sagemaker-python-sdk/docs/api/sagemaker_mlops.rst`
5. `vendor/sagemaker-python-sdk/docs/training/index.rst`
6. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
7. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-pipeline-train-create-registry.ipynb`
8. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-model-registry-example/v3-model-registry-example.ipynb`
9. `vendor/sagemaker-python-sdk/migration.md`

## Archivos locales usados en esta fase

- `pipeline/code/preprocess.py`
- `pipeline/code/evaluate.py`
- `scripts/publish_pipeline_code.sh`
- `terraform/03_sagemaker_pipeline/pipeline_definition.json.tpl`
- `terraform/03_sagemaker_pipeline/outputs.tf`
- `terraform/03_sagemaker_pipeline/terraform.tfvars.example`

## Prerequisitos concretos

1. Fases 00, 01 y 02 completadas.
2. Perfil AWS CLI `data-science-user` operativo.
3. Terraform disponible localmente.
4. Ejecutar desde la raiz del repositorio.

## Contrato del pipeline durable

### Parametros canonicos

| Parametro | Tipo | Default recomendado | Proposito |
|---|---|---|---|
| `CodeBundleUri` | String | `s3://<bucket>/pipeline/code/<sha>/pipeline_code.tar.gz` | Trazabilidad e invalidacion de cache |
| `InputTrainUri` | String | `s3://<bucket>/curated/train.csv` | Entrada de train |
| `InputValidationUri` | String | `s3://<bucket>/curated/validation.csv` | Entrada de validation |
| `AccuracyThreshold` | Float | `0.78` | Gate de calidad |

### Parametros publicados por Terraform

- `model_approval_status` no es parametro runtime del pipeline actual.
- El estado inicial del package se fija en Terraform y debe permanecer en
  `PendingManualApproval` hasta la fase 04.

### Contrato de evaluacion

`pipeline/code/evaluate.py` debe emitir `evaluation.json` con:

- `metrics.accuracy`
- `metrics.precision`
- `metrics.recall`
- `metrics.f1`
- `thresholds.passed`

## Bootstrap auto-contenido

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)
export PIPELINE_NAME=${PIPELINE_NAME:-titanic-modelbuild-dev}
export ACCURACY_THRESHOLD=${ACCURACY_THRESHOLD:-0.78}
```

## Paso a paso (ejecucion)

### 1. Verificar el codigo fuente del pipeline

```bash
ls -l \
  pipeline/code/preprocess.py \
  pipeline/code/evaluate.py \
  pipeline/code/requirements.txt
```

### 2. Publicar scripts y bundle en el bucket del proyecto

```bash
eval "$(
  AWS_PROFILE="$AWS_PROFILE" \
  AWS_REGION="$AWS_REGION" \
  scripts/publish_pipeline_code.sh --bucket "$DATA_BUCKET" --emit-exports
)"

echo "CODE_VERSION=$CODE_VERSION"
echo "CODE_BUNDLE_URI=$CODE_BUNDLE_URI"
echo "PREPROCESS_SCRIPT_S3_URI=$PREPROCESS_SCRIPT_S3_URI"
echo "EVALUATE_SCRIPT_S3_URI=$EVALUATE_SCRIPT_S3_URI"
```

Validar objetos publicados:

```bash
aws s3 ls "$CODE_BUNDLE_URI" --profile "$AWS_PROFILE"
aws s3 ls "$PREPROCESS_SCRIPT_S3_URI" --profile "$AWS_PROFILE"
aws s3 ls "$EVALUATE_SCRIPT_S3_URI" --profile "$AWS_PROFILE"
```

### 3. Validar y publicar la definicion durable del pipeline

```bash
terraform -chdir=terraform/03_sagemaker_pipeline fmt -check
terraform -chdir=terraform/03_sagemaker_pipeline validate

terraform -chdir=terraform/03_sagemaker_pipeline plan \
  -var="data_bucket_name=$DATA_BUCKET" \
  -var="code_bundle_uri=$CODE_BUNDLE_URI"

terraform -chdir=terraform/03_sagemaker_pipeline apply -auto-approve \
  -var="data_bucket_name=$DATA_BUCKET" \
  -var="code_bundle_uri=$CODE_BUNDLE_URI"
```

La publicacion durable queda respaldada por `terraform/03_sagemaker_pipeline/pipeline_definition.json.tpl`,
que consume los scripts desde:

- `s3://$DATA_BUCKET/pipeline/code/scripts/preprocess.py`
- `s3://$DATA_BUCKET/pipeline/code/scripts/evaluate.py`

### 4. Resolver outputs del pipeline publicado

```bash
export PIPELINE_NAME=$(terraform -chdir=terraform/03_sagemaker_pipeline output -raw pipeline_name)
export SAGEMAKER_PIPELINE_ROLE_ARN=$(terraform -chdir=terraform/03_sagemaker_pipeline output -raw pipeline_execution_role_arn)
export MODEL_PACKAGE_GROUP_NAME=$(terraform -chdir=terraform/03_sagemaker_pipeline output -raw model_package_group_name)

echo "PIPELINE_NAME=$PIPELINE_NAME"
echo "SAGEMAKER_PIPELINE_ROLE_ARN=$SAGEMAKER_PIPELINE_ROLE_ARN"
echo "MODEL_PACKAGE_GROUP_NAME=$MODEL_PACKAGE_GROUP_NAME"
```

### 5. Mapa entre la definicion durable y los patrones V3 del SDK

| Definicion del repo | Equivalente conceptual V3 |
|---|---|
| `DataPreProcessing` | `ScriptProcessor.run(...)` + `ProcessingStep` |
| `TrainModel` | `ModelTrainer.train()` + `TrainingStep` |
| `ModelEvaluation` | `ScriptProcessor.run(...)` + `ProcessingStep` + `PropertyFile` |
| `QualityGateAccuracy` | `ConditionStep` + `JsonGet(..., "metrics.accuracy")` |
| `RegisterModel-RegisterModel` | `ModelBuilder.register(...)` + `ModelStep` |
| `CodeBundleUri` | versionado del bundle + invalidacion de cache entre publicaciones |

Los examples vendoreados siguen siendo la referencia de diseno para estos conceptos. La
implementacion durable del repo se serializa en Terraform para evitar staging implicito en el
default bucket.

### 6. Iniciar una ejecucion con los parametros del run

```python
import json
import os

import boto3

session = boto3.Session(
    profile_name=os.getenv("AWS_PROFILE", "data-science-user"),
    region_name=os.getenv("AWS_REGION", "eu-west-1"),
)
sm_client = session.client("sagemaker")

response = sm_client.start_pipeline_execution(
    PipelineName=os.environ["PIPELINE_NAME"],
    PipelineParameters=[
        {"Name": "CodeBundleUri", "Value": os.environ["CODE_BUNDLE_URI"]},
        {"Name": "InputTrainUri", "Value": f"s3://{os.environ['DATA_BUCKET']}/curated/train.csv"},
        {"Name": "InputValidationUri", "Value": f"s3://{os.environ['DATA_BUCKET']}/curated/validation.csv"},
        {"Name": "AccuracyThreshold", "Value": os.getenv("ACCURACY_THRESHOLD", "0.78")},
    ],
)

PIPELINE_EXECUTION_ARN = response["PipelineExecutionArn"]
print(json.dumps(response, indent=2))
```

### 7. Monitorear steps y verificar registro

```python
import os
import time

import boto3

session = boto3.Session(
    profile_name=os.getenv("AWS_PROFILE", "data-science-user"),
    region_name=os.getenv("AWS_REGION", "eu-west-1"),
)
sm_client = session.client("sagemaker")
pipeline_execution_arn = os.environ["PIPELINE_EXECUTION_ARN"]
model_package_group_name = os.environ["MODEL_PACKAGE_GROUP_NAME"]

terminal_statuses = {"Succeeded", "Failed", "Stopped"}

while True:
    desc = sm_client.describe_pipeline_execution(PipelineExecutionArn=pipeline_execution_arn)
    status = desc["PipelineExecutionStatus"]
    print(f"Pipeline status: {status}")

    steps_resp = sm_client.list_pipeline_execution_steps(
        PipelineExecutionArn=pipeline_execution_arn,
        SortOrder="Ascending",
    )
    for item in steps_resp.get("PipelineExecutionSteps", []):
        print(f"  {item.get('StepName')} -> {item.get('StepStatus')}")

    if status in terminal_statuses:
        break
    time.sleep(30)

assert status == "Succeeded", f"Pipeline finalizo en {status}"

packages = sm_client.list_model_packages(
    ModelPackageGroupName=model_package_group_name,
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=5,
)["ModelPackageSummaryList"]

if packages:
    print(f"Latest ModelPackageArn: {packages[0]['ModelPackageArn']}")
```

### 8. Verificar el artefacto de evaluacion publicado

```bash
aws s3 ls "s3://$DATA_BUCKET/pipeline/runtime/$PIPELINE_NAME/evaluation/" --profile "$AWS_PROFILE"
```

### 9. Regla de republicacion cuando cambia `pipeline/code/`

Cada cambio en `pipeline/code/` debe repetir estos dos pasos:

1. volver a ejecutar `scripts/publish_pipeline_code.sh` para obtener un `CODE_BUNDLE_URI` nuevo
2. volver a ejecutar `terraform plan/apply` con ese `code_bundle_uri`

Aunque los scripts se montan desde `pipeline/code/scripts/*.py`, el `CodeBundleUri` sigue siendo
la senal trazable que invalida cache y deja evidencia de que el pipeline fue republicado con una
nueva version de codigo.

## Decisiones tecnicas y alternativas descartadas

- La publicacion canonica de esta fase es `project-bucket -> Terraform pipeline definition`,
  no `pipeline.upsert()` desde un notebook local.
- Se mantiene el mapeo conceptual a clases V3 porque los examples vendoreados siguen siendo la
  referencia de diseno.
- Se conserva `CodeBundleUri` como parametro de publicacion para trazabilidad e invalidacion de
  cache.
- Se descarta depender de `Session().default_bucket()` para staging de `preprocess.py` y
  `evaluate.py`.
- `evaluation.json` sigue siendo el contrato compartido entre fase 02 y fase 03.

## IAM usado (roles/policies/permisos clave)

- Perfil operativo: `data-science-user`.
- Managed policies del operador para esta fase:
  `DataScienceObservabilityReadOnly`, `DataSciencePassroleRestricted`,
  `DataSciences3DataAccess` y `DataScienceSageMakerAuthoringRuntime`.
- Role runtime del pipeline: `SAGEMAKER_PIPELINE_ROLE_ARN`.
- El role debe permitir processing, training, model package registration y acceso al bucket.
- El patron real de `iam:PassRole` en este repo debe incluir `titanic-sagemaker-pipeline-*`.
- El camino canonico de esta fase ya no requiere permisos adicionales sobre el default bucket de
  SageMaker.

## Evidencia requerida

1. `CODE_BUNDLE_URI` publicado.
2. `terraform plan` y `terraform apply` de `03_sagemaker_pipeline`.
3. `PipelineExecutionArn`.
4. Estado por step.
5. `ModelPackageArn` mas reciente del grupo.
6. `evaluation.json` publicado por el step de evaluacion.

## Criterio de cierre

- El bundle de codigo y los scripts quedan versionados en el bucket del proyecto.
- La definicion durable del pipeline queda publicada por Terraform con el `CodeBundleUri` del run.
- El gate usa `metrics.accuracy` desde `evaluation.json`.
- El modelo solo se registra si la condicion pasa.
- La ejecucion deja un `ModelPackageArn` trazable.

## Riesgos/pendientes

- Si cambias `pipeline/code/` sin rotar `CodeBundleUri`, puedes mantener cache o trazabilidad
  inconsistentes.
- Los prefijos `pipeline/runtime/.../preprocess/*` siguen siendo estables; si se contaminan con
  archivos legacy, XGBoost puede fallar al parsear.
- Si el repo mantiene otra definicion de pipeline fuera de Terraform, aparecera drift operativo.

## Proximo paso

Consumir el `ModelPackageArn` registrado en `docs/tutorials/04-serving-sagemaker.md`.
