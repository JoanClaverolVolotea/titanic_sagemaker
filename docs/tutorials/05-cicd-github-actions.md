# 05 CI/CD GitHub Actions

## Objetivo y contexto
Definir el contrato de automatizacion que GitHub Actions debe implementar alrededor del flujo
SageMaker V3 del proyecto.

Este archivo ya no prescribe YAML detallado ni sintaxis especifica de GitHub Actions, porque
esas piezas no forman parte de la documentacion vendoreada del SDK. La fuente de verdad aqui
es el comportamiento esperado de `ModelBuild` y `ModelDeploy` desde la perspectiva del
SageMaker SDK V3.

## Resultado minimo esperado
1. Un job de build publica `pipeline/code/` en el bucket del proyecto y sincroniza la definicion
   durable del pipeline.
2. El build inicia una ejecucion y conserva `PipelineExecutionArn`.
3. El build obtiene el `ModelPackageArn` registrado por el pipeline.
4. Un job de deploy despliega `staging`, ejecuta smoke test y solo entonces despliega `prod`.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
2. `vendor/sagemaker-python-sdk/docs/ml_ops/index.rst`
3. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
4. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-pipeline-train-create-registry.ipynb`
5. `vendor/sagemaker-python-sdk/v3-examples/ml-ops-examples/v3-model-registry-example/v3-model-registry-example.ipynb`
6. `vendor/sagemaker-python-sdk/v3-examples/model-customization-examples/model_builder_deployment_notebook.ipynb`
7. `vendor/sagemaker-python-sdk/migration.md`

## Prerequisitos concretos
1. Fases 00-04 completadas.
2. El repositorio debe exponer al runner las mismas variables necesarias que usan las fases 03
   y 04.
3. El sistema de CI debe proporcionar credenciales AWS validas para ejecutar el flujo V3.

## Bootstrap auto-contenido del contrato

Antes de traducir este contrato a un workflow real, puedes reconstruir localmente todas las
entradas necesarias desde este mismo tutorial:

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)
eval "$(
  AWS_PROFILE="$AWS_PROFILE" \
  AWS_REGION="$AWS_REGION" \
  scripts/publish_pipeline_code.sh --bucket "$DATA_BUCKET" --emit-exports
)"
export PIPELINE_NAME=${PIPELINE_NAME:-titanic-modelbuild-dev}
export SAGEMAKER_PIPELINE_ROLE_ARN=$(terraform -chdir=terraform/03_sagemaker_pipeline output -raw pipeline_execution_role_arn)
export MODEL_PACKAGE_GROUP_NAME=$(terraform -chdir=terraform/03_sagemaker_pipeline output -raw model_package_group_name)
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
export SAGEMAKER_EXECUTION_ROLE_ARN=${SAGEMAKER_EXECUTION_ROLE_ARN:-$SAGEMAKER_PIPELINE_ROLE_ARN}
export STAGING_ENDPOINT_NAME=${STAGING_ENDPOINT_NAME:-titanic-survival-staging}
export PROD_ENDPOINT_NAME=${PROD_ENDPOINT_NAME:-titanic-survival-prod}
```

## Contrato del job `ModelBuild`

### Entradas minimas
| Variable | Proposito |
|---|---|
| `DATA_BUCKET` | Bucket del proyecto |
| `CODE_BUNDLE_URI` | Bundle versionado publicado en `pipeline/code/<sha>/` |
| `SAGEMAKER_PIPELINE_ROLE_ARN` | Role del pipeline |
| `MODEL_PACKAGE_GROUP_NAME` | Grupo de registro |
| `PIPELINE_NAME` | Nombre del pipeline |
| `AWS_REGION` | Region del entorno |

### Pasos funcionales obligatorios
1. Instalar `sagemaker` 3.x en el runner.
2. Publicar `pipeline/code/` en `s3://$DATA_BUCKET/pipeline/code/...` usando
   `scripts/publish_pipeline_code.sh`.
3. Ejecutar `terraform plan/apply` sobre `terraform/03_sagemaker_pipeline` con el
   `code_bundle_uri` del run.
4. Iniciar una ejecucion del pipeline con los parametros runtime de la fase 03.
5. Esperar a un estado terminal de la ejecucion.
6. Leer el `ModelPackageArn` mas reciente del `ModelPackageGroup`.
7. Persistir como evidencia:
   - `PipelineExecutionArn`,
   - estado por step,
   - `ModelPackageArn`.

### Salidas minimas del build
- `PipelineExecutionArn`
- `ModelPackageArn`
- resumen de steps del pipeline

## Contrato del job `ModelDeploy`

### Entradas minimas
| Variable | Proposito |
|---|---|
| `MODEL_PACKAGE_ARN` | Package a desplegar |
| `SAGEMAKER_EXECUTION_ROLE_ARN` | Role de hosting |
| `STAGING_ENDPOINT_NAME` | Endpoint de staging |
| `PROD_ENDPOINT_NAME` | Endpoint de prod |
| `AWS_REGION` | Region del entorno |

### Pasos funcionales obligatorios
1. Cargar `ModelPackage` desde registry.
2. Garantizar `ModelApprovalStatus=Approved` antes del deploy.
3. Desplegar `staging` con `ModelBuilder(model=model_package)`.
4. Ejecutar smoke test con `endpoint.invoke(...)`.
5. Desplegar `prod` solo si el smoke test pasa.
6. Persistir como evidencia:
   - `ModelPackageArn`,
   - estado final de `staging`,
   - estado final de `prod`.

## Reglas de implementacion para este proyecto
- El workflow de CI/CD debe invocar exactamente los patrones V3 documentados en las fases 03
  y 04.
- El workflow no debe introducir APIs V2 como `Estimator`, `Model` o `Predictor`.
- El pipeline debe seguir registrando modelos via `ModelBuilder.register(...)`.
- El deploy debe seguir consumiendo `ModelPackageArn`, no artefactos de entrenamiento
  sueltos.

## Validacion operativa recomendada
- Ejecutar una corrida manual de las fases 03 y 04 antes de encapsularlas en un workflow.
- Comparar la evidencia del run automatizado contra la evidencia manual:
  - mismo nombre de pipeline,
  - mismo grupo de registro,
  - mismo contrato de smoke test,
  - mismo shape de `evaluation.json`.

## Decisiones tecnicas y alternativas descartadas
- Se documenta el contrato SageMaker del workflow, no la sintaxis del proveedor CI.
- El registro en Model Registry es obligatorio entre build y deploy.
- Se descarta deploy directo a prod sin `staging` ni smoke test.
- Se descartan flujos que actualizan endpoints desde artefactos no registrados.

## IAM usado (roles/policies/permisos clave)
- El runner no debe reutilizar access keys de `data-science-user`.
- El runner debe asumir un rol OIDC dedicado con:
  `docs/aws/policies/11-gha-oidc-trust-policy.json` como trust policy y
  `docs/aws/policies/12-gha-sagemaker-deployer-policy.json` como base de permisos.
- Ese rol debe poder ejecutar el mismo contrato SageMaker de las fases 03 y 04.
- Role de pipeline para processing/training/registry.
- Role de hosting para modelos y endpoints.

## Evidencia requerida
1. `PipelineExecutionArn`.
2. `ModelPackageArn`.
3. Estados de `staging` y `prod`.
4. Resultado del smoke test.

## Criterio de cierre
- Existe un contrato CI/CD claro y 100% consistente con las fases 03 y 04.
- El workflow futuro no necesitara reinterpretar la API de SageMaker fuera de este roadmap.

## Riesgos/pendientes
- La instrumentacion especifica de GitHub Actions queda fuera de este tutorial y debe
  documentarse aparte cuando se implemente.
- Si el workflow encapsula una logica distinta a las fases 03 y 04, aparecera drift.

## Proximo paso
Definir una capa minima de observabilidad centrada en recursos de SageMaker en
`docs/tutorials/06-observability-operations.md`.
