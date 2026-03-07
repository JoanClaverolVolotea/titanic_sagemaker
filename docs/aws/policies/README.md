# IAM policies for tutorial operators

Este directorio contiene dos tipos de artefactos IAM para ejecutar `docs/tutorials/`:

- politicas administradas para el usuario operador `data-science-user`
- documentos de confianza/permisos para el rol de GitHub Actions de la fase 05

## Objetivo

Permitir que el proyecto pueda:

- ejecutar las fases 00-07 con la identidad humana `data-science-user`
- mantener `iam:PassRole` restringido a los roles reales del proyecto
- operar `training`, `pipeline`, `registry` y `serving` sin permisos admin
- documentar y bootstrapear el rol OIDC de GitHub Actions sin depender de access keys estaticas

## Archivos incluidos

### Politicas administradas del usuario `data-science-user`

- `01-ds-observability-readonly.json`: lectura operativa de SageMaker, CloudWatch, logs, tags y recursos auxiliares usados por los runbooks.
- `02-ds-assume-environment-roles.json`: `sts:AssumeRole` a roles de entorno documentados.
- `03-ds-passrole-restricted.json`: `iam:PassRole` restringido a roles del proyecto y servicios esperados.
- `04-ds-s3-data-access.json`: lectura/escritura sobre el bucket real del tutorial y sus prefijos `raw/`, `curated/`, `training/`, `evaluation/` y `pipeline/`.
- `05-ds-policy-administration.json`: bootstrap IAM para que `data-science-user` pueda crear/versionar/adjuntar las managed policies del propio tutorial.
- `06-ds-s3-tutorial-bucket-bootstrap.json`: permisos de bootstrap/configuracion del bucket de fase 00 convergido por script.
- `07-ds-sagemaker-training-job-lifecycle.json`: stop/delete de training jobs del proyecto.
- `08-ds-service-quotas-readonly.json`: lectura de Service Quotas para validaciones operativas.
- `09-ds-sagemaker-authoring-runtime.json`: acciones mutantes necesarias para fases 02-04 (`CreateTrainingJob`, `CreateProcessingJob`, `Create/UpdatePipeline`, `StartPipelineExecution`, `CreateModel`, `CreateEndpoint*`, `UpdateModelPackage`, `InvokeEndpoint`).
- `10-ds-sagemaker-cleanup-nonprod.json`: cleanup no-productivo de endpoints, endpoint configs, models, pipelines y Model Registry.

### Documentos de rol para GitHub Actions

- `11-gha-oidc-trust-policy.json`: trust policy para asumir el rol del workflow via OIDC de GitHub Actions.
- `12-gha-sagemaker-deployer-policy.json`: permisos del runner para ejecutar el contrato de `docs/tutorials/05-cicd-github-actions.md`.

## Mapa fase -> politicas requeridas

| Fase | Politicas minimas |
| --- | --- |
| `00-foundations` | `04`, `06` |
| `01-data-ingestion` | `04` |
| `02-training-validation` | `01`, `03`, `04`, `07`, `09` |
| `03-sagemaker-pipeline` | `01`, `03`, `04`, `09` |
| `04-serving-sagemaker` | `01`, `03`, `04`, `09` |
| `05-cicd-github-actions` | `11`, `12` para el runner; el humano solo necesita `01` para revisar evidencia |
| `06-observability-operations` | `01`; si rehaces el smoke test, tambien `09` por `InvokeEndpoint` |
| `07-cost-governance` | `01`, `04`, `07`, `08`, `10` |

## Alineacion con la infraestructura actual

El repo usa hoy:

- AWS Account ID: `939122281183`
- Region operativa: `eu-west-1`
- Bucket de tutorial: `titanic-data-bucket-939122281183-data-science-user`
- Role de pipeline esperado por el manifest: `titanic-sagemaker-pipeline-dev`
- Model Package Group esperado por el manifest: `titanic-survival-xgboost`
- Execution role esperado por el manifest: `titanic-sagemaker-sagemaker-execution-dev`

Si ejecutas estos documentos en otra cuenta o region:

- reemplaza el `Account ID` en los ARN
- ajusta la condicion `aws:RequestedRegion`
- ajusta nombres de bucket, pipeline role y Model Package Group a tu naming real

## Credenciales estandar del operador DS

Definicion oficial para este proyecto:

- IAM User: `data-science-user`
- Access key logica activa: `data-science-user-primary`
- Access key logica de rotacion: `data-science-user-rotation`
- Perfil AWS CLI oficial: `data-science-user`

Nota: AWS genera el `AccessKeyId` real automaticamente (`AKIA...`).
Los nombres `primary` y `rotation` son etiquetas operativas para documentacion y vault.

## Aplicar politicas del usuario por AWS Console

### 1) Confirmar cuenta y usuario

1. Inicia sesion en AWS Console con la cuenta `939122281183`.
2. Abre `IAM -> Users`.
3. Verifica que existe `data-science-user`.

### 2) Crear y registrar las access keys del usuario

1. Ve a `IAM -> Users -> data-science-user -> Security credentials`.
2. Crea una key para uso CLI y guardala en tu vault como `data-science-user-primary`.
3. Crea una segunda key para rotacion controlada y guardala como `data-science-user-rotation`.
4. Mantener maximo 2 keys activas.
5. Nunca guardar secretos en el repositorio.

### 3) Crear o actualizar las managed policies del usuario

| Policy name | JSON source |
| --- | --- |
| `DataScienceObservabilityReadOnly` | `docs/aws/policies/01-ds-observability-readonly.json` |
| `DataScienceAssumeEnvironmentRoles` | `docs/aws/policies/02-ds-assume-environment-roles.json` |
| `DataSciencePassroleRestricted` | `docs/aws/policies/03-ds-passrole-restricted.json` |
| `DataSciences3DataAccess` | `docs/aws/policies/04-ds-s3-data-access.json` |
| `DataSciencePolicyAdministration` | `docs/aws/policies/05-ds-policy-administration.json` |
| `DataScienceS3TutorialBucketBootstrap` | `docs/aws/policies/06-ds-s3-tutorial-bucket-bootstrap.json` |
| `DataScienceSageMakerTrainingJobLifecycle` | `docs/aws/policies/07-ds-sagemaker-training-job-lifecycle.json` |
| `DataScienceServiceQuotasReadOnly` | `docs/aws/policies/08-ds-service-quotas-readonly.json` |
| `DataScienceSageMakerAuthoringRuntime` | `docs/aws/policies/09-ds-sagemaker-authoring-runtime.json` |
| `DataScienceSageMakerCleanupNonProd` | `docs/aws/policies/10-ds-sagemaker-cleanup-nonprod.json` |

Para cada policy:

1. Ve a `IAM -> Policies`.
2. Si no existe:
   - `Create policy` -> pestaña `JSON`
   - pega el archivo JSON
   - `Next` -> usa exactamente el nombre de la tabla
3. Si ya existe:
   - abre la policy -> `Policy versions`
   - `Create policy version`
   - pega el JSON actualizado y marca `Set as default`
   - si llegaste al limite de 5 versiones, elimina antes una no-default

### 4) Adjuntar politicas al usuario `data-science-user`

Adjunta como base del operador del tutorial:

- `DataScienceObservabilityReadOnly`
- `DataSciencePassroleRestricted`
- `DataSciences3DataAccess`
- `DataScienceS3TutorialBucketBootstrap`
- `DataScienceSageMakerTrainingJobLifecycle`
- `DataScienceSageMakerAuthoringRuntime`
- `DataScienceSageMakerCleanupNonProd`
- `DataScienceServiceQuotasReadOnly`

Adjunta segun necesidad adicional:

- `DataScienceAssumeEnvironmentRoles`: si el operador humano debe asumir roles de entorno documentados.
- `DataSciencePolicyAdministration`: si vas a usar `scripts/ensure_ds_policies.sh`.

### 5) Configurar el perfil AWS CLI unico

```bash
aws configure --profile data-science-user
aws configure set region eu-west-1 --profile data-science-user
aws configure set output json --profile data-science-user
```

Resultado esperado:

```ini
# ~/.aws/credentials
[data-science-user]
aws_access_key_id = <ACCESS_KEY_ID_PRIMARY>
aws_secret_access_key = <SECRET_ACCESS_KEY_PRIMARY>
```

```ini
# ~/.aws/config
[profile data-science-user]
region = eu-west-1
output = json
```

### 6) Validar por consola y CLI

1. En `IAM -> Users -> data-science-user -> Permissions`, confirma que estan adjuntas las 8 policies operativas del tutorial, y `DataSciencePolicyAdministration` si vas a usar el script de ensure.
2. Abre `IAM Policy Simulator`.
3. Simula al menos estas acciones:
   - `iam:PassRole`
   - `s3:PutObject`
   - `sagemaker:CreateTrainingJob`
   - `sagemaker:StartPipelineExecution`
   - `sagemaker:UpdateModelPackage`
   - `sagemaker:DeleteEndpoint`
4. Usa contexto de simulacion con region `eu-west-1`.
5. Prueba perfil local:
   - `aws sts get-caller-identity --profile data-science-user`
   - `aws configure list --profile data-science-user`
6. Prueba quotas:
   - `aws service-quotas list-service-quotas --service-code sagemaker --profile data-science-user --region eu-west-1`

## GitHub Actions role (fase 05)

Estos dos archivos no se adjuntan al usuario `data-science-user`. Son insumos para un rol
dedicado del runner, que puede convergerse con `scripts/ensure_github_actions_role.py` si el
proveedor OIDC ya existe en IAM.

Sugerencia de rol:

- nombre: `titanic-sagemaker-github-actions-dev`
- trust policy: `docs/aws/policies/11-gha-oidc-trust-policy.json`
- permissions policy: `docs/aws/policies/12-gha-sagemaker-deployer-policy.json`

Reglas:

- usa OIDC; no uses access keys estaticas en GitHub
- limita el trust al repo `JoanClaverolVolotea/titanic_sagemaker`
- si usas GitHub Environments, conserva `dev` y `prod` en el `sub` del trust

## Alternativa automatizada para el usuario DS

```bash
# Desde la raiz del repo
AWS_PROFILE=data-science-user scripts/ensure_ds_policies.sh --apply

# Solo validacion
AWS_PROFILE=data-science-user scripts/ensure_ds_policies.sh --check
```

El script:

- valida cuenta, usuario y JSON locales
- crea o versiona las 9 managed policies del usuario
- adjunta las policies faltantes a `data-science-user`
- requiere que `DataSciencePolicyAdministration` ya este adjunta al usuario
- no crea ni actualiza los documentos `11` y `12` del rol de GitHub Actions

## Notas de seguridad

- `06-ds-s3-tutorial-bucket-bootstrap.json` usa `s3:Get*` sobre el ARN del bucket porque el
  bootstrap script necesita validar configuraciones `GetBucket...` antes de converger.
- `09-ds-sagemaker-authoring-runtime.json` y `12-gha-sagemaker-deployer-policy.json` usan `Resource: "*"` en parte de las acciones de create/start/update porque SageMaker no soporta de forma consistente restricciones por ARN en todos esos APIs; el alcance se reduce por region y por `iam:PassRole` separado.
- `03-ds-passrole-restricted.json` incluye los patrones reales `titanic-sagemaker-pipeline-*`
  y `titanic-sagemaker-sagemaker-execution-*` usados por el manifest y los scripts.
- El flujo recomendado sigue siendo separar identidad humana, role runtime de SageMaker y role OIDC de GitHub Actions.
