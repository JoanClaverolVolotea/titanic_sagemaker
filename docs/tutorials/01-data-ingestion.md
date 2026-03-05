# 01 Data Ingestion

## Objetivo y contexto
Implementar carga y versionado de datos Titanic en S3, con separacion de raw, curated y
artefactos. Al terminar esta fase, los datos estan listos para consumo directo por SageMaker
en las fases 02 (training manual) y 03 (pipeline automatizado).

## Resultado minimo esperado
1. Dataset fuente `titanic.csv` cargado en `raw/`.
2. Splits `train.csv` y `validation.csv` cargados en `curated/`.
3. Rutas S3 listas para consumo de SageMaker en fase 02/03.
4. Evidencia de conteos y lectura de objetos en S3.
5. Validacion programatica de acceso a datos con SageMaker SDK V3 `Session`.

## Fuentes oficiales usadas en esta fase
1. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html`
2. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-prefixes.html`
3. `https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html`
4. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html`
5. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingServerSideEncryption.html`
6. SageMaker V3 Session: `vendor/sagemaker-python-sdk/docs/sagemaker_core/index.rst`

## Prerequisitos concretos
1. Fase 00 completada:
   - SageMaker SDK V3 instalado y verificado.
   - Terraform `00_foundations` aplicado (bucket de datos creado).
   - Perfil AWS CLI `data-science-user` operativo.
2. Bucket de datos disponible como output de fase 00:
   ```bash
   terraform -chdir=terraform/00_foundations output -raw data_bucket_name
   ```
3. Ejecutar este tutorial desde la raiz del repositorio.

## Paso a paso (ejecucion)

### 1. Definir bucket de trabajo desde output de fase 00

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)
echo "DATA_BUCKET=$DATA_BUCKET"
```

Validar que `DATA_BUCKET` no este vacio.

### 2. Preparar rutas locales de datos

El repositorio ya incluye las rutas esperadas:
- `data/titanic/raw/` -- dataset fuente
- `data/titanic/splits/` -- splits train/validation

### 3. Descargar dataset fuente Titanic

```bash
curl -fsSL https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv \
  -o data/titanic/raw/titanic.csv
```

### 4. Generar split reproducible train/validation

```bash
python3 scripts/prepare_titanic_splits.py
```

Este script genera `data/titanic/splits/train.csv` y `data/titanic/splits/validation.csv`
con un split determinista.

### 5. Validar conteos de filas

```bash
wc -l data/titanic/raw/titanic.csv data/titanic/splits/train.csv data/titanic/splits/validation.csv
```

Resultado esperado: 891 raw (+ header), ~713 train, ~178 validation.

### 6. Subir datos a S3

```bash
aws s3 cp data/titanic/raw/titanic.csv \
  s3://$DATA_BUCKET/raw/titanic.csv \
  --profile $AWS_PROFILE

aws s3 cp data/titanic/splits/train.csv \
  s3://$DATA_BUCKET/curated/train.csv \
  --profile $AWS_PROFILE

aws s3 cp data/titanic/splits/validation.csv \
  s3://$DATA_BUCKET/curated/validation.csv \
  --profile $AWS_PROFILE
```

### 7. Verificar lectura de objetos en S3

```bash
aws s3 ls s3://$DATA_BUCKET/raw/ --profile $AWS_PROFILE
aws s3 ls s3://$DATA_BUCKET/curated/ --profile $AWS_PROFILE
```

Resultado esperado: `titanic.csv` en `raw/`, `train.csv` y `validation.csv` en `curated/`.

### 8. Validar acceso programatico con SageMaker V3 Session

Verificar que el SDK puede acceder a los datos cargados. Este patron se reutiliza en fases
posteriores para bootstrap de sesion:

```python
import boto3
from sagemaker.core.helper.session_helper import Session

AWS_PROFILE = "data-science-user"
AWS_REGION = "eu-west-1"

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
session = Session(boto_session=boto_session)

# Verificar region y cuenta
print(f"Region: {session.boto_region_name}")
print(f"Account: {session.account_id()}")

# Verificar acceso al bucket
s3 = boto_session.client("s3")
DATA_BUCKET = "<valor-de-terraform-output>"  # Reemplazar con el valor real

for prefix in ["raw/", "curated/"]:
    resp = s3.list_objects_v2(Bucket=DATA_BUCKET, Prefix=prefix, MaxKeys=10)
    for obj in resp.get("Contents", []):
        print(f"  {obj['Key']} ({obj['Size']} bytes)")
```

Referencia V3: `vendor/sagemaker-python-sdk/docs/sagemaker_core/index.rst`

### 9. Verificar que el bucket corresponde a fase 00

```bash
echo "$DATA_BUCKET"
```

Debe contener un nombre de bucket valido y no vacio, derivado del output de Terraform.

## Archivos de datos del proyecto (fuente de verdad local)
- `data/titanic/raw/titanic.csv` -- dataset fuente completo
- `data/titanic/splits/train.csv` -- split de entrenamiento
- `data/titanic/splits/validation.csv` -- split de validacion

## Decisiones tecnicas y alternativas descartadas
- Estructura S3 por entorno (`dev`/`prod`) via prefijo o bucket separado.
- El bucket operativo se consume desde output de fase 00 (no hardcode en scripts).
- Convencion de paths: `raw/` para fuentes, `curated/` para datos procesados listos para ML.
- Datos base del proyecto versionados en git (archivos CSV pequenos).
- Alternativas descartadas: datasets sin versionado, buckets con nombres hardcodeados.

## IAM usado (roles/policies/permisos clave)
- Operador humano: `data-science-user`.
- Permisos S3 acotados por bucket/prefix (politica `04-ds-s3-data-access.json`).
- Acceso de lectura para entrenamiento y escritura para outputs.
- Keys logicas: `data-science-user-primary` / `data-science-user-rotation`.

## Criterio de cierre
- `train.csv` y `validation.csv` generados localmente de forma deterministica.
- Dataset fuente y splits cargados en `s3://$DATA_BUCKET`.
- Prefijos de datos listos para los jobs de processing/training/evaluation.
- Acceso programatico verificado con SageMaker V3 `Session`.

## Evidencia
Agregar:
- Conteo de filas final de raw/train/validation.
- Rutas S3 finales (`raw/`, `curated/`).
- Prueba de lectura/escritura por perfil.
- Output del paso 8 (validacion con Session V3).

## Riesgos/pendientes
- Politicas demasiado amplias en S3.
- Falta de cifrado o lifecycle policies.
- Datos de validacion no deben usarse durante preprocesamiento para evitar data leakage.

## Proximo paso
Configurar entrenamiento y validacion en `docs/tutorials/02-training-validation.md`.
