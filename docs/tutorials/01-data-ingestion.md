# 01 Data Ingestion

## Objetivo y contexto
Implementar carga y versionado de datos Titanic en S3, con separacion de raw, curated y artefactos.

## Resultado minimo esperado
1. Dataset fuente `titanic.csv` cargado en `raw/`.
2. Splits `train.csv` y `validation.csv` cargados en `curated/`.
3. Rutas S3 listas para consumo de SageMaker en fase 02/03.
4. Evidencia de conteos y lectura de objetos en S3.

## Fuentes oficiales (AWS/S3) usadas en esta fase
1. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html`
2. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-prefixes.html`
3. `https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html`
4. `https://docs.aws.amazon.com/cli/latest/reference/s3/ls.html`
5. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html`
6. `https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingServerSideEncryption.html`
7. Referencia local de estudio: `docs/aws/sagemaker-dg.pdf`.

## Prerequisitos concretos
1. Fase 00 aplicada con Terraform en `terraform/00_foundations`.
2. Bucket de datos disponible como output de fase 00:
   - `terraform -chdir=terraform/00_foundations output -raw data_bucket_name`
3. Perfil AWS CLI operativo: `data-science-user`.
4. Ejecutar este tutorial desde la raiz del repositorio para resolver rutas y comandos Terraform correctamente.

## Paso a paso (ejecucion)
1. Definir bucket de trabajo desde output de fase 00:
   - `export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)`
2. Preparar rutas locales de datos:
   - `data/titanic/raw/`
   - `data/titanic/splits/`
3. Descargar dataset fuente Titanic:
   - `curl -fsSL https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv -o data/titanic/raw/titanic.csv`
4. Generar split reproducible train/validation:
   - `python3 scripts/prepare_titanic_splits.py`
5. Validar conteos de filas:
   - `wc -l data/titanic/raw/titanic.csv data/titanic/splits/train.csv data/titanic/splits/validation.csv`
6. Subir datos a S3:
   - `aws s3 cp data/titanic/raw/titanic.csv s3://$DATA_BUCKET/raw/titanic.csv --profile data-science-user`
   - `aws s3 cp data/titanic/splits/train.csv s3://$DATA_BUCKET/curated/train.csv --profile data-science-user`
   - `aws s3 cp data/titanic/splits/validation.csv s3://$DATA_BUCKET/curated/validation.csv --profile data-science-user`
7. Verificar lectura de objetos en S3 por prefijo `raw/` y `curated/`.
8. Verificar que el bucket usado corresponde a fase 00 y no esta hardcodeado:
   - `echo "$DATA_BUCKET"` debe contener un nombre de bucket valido y no vacio.

## Decisiones tecnicas y alternativas descartadas
- Estructura S3 por entorno (`dev`/`prod`).
- El bucket operativo de tutorial se consume desde output de fase 00 (no hardcode en scripts).
- Convencion de paths para train/validation.
- Datos base del proyecto:
  - `data/titanic/raw/titanic.csv`
  - `data/titanic/splits/train.csv`
  - `data/titanic/splits/validation.csv`
- Alternativas descartadas: datasets sin versionado.

## IAM usado (roles/policies/permisos clave)
- Permisos S3 acotados por bucket/prefix.
- Acceso de lectura para entrenamiento y escritura para outputs.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- Definir bucket de trabajo desde Terraform foundations:
  - `export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)`
- Descargar dataset Titanic:
  - `curl -fsSL https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv -o data/titanic/raw/titanic.csv`
- Generar split reproducible:
  - `python3 scripts/prepare_titanic_splits.py`
- Validar volumen de datos:
  - `wc -l data/titanic/raw/titanic.csv data/titanic/splits/train.csv data/titanic/splits/validation.csv`
- Subir a S3:
  - `aws s3 cp data/titanic/raw/titanic.csv s3://$DATA_BUCKET/raw/titanic.csv --profile data-science-user`
  - `aws s3 cp data/titanic/splits/train.csv s3://$DATA_BUCKET/curated/train.csv --profile data-science-user`
  - `aws s3 cp data/titanic/splits/validation.csv s3://$DATA_BUCKET/curated/validation.csv --profile data-science-user`
- Resultado esperado: datos raw y splits versionados en S3 para alimentar Processing/Training/Evaluation.

## Evidencia
Agregar:
- Conteo de filas final de raw/train/validation.
- Rutas S3 finales (`raw/`, `curated/`).
- Prueba de lectura/escritura por rol.

## Criterio de cierre
- `train.csv` y `validation.csv` generados localmente de forma deterministica.
- Dataset fuente y splits cargados en `s3://$DATA_BUCKET`.
- Prefijos de datos listos para los jobs de processing/training/evaluation.

## Riesgos/pendientes
- Politicas demasiado amplias en S3.
- Falta de cifrado o lifecycle policies.

## Proximo paso
Configurar entrenamiento y validacion en `docs/tutorials/02-training-validation.md`.
