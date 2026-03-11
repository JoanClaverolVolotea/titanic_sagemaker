# IAM policies for tutorial operators

Este directorio contiene solo las managed policies humanas necesarias para ejecutar
`docs/tutorials/00-07`.

Esta guia no crea el usuario IAM `data-science-user`. Ese usuario debe existir previamente y
su ciclo de vida lo gestiona el equipo de DevOps o la identidad administrativa equivalente.

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
| `DataScienceTutorialBootstrap` | Fase 00 o bootstrap humano de CI | En cuanto termine la validacion o convergencia necesaria |
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

## Aplicacion por AWS CLI

Esta es la ruta canonica para DevOps o para cualquier identidad con permisos IAM
administrativos equivalentes.

Ejecuta estos comandos desde la raiz del repo `titanic_sagemaker`, porque las rutas
`docs/aws/policies/*.json` se resuelven relativas a ese directorio.

Prerequisitos de esta guia:

1. El usuario `data-science-user` ya existe.
2. El caller que ejecuta estos comandos tiene permisos IAM para crear managed policies,
   crear nuevas versiones, adjuntarlas y retirarlas del usuario objetivo.
3. La creacion del usuario IAM no se documenta en este repo porque no forma parte del flujo del
   tutorial.

### 1. Preparar variables y validar contexto

```bash
export IAM_ADMIN_PROFILE=<perfil-admin>
export TARGET_USER=data-science-user
export ACCOUNT_ID=939122281183

aws --profile "$IAM_ADMIN_PROFILE" iam get-user --user-name "$TARGET_USER"

python3 -m json.tool docs/aws/policies/01-ds-tutorial-bootstrap.json >/dev/null
python3 -m json.tool docs/aws/policies/02-ds-tutorial-operator.json >/dev/null
python3 -m json.tool docs/aws/policies/03-ds-tutorial-cleanup.json >/dev/null
```

### 2. Crear o actualizar las managed policies

```bash
for spec in \
  "DataScienceTutorialBootstrap docs/aws/policies/01-ds-tutorial-bootstrap.json" \
  "DataScienceTutorialOperator docs/aws/policies/02-ds-tutorial-operator.json" \
  "DataScienceTutorialCleanup docs/aws/policies/03-ds-tutorial-cleanup.json"
do
  policy_name="${spec%% *}"
  policy_file="${spec#* }"
  policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"

  if aws --profile "$IAM_ADMIN_PROFILE" iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
    version_count="$(aws --profile "$IAM_ADMIN_PROFILE" iam list-policy-versions \
      --policy-arn "$policy_arn" \
      --query 'length(Versions)' \
      --output text)"

    if [ "$version_count" -ge 5 ]; then
      oldest_non_default="$(aws --profile "$IAM_ADMIN_PROFILE" iam list-policy-versions \
        --policy-arn "$policy_arn" \
        --query 'sort_by(Versions[?IsDefaultVersion==`false`], &CreateDate)[0].VersionId' \
        --output text)"

      aws --profile "$IAM_ADMIN_PROFILE" iam delete-policy-version \
        --policy-arn "$policy_arn" \
        --version-id "$oldest_non_default"
    fi

    aws --profile "$IAM_ADMIN_PROFILE" iam create-policy-version \
      --policy-arn "$policy_arn" \
      --policy-document "file://${policy_file}" \
      --set-as-default
  else
    aws --profile "$IAM_ADMIN_PROFILE" iam create-policy \
      --policy-name "$policy_name" \
      --policy-document "file://${policy_file}"
  fi
done
```

### 3. Adjuntar la policy baseline al usuario

```bash
aws --profile "$IAM_ADMIN_PROFILE" iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/DataScienceTutorialOperator"
```

### 4. Adjuntar temporalmente `Bootstrap` o `Cleanup` cuando haga falta

```bash
aws --profile "$IAM_ADMIN_PROFILE" iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/DataScienceTutorialBootstrap"

aws --profile "$IAM_ADMIN_PROFILE" iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/DataScienceTutorialCleanup"
```

### 5. Retirar `Bootstrap` o `Cleanup` al terminar

```bash
aws --profile "$IAM_ADMIN_PROFILE" iam detach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/DataScienceTutorialBootstrap"

aws --profile "$IAM_ADMIN_PROFILE" iam detach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/DataScienceTutorialCleanup"
```

### 6. Validar attachments finales

```bash
aws --profile "$IAM_ADMIN_PROFILE" iam list-attached-user-policies \
  --user-name "$TARGET_USER" \
  --query 'AttachedPolicies[].PolicyName' \
  --output table
```

Baseline esperado:

- `DataScienceTutorialOperator`

Adjuntos temporales solo durante sus ventanas de uso:

- `DataScienceTutorialBootstrap`
- `DataScienceTutorialCleanup`

## Aplicacion por AWS Console

Usa esta seccion solo si necesitas una alternativa manual al flujo CLI canonico.

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
