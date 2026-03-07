# 04 Serving SageMaker

## Objetivo y contexto
Promover un modelo registrado hacia endpoints de `staging` y `prod` usando el patron V3
`ModelPackage -> ModelBuilder -> build() -> deploy() -> invoke()`.

La fuente de verdad de serving es el `ModelPackageArn` creado por la fase 03. El deploy no
consume artefactos ad hoc fuera del registry.

## Resultado minimo esperado
1. Un `ModelPackageArn` aprobado y listo para despliegue.
2. Un endpoint de `staging` creado con `ModelBuilder`.
3. Un smoke test ejecutado con `endpoint.invoke(...)`.
4. Un endpoint de `prod` desplegado solo despues del smoke test.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
2. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
3. `vendor/sagemaker-python-sdk/docs/api/sagemaker_serve.rst`
4. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-model-registry-example/v3-model-registry-example.ipynb`
5. `vendor/sagemaker-python-sdk/v3-examples/model-customization-examples/model_builder_deployment_notebook.ipynb`
6. `vendor/sagemaker-python-sdk/v3-examples/inference-examples/train-inference-e2e-example.ipynb`
7. `vendor/sagemaker-python-sdk/migration.md`

## Prerequisitos concretos
1. Fases 00-03 completadas.
2. `MODEL_PACKAGE_ARN` disponible.
3. `SAGEMAKER_EXECUTION_ROLE_ARN` disponible si el runtime no puede resolverlo solo.
4. Ejecutar desde la raiz del repositorio.

## Contrato de serving
| Parametro | Tipo | Default | Proposito |
|---|---|---|---|
| `ModelPackageArn` | String | requerido | Version aprobable para deploy |
| `StagingEndpointName` | String | `titanic-survival-staging` | Endpoint de validacion |
| `ProdEndpointName` | String | `titanic-survival-prod` | Endpoint productivo |
| `InstanceType` | String | `ml.m5.large` | Tipo de hosting |
| `InitialInstanceCount` | Integer | `1` | Capacidad inicial |

## Bootstrap auto-contenido

Este bloque deja el tutorial listo para ejecutarse sin depender de variables exportadas en
otra fase:

```bash
eval "$(python3 scripts/resolve_project_env.py --emit-exports)"
export MODEL_PACKAGE_ARN=$(python3 - <<'PY'
import boto3
import os

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")
resp = sm_client.list_model_packages(
    ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"],
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=1,
)
print(resp["ModelPackageSummaryList"][0]["ModelPackageArn"])
PY
)
export STAGING_ENDPOINT_NAME=${STAGING_ENDPOINT_NAME:-titanic-survival-staging}
export PROD_ENDPOINT_NAME=${PROD_ENDPOINT_NAME:-titanic-survival-prod}

echo "MODEL_PACKAGE_GROUP_NAME=$MODEL_PACKAGE_GROUP_NAME"
echo "MODEL_PACKAGE_ARN=$MODEL_PACKAGE_ARN"
echo "SAGEMAKER_EXECUTION_ROLE_ARN=$SAGEMAKER_EXECUTION_ROLE_ARN"
```

## Workshop paso a paso (celdas ejecutables)

### Celda 00 -- Bootstrap V3

```python
import os

import boto3
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.core.resources import ModelPackage
from sagemaker.serve.model_builder import ModelBuilder

AWS_PROFILE = os.getenv("AWS_PROFILE", "data-science-user")
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
MODEL_PACKAGE_ARN = os.environ["MODEL_PACKAGE_ARN"]
STAGING_ENDPOINT_NAME = os.getenv("STAGING_ENDPOINT_NAME", "titanic-survival-staging")
PROD_ENDPOINT_NAME = os.getenv("PROD_ENDPOINT_NAME", "titanic-survival-prod")
INSTANCE_TYPE = os.getenv("INSTANCE_TYPE", "ml.m5.large")
INITIAL_INSTANCE_COUNT = int(os.getenv("INITIAL_INSTANCE_COUNT", "1"))

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
session = Session(boto_session=boto_session)
sm_client = boto_session.client("sagemaker")

try:
    role_arn = get_execution_role()
except Exception:
    role_arn = os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"]

print(f"Region: {session.boto_region_name}")
try:
    print(f"SageMaker default bucket: {session.default_bucket()}")
except Exception as exc:
    print(f"SageMaker default bucket no disponible con el IAM actual: {exc}")
print(f"ModelPackageArn: {MODEL_PACKAGE_ARN}")
```

### Celda 01 -- Aprobar el Model Package si sigue pendiente

```python
mp_desc = sm_client.describe_model_package(ModelPackageName=MODEL_PACKAGE_ARN)
print(f"ModelPackageStatus: {mp_desc['ModelPackageStatus']}")
print(f"ModelApprovalStatus: {mp_desc['ModelApprovalStatus']}")

if mp_desc["ModelApprovalStatus"] != "Approved":
    sm_client.update_model_package(
        ModelPackageArn=MODEL_PACKAGE_ARN,
        ModelApprovalStatus="Approved",
    )
    print("ModelPackage aprobado")
```

### Celda 02 -- Construir `ModelBuilder` desde el registry

```python
model_package = ModelPackage.get(model_package_name=MODEL_PACKAGE_ARN)

staging_builder = ModelBuilder(
    model=model_package,
    role_arn=role_arn,
    sagemaker_session=session,
)
```

### Celda 03 -- Desplegar staging

```python
staging_model = staging_builder.build(model_name=f"{STAGING_ENDPOINT_NAME}-model")
staging_endpoint = staging_builder.deploy(
    endpoint_name=STAGING_ENDPOINT_NAME,
    instance_type=INSTANCE_TYPE,
    initial_instance_count=INITIAL_INSTANCE_COUNT,
)
print(f"Staging endpoint: {staging_endpoint.endpoint_name}")
```

Nota operativa:
- Si el endpoint ya existe, elimina el endpoint previo antes de reusar el mismo nombre.
- Este tutorial favorece `build() -> deploy() -> invoke()` sobre flujos de update in-place no
  cubiertos por los examples locales.

### Celda 04 -- Smoke test de staging

```python
sample_payload = "3,0,22,1,0,7.25,2\n1,1,38,1,0,71.2833,0\n"
response = staging_endpoint.invoke(
    body=sample_payload,
    content_type="text/csv",
)
predictions = response.body.read().decode("utf-8")
print(predictions)
assert predictions.strip(), "Smoke test devolvio respuesta vacia"
SMOKE_PASS = True
```

### Celda 05 -- Desplegar prod solo si staging pasa

```python
assert SMOKE_PASS is True, "No promover a prod si el smoke test falla"

prod_builder = ModelBuilder(
    model=model_package,
    role_arn=role_arn,
    sagemaker_session=session,
)
prod_model = prod_builder.build(model_name=f"{PROD_ENDPOINT_NAME}-model")
prod_endpoint = prod_builder.deploy(
    endpoint_name=PROD_ENDPOINT_NAME,
    instance_type=INSTANCE_TYPE,
    initial_instance_count=INITIAL_INSTANCE_COUNT,
)
print(f"Prod endpoint: {prod_endpoint.endpoint_name}")
```

### Celda 06 -- Verificacion final

```python
for endpoint_name in [STAGING_ENDPOINT_NAME, PROD_ENDPOINT_NAME]:
    desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
    print(f"{endpoint_name}: {desc['EndpointStatus']}")
```

### Celda 07 -- Cleanup opcional

```python
# Cuando termines las validaciones no productivas, elimina staging para reducir costo.
# staging_endpoint.delete()
```

## Decisiones tecnicas y alternativas descartadas
- El despliegue consume un `ModelPackage` del registry como entrada primaria.
- `ModelBuilder(model=model_package)` es el patron preferido para serving gobernado.
- El smoke test usa `endpoint.invoke()` en vez de patrones V2 tipo `predict()`.
- Se elimina el fallback de update manual del endpoint como camino principal del tutorial.

## IAM usado (roles/policies/permisos clave)
- Perfil operativo: `data-science-user`.
- Managed policies del operador para esta fase:
  `DataScienceObservabilityReadOnly`, `DataSciencePassroleRestricted`,
  `DataSciences3DataAccess` y `DataScienceSageMakerAuthoringRuntime`.
- Execution role de SageMaker para crear modelos y endpoints.
- Permisos de model registry para describir y aprobar el package.

## Evidencia requerida
1. `ModelPackageArn` y `ModelApprovalStatus=Approved`.
2. Estado final de `staging` y `prod`.
3. Resultado del smoke test.

## Criterio de cierre
- El modelo se despliega desde un `ModelPackageArn` aprobado.
- `staging` responde al smoke test.
- `prod` solo se despliega despues del smoke test.
- La traza `ModelPackage -> Endpoint` queda documentada.

## Riesgos/pendientes
- Reutilizar nombres de endpoint sin cleanup previo puede bloquear reejecuciones.
- Mantener `staging` activo fuera de validaciones incrementa costo sin aportar evidencia nueva.
- El rollback debe hacerse redeployando un `ModelPackageArn` anterior que ya este aprobado.

## Proximo paso
Formalizar el contrato de automatizacion alrededor de estas operaciones en
`docs/tutorials/05-cicd-github-actions.md`.
