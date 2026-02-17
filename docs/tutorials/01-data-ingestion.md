# 01 Data Ingestion

## Objetivo y contexto
Implementar carga y versionado de datos Titanic en S3, con separacion de raw, curated y artefactos.

## Paso a paso (ejecucion)
1. Definir bucket de trabajo para tutoriales:
   - `export DATA_BUCKET=titanic-data-bucket-939122281183-data-science-use`
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

## Decisiones tecnicas y alternativas descartadas
- Estructura S3 por entorno (`dev`/`prod`).
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
- Definir bucket de trabajo:
  - `export DATA_BUCKET=titanic-data-bucket-939122281183-data-science-use`
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
