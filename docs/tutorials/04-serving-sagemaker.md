# 04 Serving SageMaker

## Objetivo y contexto

Desplegar el ultimo `ModelPackageArn` del tutorial hacia `staging` y `prod` usando
`ModelBuilder`, validar `staging` con un smoke test y promover a `prod` solo si responde.

## Resultado minimo esperado

1. `ModelPackageArn` aprobado.
2. Endpoint `staging` operativo.
3. Smoke test exitoso.
4. Endpoint `prod` desplegado despues del smoke test.

## Prerequisitos concretos

1. Fases 00-03 completadas.
2. Bundle IAM disponible para esta fase: `DataScienceTutorialOperator`.
3. `DataScienceTutorialCleanup` solo si vas a borrar endpoints previos para reusar el mismo
   nombre.

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Resolver el `ModelPackageArn`

Si la fase 03 dejo `latest_model_package_arn.txt`, lo usa directamente. Si no, consulta el
registry para obtener el ultimo package.

```python
import os
from pathlib import Path

import boto3

target = Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "latest_model_package_arn.txt"
if not target.exists():
    session = boto3.Session(
        profile_name=os.environ["AWS_PROFILE"],
        region_name=os.environ["AWS_REGION"],
    )
    sm_client = session.client("sagemaker")
    packages = sm_client.list_model_packages(
        ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"],
        SortBy="CreationTime",
        SortOrder="Descending",
        MaxResults=1,
    )["ModelPackageSummaryList"]
    if not packages:
        raise SystemExit("No hay ModelPackageArn para desplegar")
    target.write_text(packages[0]["ModelPackageArn"] + "\n", encoding="utf-8")

print(target.read_text(encoding="utf-8").strip())
```

Guarda como `$TUTORIAL_ROOT/scripts/resolve_model_package.py` y ejecuta:

```bash
cat > "$TUTORIAL_ROOT/scripts/resolve_model_package.py" <<'PYEOF'
# (pega aqui el contenido Python de arriba)
PYEOF

uv run python "$TUTORIAL_ROOT/scripts/resolve_model_package.py"

export MODEL_PACKAGE_ARN=$(cat "$TUTORIAL_ROOT/artifacts/latest_model_package_arn.txt")
echo "MODEL_PACKAGE_ARN=$MODEL_PACKAGE_ARN"
```

### 2. Aprobar el package si sigue pendiente

```python
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")
desc = sm_client.describe_model_package(ModelPackageName=os.environ["MODEL_PACKAGE_ARN"])
print(f"model_package_status={desc['ModelPackageStatus']}")
print(f"model_approval_status={desc['ModelApprovalStatus']}")

if desc["ModelApprovalStatus"] != "Approved":
    sm_client.update_model_package(
        ModelPackageArn=os.environ["MODEL_PACKAGE_ARN"],
        ModelApprovalStatus="Approved",
    )
    print("model_package_approved=true")
```

Guarda como `$TUTORIAL_ROOT/scripts/approve_model_package.py` y ejecuta:

```bash
cat > "$TUTORIAL_ROOT/scripts/approve_model_package.py" <<'PYEOF'
# (pega aqui el contenido Python de arriba)
PYEOF

uv run python "$TUTORIAL_ROOT/scripts/approve_model_package.py"
```

### 3. Desplegar `staging`

Extrae la imagen y el artefacto del modelo registrado, y despliega con `ModelBuilder`.

```python
import os
from pathlib import Path

import boto3
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.core.resources import ModelPackage
from sagemaker.serve.model_builder import ModelBuilder

boto_session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
session = Session(boto_session=boto_session, default_bucket=os.environ["DATA_BUCKET"])

try:
    role_arn = get_execution_role()
except Exception:
    role_arn = os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"]

model_package = ModelPackage.get(model_package_name=os.environ["MODEL_PACKAGE_ARN"])
container = model_package.inference_specification.containers[0]

builder = ModelBuilder(
    s3_model_data_url=container.model_data_url,
    image_uri=container.image,
    role_arn=role_arn,
    sagemaker_session=session,
)
builder.build(model_name=f"{os.environ['STAGING_ENDPOINT_NAME']}-model")
endpoint = builder.deploy(
    endpoint_name=os.environ["STAGING_ENDPOINT_NAME"],
    instance_type="ml.m5.large",
    initial_instance_count=1,
)

target = Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "staging_endpoint_name.txt"
target.write_text(endpoint.endpoint_name + "\n", encoding="utf-8")
print(f"staging_endpoint={endpoint.endpoint_name}")
```

Guarda como `$TUTORIAL_ROOT/scripts/deploy_staging.py` y ejecuta:

```bash
cat > "$TUTORIAL_ROOT/scripts/deploy_staging.py" <<'PYEOF'
# (pega aqui el contenido Python de arriba)
PYEOF

uv run python "$TUTORIAL_ROOT/scripts/deploy_staging.py"
```

### 4. Ejecutar smoke test

Envia dos filas de ejemplo al endpoint `staging` y verifica que responde.

```python
import os
from pathlib import Path

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
runtime_client = session.client("sagemaker-runtime")

payload = "3,0,22,1,0,7.25,2\n1,1,38,1,0,71.2833,0\n"
response = runtime_client.invoke_endpoint(
    EndpointName=os.environ["STAGING_ENDPOINT_NAME"],
    ContentType="text/csv",
    Body=payload.encode("utf-8"),
)
predictions = response["Body"].read().decode("utf-8")
assert predictions.strip(), "Smoke test vacio"
target = Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "staging_smoke_test.txt"
target.write_text(predictions + "\n", encoding="utf-8")
print(predictions)
```

Guarda como `$TUTORIAL_ROOT/scripts/smoke_test_staging.py` y ejecuta:

```bash
cat > "$TUTORIAL_ROOT/scripts/smoke_test_staging.py" <<'PYEOF'
# (pega aqui el contenido Python de arriba)
PYEOF

uv run python "$TUTORIAL_ROOT/scripts/smoke_test_staging.py"
```

### 5. Desplegar `prod`

Replica el mismo modelo aprobado en el endpoint de produccion.

```python
import os

import boto3
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.core.resources import ModelPackage
from sagemaker.serve.model_builder import ModelBuilder

boto_session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
session = Session(boto_session=boto_session, default_bucket=os.environ["DATA_BUCKET"])

try:
    role_arn = get_execution_role()
except Exception:
    role_arn = os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"]

model_package = ModelPackage.get(model_package_name=os.environ["MODEL_PACKAGE_ARN"])
container = model_package.inference_specification.containers[0]

builder = ModelBuilder(
    s3_model_data_url=container.model_data_url,
    image_uri=container.image,
    role_arn=role_arn,
    sagemaker_session=session,
)
builder.build(model_name=f"{os.environ['PROD_ENDPOINT_NAME']}-model")
endpoint = builder.deploy(
    endpoint_name=os.environ["PROD_ENDPOINT_NAME"],
    instance_type="ml.m5.large",
    initial_instance_count=1,
)
print(f"prod_endpoint={endpoint.endpoint_name}")
```

Guarda como `$TUTORIAL_ROOT/scripts/deploy_prod.py` y ejecuta:

```bash
cat > "$TUTORIAL_ROOT/scripts/deploy_prod.py" <<'PYEOF'
# (pega aqui el contenido Python de arriba)
PYEOF

uv run python "$TUTORIAL_ROOT/scripts/deploy_prod.py"
```

### 6. Verificar ambos endpoints

```python
import os

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")

for endpoint_name in [os.environ["STAGING_ENDPOINT_NAME"], os.environ["PROD_ENDPOINT_NAME"]]:
    desc = sm_client.describe_endpoint(EndpointName=endpoint_name)
    print(f"{endpoint_name}: {desc['EndpointStatus']}")
```

Guarda como `$TUTORIAL_ROOT/scripts/verify_endpoints.py` y ejecuta:

```bash
cat > "$TUTORIAL_ROOT/scripts/verify_endpoints.py" <<'PYEOF'
# (pega aqui el contenido Python de arriba)
PYEOF

uv run python "$TUTORIAL_ROOT/scripts/verify_endpoints.py"
```

### 7. Cleanup opcional de `staging`

Si quieres borrar staging al terminar las validaciones, pasa a la fase 07 o ejecuta el borrado
manual con `DataScienceTutorialCleanup`.

## IAM usado

- `DataScienceTutorialOperator` para describir packages, aprobarlos y desplegar endpoints.
- `DataScienceTutorialCleanup` solo para borrar endpoints, configs y modelos si reusas nombres.

## Evidencia requerida

1. `MODEL_PACKAGE_ARN`
2. `staging_smoke_test.txt`
3. Estados finales de `staging` y `prod`

## Criterio de cierre

- `staging` responde al smoke test.
- `prod` se despliega desde el mismo `ModelPackageArn`.
- La promocion queda gobernada por registry + smoke test.

## Riesgos/pendientes

- Si intentas reusar un nombre de endpoint sin cleanup, el deploy puede fallar.
- Mantener `staging` activo despues de validar aumenta costo sin aportar evidencia extra.

## Proximo paso

Continuar con [`05-cicd-github-actions.md`](./05-cicd-github-actions.md).
