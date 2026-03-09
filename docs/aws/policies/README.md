# IAM policies for tutorial operators

Este directorio contiene solo las managed policies humanas necesarias para ejecutar
`docs/tutorials/00-07`.

## Goal

Mantener un set minimo y removible de permisos para el operador humano:

- `DataScienceTutorialBootstrap`
- `DataScienceTutorialOperator`
- `DataScienceTutorialCleanup`

El rol de GitHub Actions no usa JSON estaticos en este directorio. Su trust policy y su
permissions policy se generan desde `scripts/ensure_github_actions_role.py`.

## Change

El directorio queda reducido a:

- `01-ds-tutorial-bootstrap.json` -> `DataScienceTutorialBootstrap`
- `02-ds-tutorial-operator.json` -> `DataScienceTutorialOperator`
- `03-ds-tutorial-cleanup.json` -> `DataScienceTutorialCleanup`

No se incluyen aqui:

- policies opcionales de administracion IAM
- policies opcionales de `AssumeRole` cross-env
- documentos estaticos del rol OIDC de GitHub Actions

## Why

- `Bootstrap` cubre solo bucket, roles del proyecto, Model Package Group y el bootstrap
  humano del provider/rol OIDC.
- `Operator` cubre la ejecucion normal de fases 01-06 y la observabilidad base.
- `Cleanup` cubre stop/delete/reset y conserva en exclusiva la eliminacion de objetos S3.
- El rol de GitHub Actions ya se converge por script a partir del manifest; mantener JSON
  duplicados aqui solo introduce drift.

## Mapa fase -> policy minima

| Fase | Policy minima |
| --- | --- |
| `00-foundations` | `DataScienceTutorialBootstrap` |
| `01-data-ingestion` | `DataScienceTutorialOperator` |
| `02-training-validation` | `DataScienceTutorialOperator` |
| `03-sagemaker-pipeline` | `DataScienceTutorialOperator` |
| `04-serving-sagemaker` | `DataScienceTutorialOperator`; si borras/rehaces endpoints, añade `DataScienceTutorialCleanup` |
| `05-cicd-github-actions` | `DataScienceTutorialBootstrap` para el bootstrap humano one-time del provider OIDC y del rol; la policy del runner se converge con `scripts/ensure_github_actions_role.py` |
| `06-observability-operations` | `DataScienceTutorialOperator` |
| `07-cost-governance` | `DataScienceTutorialOperator` para inventario; `DataScienceTutorialCleanup` para stop/delete/reset |

## Politica de remocion

Cada policy debe poder quitarse sin romper otras capacidades:

| Policy | Cuando adjuntarla | Cuando removerla |
| --- | --- | --- |
| `DataScienceTutorialBootstrap` | Fase 00 o bootstrap humano de CI | En cuanto termine el bootstrap durable |
| `DataScienceTutorialOperator` | Fases 01-06 y revisiones operativas | Cuando el usuario ya no vaya a operar el tutorial |
| `DataScienceTutorialCleanup` | Solo para cleanup o reset explicito | En cuanto termine la limpieza |

Validacion de independencia:

- Quitar `Bootstrap` no elimina operacion normal de SageMaker/S3 del tutorial.
- Quitar `Cleanup` no elimina lectura, entrenamiento, pipeline ni serving.
- Quitar `Cleanup` si elimina delete/reset porque `Operator` ya no tiene `s3:DeleteObject`.

## Alineacion con la cuenta actual

- AWS account: `939122281183`
- Region: `eu-west-1`
- Bucket: `titanic-data-bucket-939122281183-data-science-user`
- Pipeline role: `titanic-sagemaker-pipeline-dev`
- Execution role: `titanic-sagemaker-sagemaker-execution-dev`
- Model Package Group: `titanic-survival-xgboost`
- GitHub Actions role: `titanic-sagemaker-gha-deployer-dev`

## Aplicacion por AWS Console

### 1. Crear o actualizar las managed policies humanas

| Policy name | JSON source |
| --- | --- |
| `DataScienceTutorialBootstrap` | `docs/aws/policies/01-ds-tutorial-bootstrap.json` |
| `DataScienceTutorialOperator` | `docs/aws/policies/02-ds-tutorial-operator.json` |
| `DataScienceTutorialCleanup` | `docs/aws/policies/03-ds-tutorial-cleanup.json` |

Para cada policy:

1. Ve a `IAM -> Policies`.
2. Si no existe:
   - `Create policy`
   - pega el JSON del archivo
   - usa exactamente el nombre de la tabla
3. Si ya existe:
   - abre `Policy versions`
   - crea una nueva version
   - marca `Set as default`
   - si llegaste al limite de 5 versiones, elimina antes una no-default

### 2. Adjuntar policies al usuario

Baseline operativo:

- `DataScienceTutorialOperator`

Adjunta temporalmente solo cuando haga falta:

- `DataScienceTutorialBootstrap`
- `DataScienceTutorialCleanup`

### 3. Validar por consola y CLI

1. En `IAM -> Users -> data-science-user -> Permissions`, confirma que `Operator` es la unica
   policy permanente del tutorial y que `Bootstrap`/`Cleanup` aparecen solo en sus ventanas
   de uso.
2. Simula acciones por capability:
   - `s3:CreateBucket` con `DataScienceTutorialBootstrap`
   - `sagemaker:CreateTrainingJob` con `DataScienceTutorialOperator`
   - `sagemaker:StartPipelineExecution` con `DataScienceTutorialOperator`
   - `sagemaker:UpdateModelPackage` con `DataScienceTutorialOperator`
   - `sagemaker:DeleteEndpoint` con `DataScienceTutorialCleanup`
   - `s3:DeleteObject` con `DataScienceTutorialCleanup`
3. Valida perfil local:
   - `aws sts get-caller-identity --profile data-science-user`
   - `aws configure list --profile data-science-user`

## GitHub Actions role

El rol OIDC del runner no se gestiona con JSON estaticos en este directorio.

Uso esperado:

1. crear una sola vez el provider OIDC `token.actions.githubusercontent.com`
2. converger el rol `titanic-sagemaker-gha-deployer-dev`
3. dejar que GitHub Actions asuma ese rol via OIDC

Fuente de verdad actual:

- `scripts/ensure_github_actions_role.py`
- `config/project-manifest.json`

Para el bootstrap humano de esta parte, `data-science-user` necesita
`DataScienceTutorialBootstrap`.

## Validation

Comprobaciones locales recomendadas:

```bash
python3 -m json.tool docs/aws/policies/01-ds-tutorial-bootstrap.json >/dev/null
python3 -m json.tool docs/aws/policies/02-ds-tutorial-operator.json >/dev/null
python3 -m json.tool docs/aws/policies/03-ds-tutorial-cleanup.json >/dev/null
PYTHONPYCACHEPREFIX=/tmp/pycache python3 -m py_compile scripts/ensure_github_actions_role.py
```

## Docs to update

Cuando cambie este contrato, actualizar:

- `docs/aws/policies/README.md`
- `docs/tutorials/00-foundations.md`
- `docs/tutorials/05-cicd-github-actions.md`
- `docs/tutorials/07-cost-governance.md`
- `docs/iterations/ITER-YYYYMMDD-XX.md`
