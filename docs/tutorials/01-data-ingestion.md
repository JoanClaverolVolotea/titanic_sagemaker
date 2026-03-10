# 01 Data Ingestion

## Objetivo y contexto

Descargar el dataset Titanic dentro del workspace del tutorial, crear splits reproducibles y
subir `raw/` y `curated/` al bucket del proyecto.

## Resultado minimo esperado

1. `titanic.csv` descargado en local.
2. `train.csv` y `validation.csv` generados de forma determinista.
3. Objetos cargados en `s3://$DATA_BUCKET/raw/` y `s3://$DATA_BUCKET/curated/`.
4. Lectura programatica del bucket validada con `Session`.

## Prerequisitos concretos

1. Fase 00 completada.
2. Bundle IAM disponible para esta fase: `DataScienceTutorialOperator`.

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Crear el helper de splits

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/prepare_splits.py" <<'EOF'
#!/usr/bin/env python
from __future__ import annotations

import argparse
import csv
import random
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--train-output", required=True)
    parser.add_argument("--validation-output", required=True)
    parser.add_argument("--validation-ratio", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not 0.0 < args.validation_ratio < 1.0:
        raise ValueError("validation-ratio debe estar entre 0 y 1")

    input_path = Path(args.input)
    train_path = Path(args.train_output)
    validation_path = Path(args.validation_output)
    train_path.parent.mkdir(parents=True, exist_ok=True)
    validation_path.parent.mkdir(parents=True, exist_ok=True)

    with input_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        if not fieldnames or "Survived" not in fieldnames:
            raise ValueError("El CSV debe incluir la columna Survived")
        rows = list(reader)

    by_target: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_target.setdefault(row["Survived"], []).append(row)

    rng = random.Random(args.seed)
    train_rows: list[dict[str, str]] = []
    validation_rows: list[dict[str, str]] = []

    for target_rows in by_target.values():
        shuffled = list(target_rows)
        rng.shuffle(shuffled)
        validation_count = max(1, int(round(len(shuffled) * args.validation_ratio)))
        validation_rows.extend(shuffled[:validation_count])
        train_rows.extend(shuffled[validation_count:])

    rng.shuffle(train_rows)
    rng.shuffle(validation_rows)

    with train_path.open("w", newline="", encoding="utf-8") as f_train:
        writer = csv.DictWriter(f_train, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(train_rows)

    with validation_path.open("w", newline="", encoding="utf-8") as f_validation:
        writer = csv.DictWriter(f_validation, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(validation_rows)

    print(
        f"created train={len(train_rows)} validation={len(validation_rows)} total={len(rows)}"
    )


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/prepare_splits.py"
```

### 2. Descargar el dataset Titanic

```bash
uv run python - <<'PY'
from pathlib import Path

import pandas as pd

url = "https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv"
target = Path.home() / "titanic-sagemaker-tutorial" / "data" / "raw" / "titanic.csv"
target.parent.mkdir(parents=True, exist_ok=True)
df = pd.read_csv(url)
df.to_csv(target, index=False)
print(f"downloaded_rows={len(df)} target={target}")
PY
```

### 3. Generar train y validation

```bash
uv run python "$TUTORIAL_ROOT/mlops_assets/prepare_splits.py" \
  --input "$TUTORIAL_ROOT/data/raw/titanic.csv" \
  --train-output "$TUTORIAL_ROOT/data/splits/train.csv" \
  --validation-output "$TUTORIAL_ROOT/data/splits/validation.csv"

wc -l \
  "$TUTORIAL_ROOT/data/raw/titanic.csv" \
  "$TUTORIAL_ROOT/data/splits/train.csv" \
  "$TUTORIAL_ROOT/data/splits/validation.csv"
```

### 4. Subir raw y curated a S3

```bash
aws s3 cp "$TUTORIAL_ROOT/data/raw/titanic.csv" \
  "s3://$DATA_BUCKET/raw/titanic.csv" \
  --profile "$AWS_PROFILE"

aws s3 cp "$TUTORIAL_ROOT/data/splits/train.csv" \
  "s3://$DATA_BUCKET/curated/train.csv" \
  --profile "$AWS_PROFILE"

aws s3 cp "$TUTORIAL_ROOT/data/splits/validation.csv" \
  "s3://$DATA_BUCKET/curated/validation.csv" \
  --profile "$AWS_PROFILE"
```

### 5. Verificar acceso programatico

```bash
uv run python - <<'PY'
import os

import boto3
from sagemaker.core.helper.session_helper import Session

boto_session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
session = Session(boto_session=boto_session)
s3_resource = boto_session.resource("s3")

print(f"region={session.boto_region_name}")
bucket = s3_resource.Bucket(os.environ["DATA_BUCKET"])
for prefix in ["raw/", "curated/"]:
    print(f"[{prefix}]")
    for obj in bucket.objects.filter(Prefix=prefix):
        print(f"  {obj.key} {obj.size}")
PY
```

### 6. Confirmar las rutas del tutorial

```bash
aws s3 ls "s3://$DATA_BUCKET/raw/" --profile "$AWS_PROFILE"
aws s3 ls "s3://$DATA_BUCKET/curated/" --profile "$AWS_PROFILE"
```

Rutas canonicas:

- `s3://$DATA_BUCKET/raw/titanic.csv`
- `s3://$DATA_BUCKET/curated/train.csv`
- `s3://$DATA_BUCKET/curated/validation.csv`

## IAM usado

- `DataScienceTutorialOperator` para subir datos y listarlos.

## Evidencia requerida

1. Salida de la descarga.
2. Salida de `wc -l`.
3. Salida de `aws s3 ls` en `raw/` y `curated/`.

## Criterio de cierre

- Dataset descargado localmente.
- Splits generados y trazables.
- `raw/` y `curated/` disponibles en S3.

## Riesgos/pendientes

- Si cambias la URL o el CSV fuente, cambia tambien la evidencia del resto del roadmap.
- Si subes archivos fuera de `raw/` y `curated/`, rompes el contrato del tutorial.

## Proximo paso

Continuar con [`02-training-validation.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/02-training-validation.md).
