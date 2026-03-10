# 02 Training and Validation

## Objetivo y contexto

Entrenar un baseline manual con SageMaker SDK V3 usando `ModelTrainer`, descargar el modelo y
emitir `evaluation.json` y `promotion_decision.json` desde el mismo workspace del tutorial.

## Resultado minimo esperado

1. Training job exitoso.
2. Artefacto `model.tar.gz` descargado en local.
3. `evaluation.json` con `metrics.accuracy`, `precision`, `recall` y `f1`.
4. `promotion_decision.json` con la decision de promocion.

## Prerequisitos concretos

1. Fases 00 y 01 completadas.
2. Bundle IAM disponible para esta fase: `DataScienceTutorialOperator`.

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Crear el helper para XGBoost

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/prepare_xgb_inputs.py" <<'EOF'
#!/usr/bin/env python
from __future__ import annotations

import argparse
import csv
from pathlib import Path
from statistics import median


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-input", required=True)
    parser.add_argument("--validation-input", required=True)
    parser.add_argument("--train-output", required=True)
    parser.add_argument("--validation-output", required=True)
    return parser.parse_args()


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError(f"CSV vacio: {path}")
    return rows


def parse_float(value: str | None) -> float | None:
    if value is None or not value.strip():
        return None
    return float(value)


def to_int(value: str | None, default: int = 0) -> int:
    if value is None or not value.strip():
        return default
    return int(float(value))


def encode_features(row: dict[str, str], age_fill: float, fare_fill: float) -> list[float]:
    sex_map = {"male": 0.0, "female": 1.0}
    embarked_map = {"C": 0.0, "Q": 1.0, "S": 2.0}
    age = parse_float(row.get("Age"))
    fare = parse_float(row.get("Fare"))
    return [
        float(to_int(row.get("Pclass"), default=3)),
        sex_map.get((row.get("Sex") or "").strip().lower(), -1.0),
        age_fill if age is None else age,
        float(to_int(row.get("SibSp"), default=0)),
        float(to_int(row.get("Parch"), default=0)),
        fare_fill if fare is None else fare,
        embarked_map.get((row.get("Embarked") or "").strip().upper(), -1.0),
    ]


def label(row: dict[str, str]) -> int:
    return to_int(row.get("Survived"), default=0)


def write_rows(path: Path, rows: list[list[float | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    train_rows = read_rows(Path(args.train_input))
    validation_rows = read_rows(Path(args.validation_input))
    ages = [v for v in (parse_float(r.get("Age")) for r in train_rows) if v is not None]
    fares = [v for v in (parse_float(r.get("Fare")) for r in train_rows) if v is not None]
    age_fill = float(median(ages)) if ages else 0.0
    fare_fill = float(median(fares)) if fares else 0.0

    train_payload = [[label(r), *encode_features(r, age_fill, fare_fill)] for r in train_rows]
    validation_payload = [
        [label(r), *encode_features(r, age_fill, fare_fill)] for r in validation_rows
    ]

    write_rows(Path(args.train_output), train_payload)
    write_rows(Path(args.validation_output), validation_payload)
    print(
        f"prepared train={len(train_payload)} validation={len(validation_payload)} "
        f"age_fill={age_fill:.4f} fare_fill={fare_fill:.4f}"
    )


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/prepare_xgb_inputs.py"
```

### 2. Crear el evaluador reutilizable

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/evaluate.py" <<'EOF'
#!/usr/bin/env python
from __future__ import annotations

import argparse
import csv
import json
import tarfile
from pathlib import Path

import xgboost as xgb


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-artifact", required=True)
    parser.add_argument("--validation", required=True)
    parser.add_argument("--accuracy-threshold", type=float, default=0.78)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def read_validation(path: Path) -> tuple[list[int], list[list[float]]]:
    labels: list[int] = []
    features: list[list[float]] = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            labels.append(int(float(row[0])))
            features.append([float(value) for value in row[1:]])
    if not labels:
        raise ValueError("validation vacio")
    return labels, features


def safe_div(num: float, den: float) -> float:
    return num / den if den else 0.0


def ensure_model_file(model_artifact: Path) -> Path:
    extract_dir = Path("/tmp/titanic_model_extract")
    extract_dir.mkdir(parents=True, exist_ok=True)
    with tarfile.open(model_artifact, "r:gz") as tar:
        tar.extractall(extract_dir)
    for candidate in [
        extract_dir / "xgboost-model",
        extract_dir / "model.json",
        extract_dir / "xgboost-model.json",
    ]:
        if candidate.exists():
            return candidate
    found = sorted(str(p) for p in extract_dir.rglob("*") if p.is_file())
    raise FileNotFoundError(f"No se encontro un modelo en {found}")


def main() -> None:
    args = parse_args()
    labels, features = read_validation(Path(args.validation))
    model_path = ensure_model_file(Path(args.model_artifact))

    booster = xgb.Booster()
    booster.load_model(str(model_path))
    scores = booster.predict(xgb.DMatrix(features))

    tp = tn = fp = fn = 0
    for score, label in zip(scores, labels):
        pred = 1 if float(score) >= 0.5 else 0
        if pred == 1 and label == 1:
            tp += 1
        elif pred == 0 and label == 0:
            tn += 1
        elif pred == 1 and label == 0:
            fp += 1
        else:
            fn += 1

    total = len(labels)
    accuracy = safe_div(tp + tn, total)
    precision = safe_div(tp, tp + fp)
    recall = safe_div(tp, tp + fn)
    f1 = safe_div(2 * precision * recall, precision + recall)

    payload = {
        "metrics": {
            "accuracy": accuracy,
            "precision": precision,
            "recall": recall,
            "f1": f1,
        },
        "thresholds": {
            "accuracy_threshold": args.accuracy_threshold,
            "passed": accuracy >= args.accuracy_threshold,
        },
        "confusion_matrix": {"tp": tp, "tn": tn, "fp": fp, "fn": fn},
        "samples": total,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/evaluate.py"
```

### 3. Preparar los CSV numericos

```bash
uv run python "$TUTORIAL_ROOT/mlops_assets/prepare_xgb_inputs.py" \
  --train-input "$TUTORIAL_ROOT/data/splits/train.csv" \
  --validation-input "$TUTORIAL_ROOT/data/splits/validation.csv" \
  --train-output "$TUTORIAL_ROOT/data/sagemaker/train_xgb.csv" \
  --validation-output "$TUTORIAL_ROOT/data/sagemaker/validation_xgb.csv"

wc -l \
  "$TUTORIAL_ROOT/data/sagemaker/train_xgb.csv" \
  "$TUTORIAL_ROOT/data/sagemaker/validation_xgb.csv"
```

### 4. Subir los CSV preparados a S3

```bash
export TRAIN_XGB_S3_URI="s3://$DATA_BUCKET/training/xgboost/train_xgb.csv"
export VALIDATION_XGB_S3_URI="s3://$DATA_BUCKET/training/xgboost/validation_xgb.csv"

aws s3 cp "$TUTORIAL_ROOT/data/sagemaker/train_xgb.csv" "$TRAIN_XGB_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp "$TUTORIAL_ROOT/data/sagemaker/validation_xgb.csv" "$VALIDATION_XGB_S3_URI" --profile "$AWS_PROFILE"
```

### 5. Lanzar el training job

```bash
uv run python - <<'PY'
import os
from pathlib import Path

import boto3
from sagemaker.core import image_uris
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.train import ModelTrainer
from sagemaker.train.configs import Compute, InputData, OutputDataConfig

boto_session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
session = Session(boto_session=boto_session)

try:
    role_arn = get_execution_role()
except Exception:
    role_arn = os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"]

xgb_image_uri = image_uris.retrieve(
    framework="xgboost",
    region=os.environ["AWS_REGION"],
    version="1.7-1",
    py_version="py3",
    instance_type="ml.m5.large",
)

trainer = ModelTrainer(
    training_image=xgb_image_uri,
    role=role_arn,
    sagemaker_session=session,
    base_job_name="titanic-xgb-train",
    compute=Compute(instance_type="ml.m5.large", instance_count=1, volume_size_in_gb=10),
    hyperparameters={
        "objective": "binary:logistic",
        "num_round": 200,
        "max_depth": 5,
        "eta": 0.2,
        "subsample": 0.8,
        "eval_metric": "logloss",
    },
    output_data_config=OutputDataConfig(
        s3_output_path=f"s3://{os.environ['DATA_BUCKET']}/training/xgboost/output",
    ),
    input_data_config=[
        InputData(
            channel_name="train",
            data_source=os.environ["TRAIN_XGB_S3_URI"],
            content_type="text/csv",
        ),
        InputData(
            channel_name="validation",
            data_source=os.environ["VALIDATION_XGB_S3_URI"],
            content_type="text/csv",
        ),
    ],
)

training_job = trainer.train(wait=True, logs=True)
output_path = Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "training_job_name.txt"
output_path.write_text(training_job.name + "\n", encoding="utf-8")
print(f"training_job={training_job.name}")
PY
```

### 6. Descargar el modelo entrenado

```bash
uv run python - <<'PY'
import os
from pathlib import Path

import boto3

tutorial_root = Path(os.environ["TUTORIAL_ROOT"])
training_job_name = (tutorial_root / "artifacts" / "training_job_name.txt").read_text(
    encoding="utf-8"
).strip()

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")
s3_client = session.client("s3")

job_desc = sm_client.describe_training_job(TrainingJobName=training_job_name)
model_artifact_s3_uri = job_desc["ModelArtifacts"]["S3ModelArtifacts"]
bucket, key = model_artifact_s3_uri.replace("s3://", "", 1).split("/", 1)

target = tutorial_root / "artifacts" / "model" / "model.tar.gz"
target.parent.mkdir(parents=True, exist_ok=True)
s3_client.download_file(bucket, key, str(target))

print(f"model_artifact_s3_uri={model_artifact_s3_uri}")
print(f"downloaded_to={target}")
PY
```

### 7. Evaluar el modelo localmente

```bash
uv run python "$TUTORIAL_ROOT/mlops_assets/evaluate.py" \
  --model-artifact "$TUTORIAL_ROOT/artifacts/model/model.tar.gz" \
  --validation "$TUTORIAL_ROOT/data/sagemaker/validation_xgb.csv" \
  --accuracy-threshold "$ACCURACY_THRESHOLD" \
  --output "$TUTORIAL_ROOT/artifacts/evaluation.json"
```

### 8. Emitir la decision de promocion

```bash
uv run python - <<'PY'
import json
import os
from pathlib import Path

tutorial_root = Path(os.environ["TUTORIAL_ROOT"])
evaluation = json.loads((tutorial_root / "artifacts" / "evaluation.json").read_text(encoding="utf-8"))
payload = {
    "threshold_accuracy": evaluation["thresholds"]["accuracy_threshold"],
    "observed_accuracy": evaluation["metrics"]["accuracy"],
    "decision": "pass" if evaluation["thresholds"]["passed"] else "fail",
}
target = tutorial_root / "artifacts" / "promotion_decision.json"
target.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(json.dumps(payload, indent=2))
PY
```

### 9. Publicar la evidencia en S3

```bash
aws s3 cp "$TUTORIAL_ROOT/artifacts/evaluation.json" \
  "s3://$DATA_BUCKET/evaluation/xgboost/evaluation.json" \
  --profile "$AWS_PROFILE"

aws s3 cp "$TUTORIAL_ROOT/artifacts/promotion_decision.json" \
  "s3://$DATA_BUCKET/evaluation/xgboost/promotion_decision.json" \
  --profile "$AWS_PROFILE"
```

## IAM usado

- `DataScienceTutorialOperator` para training, S3 y lectura del estado.
- `DataScienceTutorialCleanup` solo si necesitas parar o borrar recursos de esta fase.

## Evidencia requerida

1. `training_job_name.txt`
2. `evaluation.json`
3. `promotion_decision.json`
4. `ModelArtifacts.S3ModelArtifacts`

## Criterio de cierre

- Baseline entrenado con `ModelTrainer`.
- Modelo descargado.
- Contrato `evaluation.json` generado.
- Decision de promocion disponible.

## Riesgos/pendientes

- Si cambias la forma de `validation_xgb.csv`, debes regenerar tambien el evaluador.
- Si `SAGEMAKER_EXECUTION_ROLE_ARN` no es valido fuera de runtimes gestionados, el training
  no arrancara.

## Proximo paso

Continuar con [`03-sagemaker-pipeline.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/03-sagemaker-pipeline.md).
