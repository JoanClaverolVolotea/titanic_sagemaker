# IAM policies for tutorial operators

Este directorio contiene politicas IAM listas para crear y asignar al usuario que va a ejecutar los tutoriales en `docs/tutorials/`.

## Objetivo
Permitir que el usuario operador de Data Science pueda:
- Ver estado de recursos, logs, metricas y costos.
- Operar recursos de ambientes `dev` y `prod` con un perfil AWS unico.
- Ejecutar operaciones que requieren `iam:PassRole` sin usar comodines globales.

## Politicas incluidas
- `01-ds-observability-readonly.json`: lectura operativa (SageMaker, Step Functions, CloudWatch, ECS, Lambda, S3, costos).
- `02-ds-assume-environment-roles.json`: `sts:AssumeRole` a roles de entorno.
- `03-ds-passrole-restricted.json`: `iam:PassRole` restringido a roles del proyecto y servicios esperados.
- `04-ds-s3-data-access.json`: acceso de lectura/escritura acotado a buckets de datos/artefactos del proyecto.
- `05-ds-policy-administration.json`: permisos IAM bootstrap para que `data-science-user` pueda ejecutar el script de ensure (gestionar versions/attachments de policies).
- `06-ds-s3-tutorial-bucket-bootstrap.json`: permisos minimos para crear y operar el bucket de tutorial `titanic-data-bucket-939122281183-data-science-use`.

## Cuenta y region
Esta version ya usa:
- AWS Account ID: `939122281183`
- Region operativa: `eu-west-1`

Si ejecutas estos documentos en otra cuenta o region:
- Reemplaza el Account ID en los ARN.
- Ajusta la condicion `aws:RequestedRegion` en `01-ds-observability-readonly.json`.
- Si cambiaste nombres de roles o buckets, ajusta los ARN para tu naming real.

## Credenciales estandar del operador DS
Definicion oficial para este proyecto:
- IAM User: `data-science-user`
- Access key logica activa: `data-science-user-primary`
- Access key logica de rotacion: `data-science-user-rotation`
- Perfil AWS CLI oficial (unico): `data-science-user`

Nota: AWS genera el `AccessKeyId` real automaticamente (formato `AKIA...`).  
Los nombres `data-science-user-primary` y `data-science-user-rotation` son etiquetas operativas para documentacion y almacenamiento seguro.

## Aplicar politicas correctas por AWS Console (browser)
Usa este flujo en la consola web para crear/actualizar las politicas y asignarlas al usuario `data-science-user`.

### 1) Confirmar cuenta y usuario
1. Inicia sesion en AWS Console con la cuenta `939122281183`.
2. Abre `IAM` y ve a `Users`.
3. Verifica que existe el usuario `data-science-user`.

### 2) Crear y registrar las access keys del usuario
1. Ve a `IAM > Users > data-science-user > Security credentials`.
2. En `Access keys`, crea la primera key para uso CLI:
   - Use case: `Command Line Interface (CLI)`.
   - Guarda `Access key ID` y `Secret access key` en tu vault con etiqueta `data-science-user-primary`.
3. Crea una segunda key para rotacion controlada:
   - Misma ruta, `Create access key`.
   - Guarda valores en tu vault con etiqueta `data-science-user-rotation`.
4. Mantener maximo 2 keys:
   - `primary` activa para operacion diaria.
   - `rotation` activa solo durante ventana de rotacion o cuando reemplaces la primaria.
5. Nunca guardar secretos en el repositorio.

### 3) Crear o actualizar las politicas administradas
Politicas esperadas y archivo fuente:

| Policy name | JSON source |
| --- | --- |
| `DataScienceAssumeEnvironmentRoles` | `docs/aws/policies/02-ds-assume-environment-roles.json` |
| `DataScienceObservabilityReadOnly` | `docs/aws/policies/01-ds-observability-readonly.json` |
| `DataSciencePassroleRestricted` | `docs/aws/policies/03-ds-passrole-restricted.json` |
| `DataSciences3DataAccess` | `docs/aws/policies/04-ds-s3-data-access.json` |
| `DataSciencePolicyAdministration` | `docs/aws/policies/05-ds-policy-administration.json` |
| `DataScienceS3TutorialBucketBootstrap` | `docs/aws/policies/06-ds-s3-tutorial-bucket-bootstrap.json` |

Para cada politica:
1. Ve a `IAM > Policies`.
2. Si no existe:
   - `Create policy` -> pestaña `JSON`.
   - Pega el contenido del archivo JSON correspondiente.
   - `Next` -> Name: usa exactamente el `Policy name` de la tabla.
   - `Create policy`.
3. Si ya existe:
   - Abre la policy -> pestaña `Policy versions`.
   - `Create policy version` -> pega el JSON actualizado -> marca `Set as default`.
   - Si te aparece limite de 5 versiones, elimina primero una version antigua no-default y repite.

Nota: IAM es un servicio global, pero esta documentacion asume operacion en `eu-west-1` por la condicion `aws:RequestedRegion` incluida en observabilidad.

### 4) Adjuntar politicas al usuario `data-science-user`
1. Ve a `IAM > Users > data-science-user`.
2. `Add permissions`.
3. Selecciona `Attach policies directly`.
4. Busca y marca estas politicas base:
   - `DataScienceAssumeEnvironmentRoles`
   - `DataScienceObservabilityReadOnly`
   - `DataSciencePassroleRestricted`
   - `DataSciences3DataAccess`
   - `DataScienceS3TutorialBucketBootstrap` (requerida para crear/subir al bucket `titanic-data-bucket-939122281183-data-science-use`)
5. Si vas a usar `scripts/ensure_ds_policies.sh`, marca tambien:
   - `DataSciencePolicyAdministration`
6. `Next` -> `Add permissions`.

### 5) Configurar perfil AWS CLI unico con `aws configure`
Usa la key `data-science-user-primary` en el perfil `data-science-user`.

```bash
aws configure --profile data-science-user
aws configure set region eu-west-1 --profile data-science-user
aws configure set output json --profile data-science-user
```

Resultado esperado en archivos AWS:

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

### 6) Validar en la consola y por CLI
1. En `IAM > Users > data-science-user > Permissions`, confirma que estan adjuntas las 5 politicas operativas (incluyendo `DataScienceS3TutorialBucketBootstrap`).
2. Si usas el script de ensure, confirma tambien `DataSciencePolicyAdministration`.
3. Abre `IAM Policy Simulator`.
4. Selecciona el usuario `data-science-user`.
5. Simula al menos estas acciones:
   - `sts:AssumeRole`
   - `iam:PassRole`
   - `cloudwatch:GetMetricData`
   - `s3:PutObject`
6. Configura el contexto de simulacion con region `eu-west-1` para validar reglas con `aws:RequestedRegion`.
7. Prueba perfil local:
   - `aws sts get-caller-identity --profile data-science-user`
   - `aws configure list --profile data-science-user`

## Alternativa automatizada (script)
Si prefieres aplicar/verificar todo en un solo paso desde terminal:

```bash
# Desde la raiz del repo
AWS_PROFILE=data-science-user scripts/ensure_ds_policies.sh --apply

# Solo validacion (sin cambios en AWS)
AWS_PROFILE=data-science-user scripts/ensure_ds_policies.sh --check
```

El script:
- Verifica cuenta, usuario y JSON locales.
- Crea/actualiza las 5 policies operativas (versionado IAM).
- Adjunta policies base faltantes al usuario.
- Requiere que `DataSciencePolicyAdministration` ya este adjunta al usuario.
- Falla si no se ejecuta con perfil `data-science-user`.

## Notas de seguridad
- El flujo recomendado es que el usuario humano asuma roles de workload/deploy en vez de operar todo con permisos directos.
- `iam:PassRole` esta acotado por nombre de rol y por `iam:PassedToService`.
- Operaciones regionales de observabilidad quedaron acotadas a `eu-west-1` via `aws:RequestedRegion`.
- Evitar `Action: "*"` y `Resource: "*"` para operaciones de escritura.
