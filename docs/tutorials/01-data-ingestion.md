# 01 Data Ingestion

## Objetivo y contexto
Subir a S3 el dataset Titanic que ya existe dentro del repositorio y validar el acceso al
bucket con la sesion V3 de SageMaker.

Esta fase no descarga datos externos. La fuente de verdad del tutorial es el dataset local del
repositorio y los scripts locales de preparacion.

## Resultado minimo esperado
1. `data/titanic/raw/titanic.csv` verificado localmente.
2. `data/titanic/splits/train.csv` y `validation.csv` disponibles localmente.
3. Objetos cargados en `raw/` y `curated/` del bucket del proyecto.
4. Lectura programatica del bucket validada con `Session` + `boto3`.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/installation.rst`
2. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
3. `vendor/sagemaker-python-sdk/docs/sagemaker_core/index.rst`
4. `vendor/sagemaker-python-sdk/v3-examples/sagemaker_v3_setup.ipynb`

## Archivos locales usados en esta fase
- `data/titanic/raw/titanic.csv`
- `data/titanic/splits/train.csv`
- `data/titanic/splits/validation.csv`
- `scripts/prepare_titanic_splits.py`

## Prerequisitos concretos
1. Fase 00 completada.
2. `config/project-manifest.json` presente y `scripts/ensure_project_bootstrap.py --check`
   exitoso.
3. Perfil AWS CLI `data-science-user` operativo.
4. Ejecutar este tutorial desde la raiz del repositorio.

## Paso a paso (ejecucion)

### 1. Resolver el bucket operativo

```bash
eval "$(python3 scripts/resolve_project_env.py --emit-exports)"
python3 scripts/ensure_project_bootstrap.py --check
echo "DATA_BUCKET=$DATA_BUCKET"
```

### 2. Verificar los archivos locales del dataset

```bash
ls -l \
  data/titanic/raw/titanic.csv \
  data/titanic/splits/train.csv \
  data/titanic/splits/validation.csv
```

### 3. Regenerar splits solo si necesitas rehacer la evidencia

```bash
python3 scripts/prepare_titanic_splits.py
wc -l data/titanic/raw/titanic.csv data/titanic/splits/train.csv data/titanic/splits/validation.csv
```

### 4. Subir raw y curated a S3

```bash
aws s3 cp data/titanic/raw/titanic.csv \
  s3://$DATA_BUCKET/raw/titanic.csv \
  --profile "$AWS_PROFILE"

aws s3 cp data/titanic/splits/train.csv \
  s3://$DATA_BUCKET/curated/train.csv \
  --profile "$AWS_PROFILE"

aws s3 cp data/titanic/splits/validation.csv \
  s3://$DATA_BUCKET/curated/validation.csv \
  --profile "$AWS_PROFILE"
```

### 5. Validar acceso programatico con `Session`

```python
import os

import boto3
from sagemaker.core.helper.session_helper import Session

AWS_PROFILE = "data-science-user"
AWS_REGION = "eu-west-1"
DATA_BUCKET = os.environ["DATA_BUCKET"]

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
session = Session(boto_session=boto_session)
s3_resource = boto_session.resource("s3")

print(f"Region: {session.boto_region_name}")
try:
    print(f"SageMaker default bucket: {session.default_bucket()}")
except Exception as exc:
    print(f"SageMaker default bucket no disponible con el IAM actual: {exc}")

bucket = s3_resource.Bucket(DATA_BUCKET)
for prefix in ["raw/", "curated/"]:
    print(f"[{prefix}]")
    for obj in bucket.objects.filter(Prefix=prefix):
        print(f"  {obj.key} ({obj.size} bytes)")
```

### 6. Verificar las rutas que consumen las fases 02 y 03

```bash
aws s3 ls s3://$DATA_BUCKET/raw/ --profile "$AWS_PROFILE"
aws s3 ls s3://$DATA_BUCKET/curated/ --profile "$AWS_PROFILE"
```

Rutas canonicas del roadmap:
- `s3://$DATA_BUCKET/raw/titanic.csv`
- `s3://$DATA_BUCKET/curated/train.csv`
- `s3://$DATA_BUCKET/curated/validation.csv`

## Decisiones tecnicas y alternativas descartadas
- La fuente de verdad del tutorial es el dataset local del repositorio, no una descarga externa.
- `Session` se usa como bootstrap V3 para validar credenciales, region y bucket por defecto.
- Los datos para training y pipeline se consumen desde `curated/`.
- Se evita hardcodear bucket names dentro de los scripts del roadmap.

## IAM usado (roles/policies/permisos clave)
- Identidad base: `data-science-user`.
- Policy minima para esta fase: `DataScienceTutorialOperator`.
- Si el mismo operador tambien crea o reconfigura el bucket con
  `scripts/ensure_project_bootstrap.py`, añade `DataScienceTutorialBootstrap`.

## Evidencia
Agregar:
- Salida de `wc -l`.
- Salida de `aws s3 ls` sobre `raw/` y `curated/`.
- Salida del snippet con `Session` y listado de objetos.

## Criterio de cierre
- El dataset local y sus splits existen dentro del repositorio.
- `raw/` y `curated/` estan cargados en el bucket operativo.
- `Session` valida el acceso y el bucket puede leerse programaticamente.

## Riesgos/pendientes
- Subir datos distintos a los versionados en el repo rompe la trazabilidad del roadmap.
- Usar prefijos distintos de `raw/` y `curated/` rompe el contrato de las fases 02 y 03.

## Proximo paso
Entrenar un baseline manual con `ModelTrainer` en `docs/tutorials/02-training-validation.md`.
