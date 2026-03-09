# 06 Observability and Operations

## Objetivo y contexto
Definir una practica operativa minima centrada en recursos de SageMaker: pipeline
executions, model packages, endpoints y artefactos de evaluacion.

Este tutorial elimina prescripciones detalladas sobre servicios AWS externos no cubiertos por
la documentacion vendoreada del SDK. La meta aqui es dejar un runbook reproducible a partir
de los recursos de SageMaker que el proyecto ya crea.

## Resultado minimo esperado
1. El operador puede inspeccionar el estado de un pipeline execution y sus steps.
2. El operador puede localizar el ultimo `ModelPackageArn` y su approval status.
3. El operador puede verificar el estado de `staging` y `prod`.
4. El operador puede reejecutar un smoke test de inferencia.
5. El operador puede validar el contrato de `evaluation.json`.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/sagemaker_core/index.rst`
2. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
3. `vendor/sagemaker-python-sdk/docs/ml_ops/index.rst`
4. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
5. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-pipeline-train-create-registry.ipynb`
6. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-model-registry-example/v3-model-registry-example.ipynb`

## Prerequisitos concretos
1. Fases 00-04 completadas.
2. `PIPELINE_NAME`, `MODEL_PACKAGE_GROUP_NAME` y al menos un endpoint desplegado.
3. Perfil `data-science-user` operativo.

## Bootstrap auto-contenido

Este bloque reconstruye todas las variables del runbook sin depender de otra sesion:

```bash
eval "$(python3 scripts/resolve_project_env.py --emit-exports)"
```

## Operador minimo: sesion y clientes

```python
import os

import boto3
from sagemaker.core.helper.session_helper import Session

AWS_PROFILE = os.getenv("AWS_PROFILE", "data-science-user")
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
PIPELINE_NAME = os.getenv("PIPELINE_NAME", "titanic-modelbuild-dev")
MODEL_PACKAGE_GROUP_NAME = os.getenv("MODEL_PACKAGE_GROUP_NAME", "titanic-survival-xgboost")
STAGING_ENDPOINT_NAME = os.getenv("STAGING_ENDPOINT_NAME", "titanic-survival-staging")
PROD_ENDPOINT_NAME = os.getenv("PROD_ENDPOINT_NAME", "titanic-survival-prod")

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
session = Session(boto_session=boto_session)
sm_client = boto_session.client("sagemaker")
sm_runtime_client = boto_session.client("sagemaker-runtime")

print(f"Region: {session.boto_region_name}")
try:
    print(f"SageMaker default bucket: {session.default_bucket()}")
except Exception as exc:
    print(f"SageMaker default bucket no disponible con el IAM actual: {exc}")
```

## Entregable 1 -- Inspeccion de pipeline executions

```python
executions = sm_client.list_pipeline_executions(
    PipelineName=PIPELINE_NAME,
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
```

## Entregable 2 -- Inspeccion de Model Registry

```python
packages = sm_client.list_model_packages(
    ModelPackageGroupName=MODEL_PACKAGE_GROUP_NAME,
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=5,
)["ModelPackageSummaryList"]

for package in packages:
    desc = sm_client.describe_model_package(ModelPackageName=package["ModelPackageArn"])
    print(package["ModelPackageArn"], desc["ModelApprovalStatus"])
```

## Entregable 3 -- Verificacion de endpoints

```python
for endpoint_name in [STAGING_ENDPOINT_NAME, PROD_ENDPOINT_NAME]:
    desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
    print(endpoint_name, desc["EndpointStatus"])
```

## Entregable 4 -- Smoke test operativo

Smoke test auto-contenido sin depender del objeto `staging_endpoint` de otra fase:

```python
sample_payload = "3,0,22,1,0,7.25,2\n"

response = sm_runtime_client.invoke_endpoint(
    EndpointName=STAGING_ENDPOINT_NAME,
    ContentType="text/csv",
    Body=sample_payload.encode("utf-8"),
)
print(response["Body"].read().decode("utf-8"))
```

## Entregable 5 -- Validacion del contrato de evaluacion

```bash
python3 - <<'PY'
import json
from pathlib import Path

payload = json.loads(Path("data/titanic/sagemaker/evaluation.json").read_text(encoding="utf-8"))
assert "metrics" in payload and "accuracy" in payload["metrics"]
assert "thresholds" in payload and "passed" in payload["thresholds"]
print(json.dumps(payload, indent=2))
PY
```

## Runbook por sintoma
| Sintoma | Causa raiz probable | Accion recomendada |
|---|---|---|
| El pipeline termina en `Failed` | Script de preprocess/evaluate, permisos o datos | Revisar el ultimo execution, identificar el step y corregir antes de relanzar |
| No aparece `ModelPackageArn` nuevo | El gate no paso o el register no ejecuto | Confirmar `metrics.accuracy` y el status del `ConditionStep` |
| `staging` no responde al smoke test | Endpoint no esta listo o el payload no coincide | Verificar `EndpointStatus` y repetir `endpoint.invoke(...)` |
| `prod` no debe promoverse | `staging` no paso smoke | Mantener `ModelApprovalStatus` controlado y no desplegar prod |
| `evaluation.json` no tiene `metrics.accuracy` | Drift del script `pipeline/code/evaluate.py` | Corregir el contrato antes de tocar el pipeline |

## Alcance explicitamente excluido de este tutorial
Quedan fuera de alcance aqui, porque no estan descritos por la documentacion vendoreada del
SDK y el repo no trae una implementacion canonica V3 para ellos:
- alarmas detalladas de CloudWatch,
- reglas de EventBridge,
- wiring de notificaciones externas,
- configuracion final de data capture / monitoring schedules.

Si esas piezas se implementan mas adelante, deben documentarse en `docs/iterations/` sin
contradecir este runbook base de SageMaker.

## Decisiones tecnicas y alternativas descartadas
- La observabilidad base se centra en recursos de SageMaker que el proyecto ya usa.
- Se prioriza inspeccion reproducible de pipeline, registry y endpoints sobre integraciones
  externas no vendoreadas.
- Se descarta prescribir comandos de otros servicios AWS como parte del tutorial canonico.

## IAM usado (roles/policies/permisos clave)
- Perfil operativo: `data-science-user`.
- Para inspeccion, logs, metricas y smoke test operativo: `DataScienceTutorialOperator`.

## Evidencia requerida
1. Ultimo `PipelineExecutionArn` y estados por step.
2. `ModelPackageArn` mas reciente y `ModelApprovalStatus`.
3. Estado actual de `staging` y `prod`.
4. Salida del smoke test.

## Criterio de cierre
- El operador puede responder al estado actual del sistema usando solo recursos de SageMaker.
- Existe un runbook reproducible sin depender de servicios externos al alcance del SDK local.

## Riesgos/pendientes
- La capa de alarmado y notificaciones sigue pendiente de documentacion separada.
- Si la evidencia local (`evaluation.json`) no se conserva, el triage pierde contexto.

## Proximo paso
Aplicar reglas de costo y limpieza centradas en recursos de SageMaker en
`docs/tutorials/07-cost-governance.md`.
