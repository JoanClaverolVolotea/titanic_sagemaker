# 06 Observability and Operations

## Objetivo y contexto

Operar el estado actual del tutorial usando solo consultas reproducibles sobre pipeline
executions, Model Registry, endpoints y la evidencia local generada en fases anteriores.

## Resultado minimo esperado

1. Ultimo pipeline execution inspeccionado.
2. Ultimo `ModelPackageArn` y su approval status confirmados.
3. Estados de `staging` y `prod` verificados.
4. Smoke test operativo repetible.
5. Contrato de `evaluation.json` validado.

## Prerequisitos concretos

1. Fases 00-04 completadas.
2. Bundle IAM disponible para esta fase: `DataScienceTutorialOperator`.

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Inspeccionar el ultimo pipeline execution

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")
executions = sm_client.list_pipeline_executions(
    PipelineName=os.environ["PIPELINE_NAME"],
    MaxResults=5,
)["PipelineExecutionSummaries"]

for item in executions:
    print(item["PipelineExecutionArn"], item["PipelineExecutionStatus"])

latest_execution_arn = executions[0]["PipelineExecutionArn"]
steps = sm_client.list_pipeline_execution_steps(
    PipelineExecutionArn=latest_execution_arn,
    SortOrder="Ascending",
)["PipelineExecutionSteps"]

for step in steps:
    print(step["StepName"], step["StepStatus"])
PY
```

### 2. Revisar el Model Registry

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
    MaxResults=5,
)["ModelPackageSummaryList"]

for package in packages:
    desc = sm_client.describe_model_package(ModelPackageName=package["ModelPackageArn"])
    print(package["ModelPackageArn"], desc["ModelApprovalStatus"])
PY
```

### 3. Comprobar endpoints

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")

for endpoint_name in [os.environ["STAGING_ENDPOINT_NAME"], os.environ["PROD_ENDPOINT_NAME"]]:
    desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
    print(endpoint_name, desc["EndpointStatus"])
PY
```

### 4. Repetir el smoke test

```bash
uv run python - <<'PY'
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
runtime_client = session.client("sagemaker-runtime")
response = runtime_client.invoke_endpoint(
    EndpointName=os.environ["STAGING_ENDPOINT_NAME"],
    ContentType="text/csv",
    Body="3,0,22,1,0,7.25,2\n".encode("utf-8"),
)
print(response["Body"].read().decode("utf-8"))
PY
```

### 5. Validar la evidencia local de evaluacion

```bash
uv run python - <<'PY'
import json
import os
from pathlib import Path

payload = json.loads(
    (Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "evaluation.json").read_text(
        encoding="utf-8"
    )
)
assert "metrics" in payload and "accuracy" in payload["metrics"]
assert "thresholds" in payload and "passed" in payload["thresholds"]
print(json.dumps(payload, indent=2))
PY
```

## Runbook por sintoma

| Sintoma | Causa raiz probable | Accion recomendada |
|---|---|---|
| El pipeline termina en `Failed` | Datos, IAM o codigo del step | Revisar el ultimo execution y corregir antes de relanzar |
| No aparece `ModelPackageArn` nuevo | El gate no paso o el register no se ejecuto | Confirmar `metrics.accuracy` y el estado de `QualityGateAccuracy` |
| `staging` no responde | Endpoint no listo o payload invalido | Verificar `EndpointStatus` y repetir el smoke test |
| `prod` no debe promoverse | `staging` no paso smoke | Mantener solo `staging` y corregir antes de redeployar |
| `evaluation.json` no tiene `metrics.accuracy` | Drift del evaluador local | Regenerar `evaluate.py` y repetir la fase 02 o 03 |

## IAM usado

- `DataScienceTutorialOperator` para describir recursos y ejecutar el smoke test.

## Evidencia requerida

1. Ultimo `PipelineExecutionArn` y sus steps.
2. `ModelPackageArn` mas reciente y approval status.
3. Estado de `staging` y `prod`.
4. Salida del smoke test.

## Criterio de cierre

- El operador puede explicar el estado del sistema con consultas repetibles.
- `evaluation.json` sigue teniendo el contrato esperado.

## Riesgos/pendientes

- Si borras la evidencia local antes de validar, pierdes contexto de troubleshooting.
- Si promocionas sin revisar `staging`, el rollback se vuelve mas caro.

## Proximo paso

Continuar con [`07-cost-governance.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/07-cost-governance.md).
