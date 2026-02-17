# 01 Data Ingestion

## Objetivo y contexto
Implementar carga y versionado de datos Titanic en S3, con separacion de raw, curated y artefactos.

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
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfiles `data-science-user-dev` (dev) o `data-science-user-prod` (prod).
- Descargar dataset Titanic:
  - `curl -fsSL https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv -o data/titanic/raw/titanic.csv`
- Generar split reproducible:
  - `python3 scripts/prepare_titanic_splits.py`
- Validar volumen de datos:
  - `wc -l data/titanic/raw/titanic.csv data/titanic/splits/train.csv data/titanic/splits/validation.csv`
- Subir a S3 (dev):
  - `aws s3 cp data/titanic/raw/titanic.csv s3://<titanic-data-bucket-dev>/raw/titanic.csv --profile data-science-user-dev`
  - `aws s3 cp data/titanic/splits/train.csv s3://<titanic-data-bucket-dev>/curated/train.csv --profile data-science-user-dev`
  - `aws s3 cp data/titanic/splits/validation.csv s3://<titanic-data-bucket-dev>/curated/validation.csv --profile data-science-user-dev`
- Resultado esperado: datos raw y splits versionados en S3 para alimentar Processing/Training/Evaluation.

## Evidencia
Agregar:
- Conteo de filas final de raw/train/validation.
- Rutas S3 finales (`raw/`, `curated/`).
- Prueba de lectura/escritura por rol.

## Riesgos/pendientes
- Politicas demasiado amplias en S3.
- Falta de cifrado o lifecycle policies.

## Proximo paso
Configurar entrenamiento y validacion en `docs/tutorials/02-training-validation.md`.
