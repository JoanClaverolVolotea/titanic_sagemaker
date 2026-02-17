# IAM policies for tutorial operators

Este directorio contiene politicas IAM listas para crear y asignar al usuario que va a ejecutar los tutoriales en `docs/tutorials/`.

## Objetivo
Permitir que el usuario operador de Data Science pueda:
- Ver estado de recursos, logs, metricas y costos.
- Asumir roles de ejecucion por ambiente (`dev` y `prod`).
- Ejecutar operaciones que requieren `iam:PassRole` sin usar comodines globales.

## Politicas incluidas
- `01-ds-observability-readonly.json`: lectura operativa (SageMaker, Step Functions, CloudWatch, ECS, Lambda, S3, costos).
- `02-ds-assume-environment-roles.json`: `sts:AssumeRole` a roles de entorno.
- `03-ds-passrole-restricted.json`: `iam:PassRole` restringido a roles del proyecto y servicios esperados.
- `04-ds-s3-data-access.json`: acceso de lectura/escritura acotado a buckets de datos/artefactos del proyecto.

## Cuenta y region
Esta version ya usa:
- AWS Account ID: `939122281183`
- Region operativa: `eu-west-1`

Si ejecutas estos documentos en otra cuenta o region:
- Reemplaza el Account ID en los ARN.
- Ajusta la condicion `aws:RequestedRegion` en `01-ds-observability-readonly.json`.
- Si cambiaste nombres de roles o buckets, ajusta los ARN para tu naming real.

## Creacion de politicas (AWS CLI)
```bash
export AWS_REGION=eu-west-1
export AWS_DEFAULT_REGION=eu-west-1

aws iam create-policy \
  --policy-name titanic-ds-observability-readonly \
  --policy-document file://docs/aws/policies/01-ds-observability-readonly.json

aws iam create-policy \
  --policy-name titanic-ds-assume-environment-roles \
  --policy-document file://docs/aws/policies/02-ds-assume-environment-roles.json

aws iam create-policy \
  --policy-name titanic-ds-passrole-restricted \
  --policy-document file://docs/aws/policies/03-ds-passrole-restricted.json

aws iam create-policy \
  --policy-name titanic-ds-s3-data-access \
  --policy-document file://docs/aws/policies/04-ds-s3-data-access.json
```

## Asignacion a usuario
Adjunta las politicas al usuario operador (ejemplo `titanic-ds-operator`):
```bash
aws iam attach-user-policy --user-name titanic-ds-operator --policy-arn arn:aws:iam::939122281183:policy/titanic-ds-observability-readonly
aws iam attach-user-policy --user-name titanic-ds-operator --policy-arn arn:aws:iam::939122281183:policy/titanic-ds-assume-environment-roles
aws iam attach-user-policy --user-name titanic-ds-operator --policy-arn arn:aws:iam::939122281183:policy/titanic-ds-passrole-restricted
aws iam attach-user-policy --user-name titanic-ds-operator --policy-arn arn:aws:iam::939122281183:policy/titanic-ds-s3-data-access
```

## Validacion minima
```bash
aws sts get-caller-identity
aws iam list-attached-user-policies --user-name titanic-ds-operator
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::939122281183:user/titanic-ds-operator \
  --action-names sts:AssumeRole iam:PassRole cloudwatch:GetMetricData s3:PutObject \
  --context-entries ContextKeyName=aws:RequestedRegion,ContextKeyType=string,ContextKeyValues=eu-west-1
```

## Notas de seguridad
- El flujo recomendado es que el usuario humano asuma roles de workload/deploy en vez de operar todo con permisos directos.
- `iam:PassRole` esta acotado por nombre de rol y por `iam:PassedToService`.
- Operaciones regionales de observabilidad quedaron acotadas a `eu-west-1` via `aws:RequestedRegion`.
- Evitar `Action: "*"` y `Resource: "*"` para operaciones de escritura.
