# 02 Training and Validation

## Objetivo y contexto
Entrenar un modelo binario (`Survived`) en SageMaker y emitir una decision objetiva
`pass/fail` usando el validation set.

Resultado minimo esperado al cerrar esta fase:
1. Un `TrainingJobArn` exitoso.
2. Predicciones sobre validation generadas por Batch Transform.
3. `metrics.json` con `accuracy`, `precision`, `recall`, `f1`.
4. `promotion_decision.json` con `pass` o `fail`.

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
1. Dataset de fase 01 cargado en S3:
   - `s3://titanic-data-bucket-939122281183-data-science-use/curated/train.csv`
   - `s3://titanic-data-bucket-939122281183-data-science-use/curated/validation.csv`
2. Perfil AWS CLI operativo: `data-science-user`.
3. Un SageMaker execution role existente con permisos a:
   - leer/escribir en el bucket del proyecto,
   - ejecutar Training/Model/Transform jobs,
   - escribir logs en CloudWatch.

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
export DATA_BUCKET=titanic-data-bucket-939122281183-data-science-use

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
   - Output path: `s3://titanic-data-bucket-939122281183-data-science-use/training/xgboost/output/`
   - Tipo de instancia: `ml.m5.large`, count `1`.
   - Hyperparameters minimos:
     - `objective=binary:logistic`
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

7. Crear modelo y Batch Transform sobre validation:
   - En el detalle del training job, crear `Model` con nombre sugerido:
     - `titanic-xgb-model-<yyyymmdd-hhmm>`
   - Crear `Batch transform job` con:
     - Nombre sugerido: `titanic-xgb-transform-<yyyymmdd-hhmm>`
     - Input: `s3://.../training/xgboost/validation_features_xgb.csv`
     - Output: `s3://titanic-data-bucket-939122281183-data-science-use/evaluation/xgboost/predictions/`
     - Content type: `text/csv`
     - Split type: `Line`
     - Instance: `ml.m5.large`
     - Tags recomendados:
       - `project=titanic-sagemaker`
       - `tutorial_phase=02`

8. Descargar predicciones y calcular metricas:

```bash
aws s3 cp \
  s3://titanic-data-bucket-939122281183-data-science-use/evaluation/xgboost/predictions/ \
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
  s3://titanic-data-bucket-939122281183-data-science-use/evaluation/xgboost/metrics.json \
  --profile "$AWS_PROFILE"

aws s3 cp data/titanic/sagemaker/promotion_decision.json \
  s3://titanic-data-bucket-939122281183-data-science-use/evaluation/xgboost/promotion_decision.json \
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
La fase 03 debe consumir exactamente estos outputs de fase 02:
1. URIs S3 de datos preparados:
   - `s3://$DATA_BUCKET/training/xgboost/train_xgb.csv`
   - `s3://$DATA_BUCKET/training/xgboost/validation_xgb.csv`
2. Regla de calidad:
   - threshold `accuracy >= 0.78`.
3. Artefactos de evidencia:
   - `evaluation/xgboost/metrics.json`
   - `evaluation/xgboost/promotion_decision.json`
4. Config base de entrenamiento validada:
   - algoritmo `XGBoost`,
   - hiperparametros base documentados en este tutorial.

## Decisiones tecnicas y alternativas descartadas
- Se estandariza un baseline reproducible con `XGBoost` de SageMaker sobre features numericas.
- El umbral de promocion de esta fase queda en `accuracy >= 0.78`.
- La evaluacion se calcula fuera del training job con Batch Transform + script local para obtener
  `accuracy`, `precision`, `recall`, `f1`.
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
- Crear training job y transform job en SageMaker Console
- `python3 scripts/evaluate_titanic_predictions.py ...`
- Resultado esperado:
  - `TrainingJobStatus=Completed`,
  - `metrics.json` generado con `accuracy`, `precision`, `recall`, `f1`,
  - `promotion_decision.json` con `pass` o `fail`.

## Evidencia
Agregar:
- `TrainingJobArn`.
- `TransformJobArn`.
- `metrics.json` y `promotion_decision.json`.
- URI S3 del modelo (`ModelArtifacts.S3ModelArtifacts`) y de metricas.

## Criterio de cierre
- Training job y transform job finalizados en estado exitoso.
- Metricas de validacion generadas y publicadas en S3.
- Decision de promocion (`pass`/`fail`) documentada y trazable.

## Riesgos/pendientes
- Drift entre dataset versionado y dataset usado en entrenamiento real.
- Falta de control de sesgo o fairness en features seleccionadas.
- Ajuste de hiperparametros pendiente para mejorar `f1` sin degradar `recall`.

## Proximo paso
Automatizar flujo con SageMaker Pipeline en `docs/tutorials/03-sagemaker-pipeline.md`.
