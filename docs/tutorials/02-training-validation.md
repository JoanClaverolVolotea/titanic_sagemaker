# 02 Training and Validation

## Objetivo y contexto
Entrenar un modelo binario (`Survived`) en SageMaker y emitir una decision objetiva
`pass/fail` usando el validation set.

Resultado minimo esperado al cerrar esta fase:
1. Un `TrainingJobArn` exitoso.
2. Predicciones sobre validation (preferente por Batch Transform; fallback local si no hay quota de transform).
3. `metrics.json` con `accuracy`, `precision`, `recall`, `f1`.
4. `promotion_decision.json` con `pass` o `fail`.

## Fuentes oficiales (SageMaker DG/API) usadas en esta fase
1. `https://docs.aws.amazon.com/sagemaker/latest/dg/how-it-works-training.html`
2. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateTrainingJob.html`
3. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_DescribeTrainingJob.html`
4. `https://docs.aws.amazon.com/sagemaker/latest/dg/xgboost.html`
5. `https://docs.aws.amazon.com/sagemaker/latest/dg/batch-transform.html`
6. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateTransformJob.html`
7. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_DescribeTransformJob.html`
8. `https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_CreateModel.html`
9. `https://docs.aws.amazon.com/sagemaker/latest/dg/regions-quotas.html`
10. `https://docs.aws.amazon.com/servicequotas/latest/userguide/intro.html`
11. Referencia local de estudio: `docs/aws/sagemaker-dg.pdf`.

## Alineacion con la arquitectura de referencia (imagen)
Esta fase es un ensayo manual de la parte central de `ModelBuild` para validar
dataset, features, hiperparametros y umbral antes de codificar el pipeline de la fase 03.

Mapeo directo:
1. Preparar `train_xgb/validation_xgb` -> equivalente funcional de `DataPreProcessing`.
2. Crear Training Job -> `TrainModel`.
3. Batch Transform + calculo de metricas -> equivalente funcional de `ModelEvaluation`.
4. `promotion_decision.json` -> gate de calidad previo a `RegisterModel`.

Fuera de alcance en esta fase:
- `RegisterModel` en Model Registry (se ejecuta en fase 03).
- Despliegue `staging/prod` (se ejecuta en fase 04/05).

## Prerequisitos concretos
1. Fase 00 aplicada en `terraform/00_foundations` (bucket y controles base activos).
2. Bucket operativo obtenido desde output de fase 00:
   - `terraform -chdir=terraform/00_foundations output -raw data_bucket_name`
3. Fase 01 completada (dataset cargado en bucket de fase 00):
   - `s3://<DATA_BUCKET_FROM_PHASE_00>/curated/train.csv`
   - `s3://<DATA_BUCKET_FROM_PHASE_00>/curated/validation.csv`
4. Perfil AWS CLI operativo: `data-science-user`.
5. Un SageMaker execution role existente con permisos a:
   - leer/escribir en el bucket del proyecto,
   - ejecutar Training/Model/Transform jobs,
   - escribir logs en CloudWatch.
6. Ejecutar este tutorial desde la raiz del repositorio para resolver `terraform -chdir=terraform/00_foundations ...`.

## Como se entrena realmente el modelo (sin ambiguedad)
1. Local solo prepara/evalua:
   - `scripts/prepare_titanic_xgboost_inputs.py` transforma CSV a features numericas.
   - `scripts/evaluate_titanic_predictions.py` calcula metricas sobre predicciones.
2. El entrenamiento real ocurre en AWS SageMaker:
   - Paso 5 crea un `Training Job` en SageMaker (`Built-in XGBoost`).
   - El artefacto del modelo queda en S3 (`training/xgboost/output/`).
3. La evaluacion operacional ocurre con Batch Transform en SageMaker:
   - Paso 7 ejecuta inferencia batch sobre validation.
   - Paso 8 baja predicciones para calcular metricas y decidir `pass/fail`.

## Paso a paso (ejecucion)
1. Definir variables del run:

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

2. Verificar que los datos de fase 01 existen en S3:

```bash
aws s3 ls "$TRAIN_RAW_S3_URI" --profile "$AWS_PROFILE"
aws s3 ls "$VALIDATION_RAW_S3_URI" --profile "$AWS_PROFILE"
```

3. Preparar features numericas para XGBoost (sin headers):

```bash
python3 scripts/prepare_titanic_xgboost_inputs.py
wc -l data/titanic/sagemaker/train_xgb.csv data/titanic/sagemaker/validation_xgb.csv
```

4. Subir archivos preparados a S3:

```bash
aws s3 cp data/titanic/sagemaker/train_xgb.csv "$TRAIN_XGB_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_xgb.csv "$VALIDATION_XGB_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_features_xgb.csv "$VALIDATION_FEATURES_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_labels.csv "$VALIDATION_LABELS_S3_URI" --profile "$AWS_PROFILE"
```

5. Crear Training Job en AWS Console (SageMaker):
   - Ir a `Amazon SageMaker > Training jobs > Create training job`.
   - Nombre sugerido: `titanic-xgb-train-<yyyymmdd-hhmm>`.
   - Algoritmo: `Built-in algorithm > XGBoost`.
   - Input mode: `File`.
   - Canales de datos:
     - `train` -> `s3://.../training/xgboost/train_xgb.csv`
     - `validation` -> `s3://.../training/xgboost/validation_xgb.csv`
     - Content type: `text/csv`.
   - Output path: `s3://$DATA_BUCKET/training/xgboost/output/`
   - Tipo de instancia: `ml.m5.large`, count `1`.
   - Hyperparameters minimos:
     - `objective=binary:logistic`
     - no definir `num_class` para este caso binario
     - `num_round=200`
     - `max_depth=5`
     - `eta=0.2`
     - `subsample=0.8`
     - `eval_metric=logloss`
   - Execution role: usar el rol SageMaker del proyecto con acceso al bucket.
   - Tags recomendados en el job:
     - `project=titanic-sagemaker`
     - `tutorial_phase=02`

6. Monitorear estado del training job:

```bash
export TRAINING_JOB_NAME=<nombre-del-job-creado-en-console>
aws sagemaker describe-training-job \
  --training-job-name "$TRAINING_JOB_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'TrainingJobStatus'
```

Si el estado es `Failed`, revisar causa raiz:

```bash
aws sagemaker describe-training-job \
  --training-job-name "$TRAINING_JOB_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'FailureReason'
```

7. Crear modelo y Batch Transform sobre validation:
   - En el detalle del training job, crear `Model` con nombre sugerido:
     - `titanic-xgb-model-<yyyymmdd-hhmm>`
   - Crear `Batch transform job` con:
     - Nombre sugerido: `titanic-xgb-transform-<yyyymmdd-hhmm>`
     - Input: `s3://.../training/xgboost/validation_features_xgb.csv`
     - Output: `s3://$DATA_BUCKET/evaluation/xgboost/predictions/`
     - Content type: `text/csv`
     - Split type: `Line`
     - Instance count: `1`
     - Instance type: usar un tipo con quota disponible para transform job usage (no asumir `ml.m5.large`)
     - Tags recomendados:
       - `project=titanic-sagemaker`
       - `tutorial_phase=02`

Antes de crear el transform job, validar quotas disponibles por CLI:

```bash
aws service-quotas list-service-quotas \
  --service-code sagemaker \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "Quotas[?contains(QuotaName, 'for transform job usage')].[QuotaName,Value]" \
  --output table
```

Si recibes `ResourceLimitExceeded`:
- Verifica quota de la instancia elegida.
- Cambia a otra instancia con quota > 0.
- Si todas estan en `0`, solicita increase en Service Quotas y deja evidencia en `docs/iterations/`.

8. Obtener predicciones y calcular metricas:

Opcion A (preferente): Batch Transform
- Descargar predicciones de S3 y evaluar metricas:

```bash
aws s3 cp \
  s3://$DATA_BUCKET/evaluation/xgboost/predictions/ \
  data/titanic/sagemaker/predictions/ \
  --recursive \
  --profile "$AWS_PROFILE"

export PREDICTIONS_FILE=$(find data/titanic/sagemaker/predictions -type f -name "*.out" | head -n 1)
cp "$PREDICTIONS_FILE" data/titanic/sagemaker/validation_predictions.csv

python3 scripts/evaluate_titanic_predictions.py \
  --predictions data/titanic/sagemaker/validation_predictions.csv \
  --labels data/titanic/sagemaker/validation_labels.csv \
  --threshold 0.5 \
  --output data/titanic/sagemaker/metrics.json
```

Opcion B (workaround): inferencia local desde `ModelArtifacts` cuando no hay quota de transform

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

2) Generar predicciones localmente con el modelo XGBoost:

```bash
uv run --with xgboost==2.1.4 python -c "import xgboost; print(xgboost.__version__)"
```

Nota de compatibilidad:
- Los artefactos generados por `sagemaker-xgboost:1.3-1` pueden fallar con `xgboost` 3.x al cargar `xgboost-model`.
- Para este workaround usar `xgboost==2.1.4`.

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

3) Calcular metricas con el mismo script de evaluacion:

```bash
python3 scripts/evaluate_titanic_predictions.py \
  --predictions data/titanic/sagemaker/validation_predictions.csv \
  --labels data/titanic/sagemaker/validation_labels.csv \
  --threshold 0.5 \
  --output data/titanic/sagemaker/metrics.json
```

9. Emitir decision `pass/fail` con umbral de promocion:

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

10. Publicar evidencia de metricas/decision en S3:

```bash
aws s3 cp data/titanic/sagemaker/metrics.json \
  s3://$DATA_BUCKET/evaluation/xgboost/metrics.json \
  --profile "$AWS_PROFILE"

aws s3 cp data/titanic/sagemaker/promotion_decision.json \
  s3://$DATA_BUCKET/evaluation/xgboost/promotion_decision.json \
  --profile "$AWS_PROFILE"
```

11. (Opcional) Resetear estado para repetir fase 02:

```bash
# Plan de borrado (sin cambios)
scripts/reset_tutorial_state.sh --target after-tutorial-2

# Ejecutar borrado real
scripts/reset_tutorial_state.sh --target after-tutorial-2 --apply --confirm RESET
```

## Handoff explicito a fase 03
La fase 02 entrega baseline y criterio de calidad para fase 03, pero no impone como contrato
de entrada los CSV procesados manualmente.
1. Regla de calidad a reutilizar en pipeline:
   - threshold `accuracy >= 0.78`.
2. Config base de entrenamiento validada:
   - algoritmo `XGBoost`,
   - hiperparametros base documentados en este tutorial.
3. Artefactos de evidencia para trazabilidad:
   - `evaluation/xgboost/metrics.json`
   - `evaluation/xgboost/promotion_decision.json`
4. Nota de separacion arquitectonica:
   - fase 03 debe iniciar desde `curated/train.csv` y `curated/validation.csv`,
   - `train_xgb.csv`, `validation_xgb.csv`, `validation_features_xgb.csv`, `validation_labels.csv`
     pasan a ser artefactos internos del paso `DataPreProcessing` del pipeline.

## Decisiones tecnicas y alternativas descartadas
- Se estandariza un baseline reproducible con `XGBoost` de SageMaker sobre features numericas.
- Fase 02 consume el bucket de salida de fase 00 para evitar drift de nombres entre infraestructura y ejecucion.
- El umbral de promocion de esta fase queda en `accuracy >= 0.78`.
- La evaluacion se calcula fuera del training job con Batch Transform + script local para obtener
  `accuracy`, `precision`, `recall`, `f1`.
- Si no hay quota de transform job usage, se permite fallback temporal con inferencia local desde `ModelArtifacts`.
- Alternativas descartadas: promover modelo solo por estado `Completed` sin metricas de calidad.

## IAM usado (roles/policies/permisos clave)
- Operador humano: `data-science-user`.
- SageMaker execution role con permisos minimos para:
  - `sagemaker:CreateTrainingJob`, `DescribeTrainingJob`, `CreateModel`, `CreateTransformJob`,
  - `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` en bucket del proyecto,
  - escritura de logs/metricas en CloudWatch.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con perfil `data-science-user`.
- `python3 scripts/prepare_titanic_xgboost_inputs.py`
- `aws s3 cp ... train_xgb.csv / validation_xgb.csv / validation_features_xgb.csv / validation_labels.csv`
- Crear training job y transform job en SageMaker Console (si hay quota de transform).
- Workaround local (si no hay quota): `uv run --with xgboost==2.1.4 python - <<'PY' ...`
- `python3 scripts/evaluate_titanic_predictions.py ...`
- Resultado esperado:
  - `TrainingJobStatus=Completed`,
  - `metrics.json` generado con `accuracy`, `precision`, `recall`, `f1`,
  - `promotion_decision.json` con `pass` o `fail`.

## Evidencia
Agregar:
- `TrainingJobArn`.
- `TransformJobArn` (si aplica) o evidencia de workaround local (`MODEL_ARTIFACT_S3_URI` + comando de inferencia local).
- `metrics.json` y `promotion_decision.json`.
- URI S3 del modelo (`ModelArtifacts.S3ModelArtifacts`) y de metricas.

## Criterio de cierre
- Training job finalizado en estado exitoso.
- Transform job exitoso o workaround local ejecutado y documentado cuando no haya quota disponible.
- Metricas de validacion generadas y publicadas en S3.
- Decision de promocion (`pass`/`fail`) documentada y trazable.

## Riesgos/pendientes
- Drift entre dataset versionado y dataset usado en entrenamiento real.
- Falta de control de sesgo o fairness en features seleccionadas.
- Ajuste de hiperparametros pendiente para mejorar `f1` sin degradar `recall`.
- Quotas de SageMaker Batch Transform pueden venir en `0` para todas las instancias en cuentas nuevas/restringidas.

## Troubleshooting rapido
1. `XGBoostError ... preds.Size() != labels.Size() (1426 vs. 713)`:
   - Causa comun: `objective=reg:logistic` y/o `num_class` definido en problema binario.
   - Corregir a `objective=binary:logistic` y remover `num_class`.
2. `AccessDenied ... s3:GetObject ... train_xgb.csv` durante training:
   - Verificar que la policy S3 este adjunta al execution role de SageMaker (no solo como permissions boundary).
3. `ResourceLimitExceeded ... for transform job usage`:
   - Ajustar `Instance count=1`, elegir instancia con quota > 0 o solicitar increase.
4. `Failed to load model ... binary format ... removed in 3.1` en inferencia local:
   - Causa: version local de XGBoost no compatible con artefacto legacy del container SageMaker.
   - Corregir ejecutando workaround con `uv run --with xgboost==2.1.4`.

## Proximo paso
Automatizar flujo con SageMaker Pipeline en `docs/tutorials/03-sagemaker-pipeline.md`.
