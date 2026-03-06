# 02 Training and Validation

## Objetivo y contexto
Entrenar un modelo binario (`Survived`) en SageMaker usando el SDK V3 y emitir una decision
objetiva `pass/fail` usando el validation set.

Esta fase es un ensayo manual de la parte central de `ModelBuild` para validar dataset,
features, hiperparametros y umbral antes de codificar el pipeline automatizado en fase 03.

## Resultado minimo esperado
1. Un `TrainingJob` exitoso creado via SageMaker SDK V3 `ModelTrainer`.
2. Predicciones sobre validation (Batch Transform o inferencia local como fallback).
3. `metrics.json` con `accuracy`, `precision`, `recall`, `f1`.
4. `promotion_decision.json` con `pass` o `fail`.

## Fuentes oficiales usadas en esta fase
1. SageMaker V3 Training: `vendor/sagemaker-python-sdk/docs/training/index.rst`
2. ModelTrainer API: `vendor/sagemaker-python-sdk/docs/api/sagemaker_train.rst`
3. Training configs: `vendor/sagemaker-python-sdk/sagemaker-core/src/sagemaker/core/training/configs.py`
4. Image URIs: `vendor/sagemaker-python-sdk/sagemaker-core/src/sagemaker/core/image_uris.py`
5. V3 training example: `vendor/sagemaker-python-sdk/v3-examples/training-examples/`
6. `https://docs.aws.amazon.com/sagemaker/latest/dg/xgboost.html`
7. `https://docs.aws.amazon.com/sagemaker/latest/dg/batch-transform.html`
8. `https://docs.aws.amazon.com/sagemaker/latest/dg/regions-quotas.html`

## Alineacion con la arquitectura de referencia
Mapeo directo a la arquitectura `ModelBuild`:
1. Preparar `train_xgb/validation_xgb` -> equivalente funcional de `DataPreProcessing`.
2. Crear Training Job via `ModelTrainer` -> `TrainModel`.
3. Batch Transform + calculo de metricas -> equivalente funcional de `ModelEvaluation`.
4. `promotion_decision.json` -> gate de calidad previo a `RegisterModel`.

Fuera de alcance en esta fase:
- `RegisterModel` en Model Registry (se ejecuta en fase 03).
- Despliegue `staging/prod` (se ejecuta en fase 04).

## Prerequisitos concretos
1. Fase 00 completada (SDK V3 instalado, Terraform foundations aplicado).
2. Fase 01 completada (datasets en S3):
   - `s3://<DATA_BUCKET>/curated/train.csv`
   - `s3://<DATA_BUCKET>/curated/validation.csv`
3. Perfil AWS CLI operativo: `data-science-user`.
4. Un SageMaker execution role existente con permisos a:
   - leer/escribir en el bucket del proyecto,
   - ejecutar Training/Model/Transform jobs,
   - escribir logs en CloudWatch.
5. Ejecutar este tutorial desde la raiz del repositorio.

## Como se entrena realmente el modelo
1. **Local solo prepara/evalua**:
   - `scripts/prepare_titanic_xgboost_inputs.py` transforma CSV a features numericas.
   - `scripts/evaluate_titanic_predictions.py` calcula metricas sobre predicciones.
2. **El entrenamiento real ocurre en AWS SageMaker**:
   - Se usa `ModelTrainer` (V3) con imagen built-in XGBoost.
   - El artefacto del modelo queda en S3 (`training/xgboost/output/`).
3. **La evaluacion usa Batch Transform o inferencia local**:
   - Opcion A: Batch Transform en SageMaker (preferente).
   - Opcion B: Inferencia local desde `ModelArtifacts` (workaround si no hay quota).

## Estandar SDK en esta fase
Todo el flujo de entrenamiento usa patrones de SageMaker SDK V3:
- `sagemaker.train.ModelTrainer` para crear y ejecutar training jobs.
- `sagemaker.train.configs` (`Compute`, `InputData`, `OutputDataConfig`) para configuracion declarativa.
- `sagemaker.core.image_uris.retrieve()` para imagenes built-in.
- `sagemaker.core.helper.session_helper.Session()` para bootstrap de sesion.

## Paso a paso (ejecucion)

### Paso 1 -- Definir variables del run

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)

export TRAIN_RAW_S3_URI=s3://$DATA_BUCKET/curated/train.csv
export VALIDATION_RAW_S3_URI=s3://$DATA_BUCKET/curated/validation.csv

export TRAIN_XGB_S3_URI=s3://$DATA_BUCKET/training/xgboost/train_xgb.csv
export VALIDATION_XGB_S3_URI=s3://$DATA_BUCKET/training/xgboost/validation_xgb.csv
export VALIDATION_FEATURES_S3_URI=s3://$DATA_BUCKET/training/xgboost/validation_features_xgb.csv
export VALIDATION_LABELS_S3_URI=s3://$DATA_BUCKET/training/xgboost/validation_labels.csv
```

### Paso 2 -- Verificar que los datos de fase 01 existen en S3

```bash
aws s3 ls "$TRAIN_RAW_S3_URI" --profile "$AWS_PROFILE"
aws s3 ls "$VALIDATION_RAW_S3_URI" --profile "$AWS_PROFILE"
```

### Paso 3 -- Preparar features numericas para XGBoost (sin headers)

```bash
python3 scripts/prepare_titanic_xgboost_inputs.py
wc -l data/titanic/sagemaker/train_xgb.csv data/titanic/sagemaker/validation_xgb.csv
```

### Paso 4 -- Subir archivos preparados a S3

```bash
aws s3 cp data/titanic/sagemaker/train_xgb.csv "$TRAIN_XGB_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_xgb.csv "$VALIDATION_XGB_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_features_xgb.csv "$VALIDATION_FEATURES_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_labels.csv "$VALIDATION_LABELS_S3_URI" --profile "$AWS_PROFILE"
```

### Paso 5 -- Crear Training Job con ModelTrainer (SageMaker SDK V3)

Este es el paso central que reemplaza la creacion manual via Console.

```python
import os
import boto3
from sagemaker.core.helper.session_helper import Session
from sagemaker.core import image_uris
from sagemaker.train import ModelTrainer
from sagemaker.train.configs import Compute, InputData, OutputDataConfig

# --- Bootstrap de sesion ---
AWS_PROFILE = os.getenv("AWS_PROFILE", "data-science-user")
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
DATA_BUCKET = os.environ["DATA_BUCKET"]

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
session = Session(boto_session=boto_session)

# Role de ejecucion de SageMaker (creado por Terraform o manualmente)
SAGEMAKER_EXEC_ROLE_ARN = os.environ["SAGEMAKER_PIPELINE_ROLE_ARN"]

# --- Obtener imagen built-in XGBoost ---
xgb_image_uri = image_uris.retrieve(
    framework="xgboost",
    region=AWS_REGION,
    version="1.7-1",
    py_version="py3",
    instance_type="ml.m5.large",
)
print(f"XGBoost image: {xgb_image_uri}")

# --- Crear ModelTrainer ---
model_trainer = ModelTrainer(
    training_image=xgb_image_uri,
    role=SAGEMAKER_EXEC_ROLE_ARN,
    sagemaker_session=session,
    base_job_name="titanic-xgb-train",
    compute=Compute(
        instance_type="ml.m5.large",
        instance_count=1,
        volume_size_in_gb=10,
    ),
    hyperparameters={
        "objective": "binary:logistic",
        "num_round": 200,
        "max_depth": 5,
        "eta": 0.2,
        "subsample": 0.8,
        "eval_metric": "logloss",
    },
    output_data_config=OutputDataConfig(
        s3_output_path=f"s3://{DATA_BUCKET}/training/xgboost/output",
    ),
    input_data_config=[
        InputData(
            channel_name="train",
            data_source=f"s3://{DATA_BUCKET}/training/xgboost/train_xgb.csv",
            content_type="text/csv",
        ),
        InputData(
            channel_name="validation",
            data_source=f"s3://{DATA_BUCKET}/training/xgboost/validation_xgb.csv",
            content_type="text/csv",
        ),
    ],
)

# --- Lanzar entrenamiento ---
print("Lanzando training job...")
model_trainer.train(wait=True, logs=True)
print("Training completado.")

# --- Obtener nombre del job ---
training_job = model_trainer._latest_training_job
print(f"TrainingJobName: {training_job.training_job_name}")
print(f"TrainingJobArn: {training_job.training_job_arn}")
```

Referencia V3: `vendor/sagemaker-python-sdk/docs/training/index.rst`
Ejemplo V3: `vendor/sagemaker-python-sdk/v3-examples/training-examples/`

### Paso 6 -- Monitorear estado del training job (CLI alternativo)

Si prefieres monitorear por CLI en otra terminal:

```bash
export TRAINING_JOB_NAME=<nombre-del-job-creado>
aws sagemaker describe-training-job \
  --training-job-name "$TRAINING_JOB_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'TrainingJobStatus'
```

Si el estado es `Failed`:

```bash
aws sagemaker describe-training-job \
  --training-job-name "$TRAINING_JOB_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'FailureReason'
```

### Paso 7 -- Obtener predicciones para evaluacion

#### Opcion A (preferente): Batch Transform

Crear modelo y ejecutar Batch Transform. Si no hay quota de transform, ir a Opcion B.

Verificar quotas disponibles primero:

```bash
aws service-quotas list-service-quotas \
  --service-code sagemaker \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "Quotas[?contains(QuotaName, 'for transform job usage')].[QuotaName,Value]" \
  --output table
```

Si hay quota disponible, crear transform job via Console o CLI:
- Input: `s3://.../training/xgboost/validation_features_xgb.csv`
- Output: `s3://$DATA_BUCKET/evaluation/xgboost/predictions/`
- Content type: `text/csv`
- Split type: `Line`
- Instance count: `1`
- Instance type: usar un tipo con quota > 0
- Tags: `project=titanic-sagemaker`, `tutorial_phase=02`

Luego descargar predicciones:

```bash
aws s3 cp \
  s3://$DATA_BUCKET/evaluation/xgboost/predictions/ \
  data/titanic/sagemaker/predictions/ \
  --recursive \
  --profile "$AWS_PROFILE"

export PREDICTIONS_FILE=$(find data/titanic/sagemaker/predictions -type f -name "*.out" | head -n 1)
cp "$PREDICTIONS_FILE" data/titanic/sagemaker/validation_predictions.csv
```

#### Opcion B (workaround): Inferencia local desde ModelArtifacts

Cuando no hay quota de transform job, se pueden generar predicciones localmente.

1) Obtener y descargar artefacto del modelo entrenado:

```bash
export MODEL_ARTIFACT_S3_URI=$(aws sagemaker describe-training-job \
  --training-job-name "$TRAINING_JOB_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'ModelArtifacts.S3ModelArtifacts' \
  --output text)

mkdir -p data/titanic/sagemaker/model
aws s3 cp "$MODEL_ARTIFACT_S3_URI" data/titanic/sagemaker/model/model.tar.gz --profile "$AWS_PROFILE"
mkdir -p data/titanic/sagemaker/model/extracted
tar -xzf data/titanic/sagemaker/model/model.tar.gz -C data/titanic/sagemaker/model/extracted
```

2) Generar predicciones localmente con XGBoost:

Nota de compatibilidad:
- Los artefactos generados por `sagemaker-xgboost:1.3-1` pueden fallar con `xgboost` 3.x.
- Usar `xgboost==2.1.4` para compatibilidad.

```bash
uv run --with xgboost==2.1.4 python - <<'PY'
import csv
from pathlib import Path

import xgboost as xgb

features_path = Path("data/titanic/sagemaker/validation_features_xgb.csv")
predictions_path = Path("data/titanic/sagemaker/validation_predictions.csv")
model_root = Path("data/titanic/sagemaker/model/extracted")

model_files = sorted([p for p in model_root.rglob("*") if p.is_file() and p.name.startswith("xgboost-model")])
if not model_files:
    raise FileNotFoundError("No se encontro xgboost-model dentro de model.tar.gz")

rows = []
with features_path.open("r", encoding="utf-8") as f:
    reader = csv.reader(f)
    for row in reader:
        if not row:
            continue
        rows.append([float(x) for x in row])

if not rows:
    raise ValueError("validation_features_xgb.csv no tiene filas")

dmat = xgb.DMatrix(rows)
booster = xgb.Booster()
booster.load_model(str(model_files[0]))
preds = booster.predict(dmat)

predictions_path.parent.mkdir(parents=True, exist_ok=True)
with predictions_path.open("w", encoding="utf-8", newline="") as f:
    for score in preds:
        f.write(f"{float(score):.10f}\n")

print(f"Predicciones generadas: {len(preds)} -> {predictions_path}")
PY
```

### Paso 8 -- Calcular metricas de evaluacion

```bash
python3 scripts/evaluate_titanic_predictions.py \
  --predictions data/titanic/sagemaker/validation_predictions.csv \
  --labels data/titanic/sagemaker/validation_labels.csv \
  --threshold 0.5 \
  --output data/titanic/sagemaker/metrics.json
```

### Paso 9 -- Emitir decision pass/fail con umbral de promocion

```bash
python3 - <<'PY'
import json
from pathlib import Path

metrics_path = Path("data/titanic/sagemaker/metrics.json")
decision_path = Path("data/titanic/sagemaker/promotion_decision.json")
threshold = 0.78

metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
decision = "pass" if metrics["accuracy"] >= threshold else "fail"

payload = {
    "threshold_accuracy": threshold,
    "observed_accuracy": metrics["accuracy"],
    "decision": decision,
}
decision_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(payload)
PY
```

### Paso 10 -- Publicar evidencia de metricas/decision en S3

```bash
aws s3 cp data/titanic/sagemaker/metrics.json \
  s3://$DATA_BUCKET/evaluation/xgboost/metrics.json \
  --profile "$AWS_PROFILE"

aws s3 cp data/titanic/sagemaker/promotion_decision.json \
  s3://$DATA_BUCKET/evaluation/xgboost/promotion_decision.json \
  --profile "$AWS_PROFILE"
```

### Paso 11 -- (Opcional) Resetear estado para repetir fase 02

```bash
# Plan de borrado (sin cambios)
scripts/reset_tutorial_state.sh --target after-tutorial-2

# Ejecutar borrado real
scripts/reset_tutorial_state.sh --target after-tutorial-2 --apply --confirm RESET
```

## Handoff explicito a fase 03
La fase 02 entrega baseline y criterio de calidad para fase 03, pero no impone como contrato
de entrada los CSV procesados manualmente.
1. **Regla de calidad** a reutilizar en pipeline: threshold `accuracy >= 0.78`.
2. **Config base de entrenamiento** validada: algoritmo XGBoost, hiperparametros documentados.
3. **Artefactos de evidencia**: `evaluation/xgboost/metrics.json` y `promotion_decision.json`.
4. **Separacion arquitectonica**: fase 03 inicia desde `curated/train.csv` y `curated/validation.csv`.
   Los archivos `train_xgb.csv`, `validation_xgb.csv`, etc. pasan a ser artefactos internos
   del paso `DataPreProcessing` del pipeline.

## Decisiones tecnicas y alternativas descartadas
- SDK V3 `ModelTrainer` como metodo primario de creacion de training jobs (reemplaza Console manual).
- El umbral de promocion queda en `accuracy >= 0.78`.
- La evaluacion se calcula fuera del training job con Batch Transform + script local.
- Si no hay quota de transform, se permite fallback temporal con inferencia local desde `ModelArtifacts`.
- Alternativas descartadas: Console-only workflow sin SDK, promover modelo solo por estado `Completed`.

## IAM usado (roles/policies/permisos clave)
- Operador humano: `data-science-user`.
- SageMaker execution role con permisos minimos para:
  - `sagemaker:CreateTrainingJob`, `DescribeTrainingJob`, `CreateModel`, `CreateTransformJob`,
  - `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` en bucket del proyecto,
  - escritura de logs/metricas en CloudWatch.

## Evidencia
Agregar:
- `TrainingJobArn` (del output de `ModelTrainer`).
- `TransformJobArn` (si aplica) o evidencia de workaround local.
- `metrics.json` y `promotion_decision.json`.
- URI S3 del modelo (`ModelArtifacts.S3ModelArtifacts`).

## Criterio de cierre
- Training job creado via V3 `ModelTrainer` y finalizado en estado exitoso.
- Transform job exitoso o workaround local ejecutado y documentado.
- Metricas de validacion generadas y publicadas en S3.
- Decision de promocion (`pass`/`fail`) documentada y trazable.

## Troubleshooting rapido
| Sintoma | Causa raiz probable | Accion recomendada |
|---|---|---|
| `XGBoostError ... preds.Size() != labels.Size()` | `objective=reg:logistic` y/o `num_class` definido en problema binario | Corregir a `objective=binary:logistic` y remover `num_class` |
| `AccessDenied ... s3:GetObject ... train_xgb.csv` | Policy S3 no adjunta al execution role de SageMaker | Verificar que la policy este adjunta al role (no solo como permissions boundary) |
| `ResourceLimitExceeded ... for transform job usage` | Quota de instancia en 0 | Ajustar a instancia con quota > 0 o solicitar increase |
| `Failed to load model ... binary format ... removed in 3.1` | Version local de XGBoost incompatible | Usar `uv run --with xgboost==2.1.4` para workaround local |
| `ImportError: ModelTrainer` | Paquete SageMaker incorrecto o instalacion incompleta | Verificar `pip show sagemaker` -> version debe ser 3.x |

## Riesgos/pendientes
- Drift entre dataset versionado y dataset usado en entrenamiento real.
- Falta de control de sesgo o fairness en features seleccionadas.
- Ajuste de hiperparametros pendiente para mejorar `f1` sin degradar `recall`.
- Quotas de Batch Transform pueden estar en `0` para todas las instancias en cuentas nuevas.

## Proximo paso
Automatizar flujo con SageMaker Pipeline en `docs/tutorials/03-sagemaker-pipeline.md`.
