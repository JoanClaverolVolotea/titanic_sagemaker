# 02 Training and Validation

## Objetivo y contexto
Entrenar un baseline manual con SageMaker SDK V3 usando `ModelTrainer` y producir una
`evaluation.json` compatible con el contrato que reutiliza la fase 03.

La fase valida dataset, hiperparametros y umbral antes de automatizar el flujo con un
pipeline V3.

## Resultado minimo esperado
1. Un training job exitoso lanzado con `ModelTrainer`.
2. Un artefacto de modelo descargado localmente para evaluacion.
3. `evaluation.json` con `metrics.accuracy`, `precision`, `recall` y `f1`.
4. `promotion_decision.json` con `pass` o `fail`.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/overview.rst`
2. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
3. `vendor/sagemaker-python-sdk/docs/training/index.rst`
4. `vendor/sagemaker-python-sdk/docs/api/sagemaker_train.rst`
5. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
6. `vendor/sagemaker-python-sdk/v3-examples/training-examples/`
7. `vendor/sagemaker-python-sdk/v3-examples/inference-examples/train-inference-e2e-example.ipynb`
8. `vendor/sagemaker-python-sdk/migration.md`

## Archivos locales usados en esta fase
- `scripts/prepare_titanic_xgboost_inputs.py`
- `pipeline/code/evaluate.py`
- `data/titanic/sagemaker/`

## Prerequisitos concretos
1. Fases 00 y 01 completadas.
2. Debe existir un execution role resoluble por uno de estos caminos:
   - runtime administrado con `get_execution_role()`, o
   - variable de entorno `SAGEMAKER_EXECUTION_ROLE_ARN` exportada manualmente.
3. Perfil AWS CLI `data-science-user` operativo.
4. Ejecutar desde la raiz del repositorio.

## Estandar V3 de esta fase
- `ModelTrainer` es la interfaz canonica de training.
- `Compute`, `InputData` y `OutputDataConfig` definen la configuracion declarativa.
- `image_uris.retrieve()` resuelve la imagen del algoritmo.
- El artefacto de evaluacion reutiliza la misma estructura JSON que consumira la fase 03.

## Paso a paso (ejecucion)

### 1. Definir variables del run

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1
export DATA_BUCKET=$(terraform -chdir=terraform/00_foundations output -raw data_bucket_name)

export TRAIN_RAW_S3_URI=s3://$DATA_BUCKET/curated/train.csv
export VALIDATION_RAW_S3_URI=s3://$DATA_BUCKET/curated/validation.csv

export TRAIN_XGB_S3_URI=s3://$DATA_BUCKET/training/xgboost/train_xgb.csv
export VALIDATION_XGB_S3_URI=s3://$DATA_BUCKET/training/xgboost/validation_xgb.csv
```

### 2. Resolver el execution role para el tutorial

Si no estas dentro de un runtime administrado por SageMaker, deja el role listo antes de
ejecutar los snippets Python:

```bash
if [ -z "${SAGEMAKER_EXECUTION_ROLE_ARN:-}" ] && [ -d terraform/03_sagemaker_pipeline ]; then
  export SAGEMAKER_EXECUTION_ROLE_ARN=$(terraform -chdir=terraform/03_sagemaker_pipeline output -raw pipeline_execution_role_arn 2>/dev/null || true)
fi

echo "SAGEMAKER_EXECUTION_ROLE_ARN=${SAGEMAKER_EXECUTION_ROLE_ARN:-<pendiente>}"
```

### 3. Preparar los CSV numericos para XGBoost

```bash
python3 scripts/prepare_titanic_xgboost_inputs.py
wc -l data/titanic/sagemaker/train_xgb.csv data/titanic/sagemaker/validation_xgb.csv
```

### 4. Subir los CSV preparados a S3

```bash
aws s3 cp data/titanic/sagemaker/train_xgb.csv "$TRAIN_XGB_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp data/titanic/sagemaker/validation_xgb.csv "$VALIDATION_XGB_S3_URI" --profile "$AWS_PROFILE"
```

### 5. Lanzar training job con `ModelTrainer`

```python
import os
from pathlib import Path

import boto3
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.core import image_uris
from sagemaker.train import ModelTrainer
from sagemaker.train.configs import Compute, InputData, OutputDataConfig

AWS_PROFILE = os.getenv("AWS_PROFILE", "data-science-user")
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
DATA_BUCKET = os.environ["DATA_BUCKET"]

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
session = Session(boto_session=boto_session)

try:
    role_arn = get_execution_role()
except Exception:
    role_arn = os.environ["SAGEMAKER_EXECUTION_ROLE_ARN"]

xgb_image_uri = image_uris.retrieve(
    framework="xgboost",
    region=AWS_REGION,
    version="1.7-1",
    py_version="py3",
    instance_type="ml.m5.large",
)

model_trainer = ModelTrainer(
    training_image=xgb_image_uri,
    role=role_arn,
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

training_job = model_trainer.train(wait=True, logs=True)
Path("data/titanic/sagemaker/training_job_name.txt").write_text(
    training_job.name + "\n",
    encoding="utf-8",
)
print(f"Training job: {training_job.name}")
```

### 6. Descargar el artefacto del modelo para evaluacion local

```python
import os
from pathlib import Path

import boto3

AWS_PROFILE = os.getenv("AWS_PROFILE", "data-science-user")
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
TRAINING_JOB_NAME = os.getenv("TRAINING_JOB_NAME") or Path(
    "data/titanic/sagemaker/training_job_name.txt"
).read_text(encoding="utf-8").strip()

boto_session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
sm_client = boto_session.client("sagemaker")
s3_client = boto_session.client("s3")

job_desc = sm_client.describe_training_job(TrainingJobName=TRAINING_JOB_NAME)
model_artifact_s3_uri = job_desc["ModelArtifacts"]["S3ModelArtifacts"]
print(f"Model artifact: {model_artifact_s3_uri}")

bucket, key = model_artifact_s3_uri.replace("s3://", "", 1).split("/", 1)
output_path = Path("data/titanic/sagemaker/model/model.tar.gz")
output_path.parent.mkdir(parents=True, exist_ok=True)
s3_client.download_file(bucket, key, str(output_path))
print(f"Downloaded to {output_path}")
```

### 7. Evaluar el modelo con el mismo contrato JSON de la fase 03

```bash
uv run --with xgboost==2.1.4 python pipeline/code/evaluate.py \
  --model-artifact data/titanic/sagemaker/model/model.tar.gz \
  --validation data/titanic/sagemaker/validation_xgb.csv \
  --accuracy-threshold 0.78 \
  --output data/titanic/sagemaker/evaluation.json
```

### 8. Emitir decision de promocion

```bash
python3 - <<'PY'
import json
from pathlib import Path

evaluation = json.loads(Path("data/titanic/sagemaker/evaluation.json").read_text(encoding="utf-8"))
accuracy = evaluation["metrics"]["accuracy"]
threshold = evaluation["thresholds"]["accuracy_threshold"]
decision = "pass" if evaluation["thresholds"]["passed"] else "fail"

payload = {
    "threshold_accuracy": threshold,
    "observed_accuracy": accuracy,
    "decision": decision,
}
Path("data/titanic/sagemaker/promotion_decision.json").write_text(
    json.dumps(payload, indent=2) + "\n",
    encoding="utf-8",
)
print(json.dumps(payload, indent=2))
PY
```

### 9. Publicar la evidencia en S3

```bash
aws s3 cp data/titanic/sagemaker/evaluation.json \
  s3://$DATA_BUCKET/evaluation/xgboost/evaluation.json \
  --profile "$AWS_PROFILE"

aws s3 cp data/titanic/sagemaker/promotion_decision.json \
  s3://$DATA_BUCKET/evaluation/xgboost/promotion_decision.json \
  --profile "$AWS_PROFILE"
```

## Handoff explicito a fase 03
1. El umbral reutilizable es `accuracy >= 0.78`.
2. El contrato JSON reutilizable es `evaluation.json` con la ruta `metrics.accuracy`.
3. La imagen y los hiperparametros baseline quedan validados para el pipeline V3.
4. La fase 03 debe registrar el modelo solo si el gate de calidad pasa.

## Decisiones tecnicas y alternativas descartadas
- `ModelTrainer` se usa como API primaria de training en vez de patrones V2.
- La evaluacion manual reutiliza `pipeline/code/evaluate.py` para mantener el mismo contrato
  que consumira el pipeline.
- Se elimina el flujo de Batch Transform como paso obligatorio de esta fase porque no es
  necesario para validar el contrato V3 del proyecto.
- Se evita leer atributos privados del trainer como mecanismo principal de control.

## IAM usado (roles/policies/permisos clave)
- Perfil operativo: `data-science-user`.
- Managed policies del operador para esta fase:
  `DataScienceObservabilityReadOnly`, `DataSciencePassroleRestricted`,
  `DataSciences3DataAccess`, `DataScienceSageMakerTrainingJobLifecycle` y
  `DataScienceSageMakerAuthoringRuntime`.
- Execution role de SageMaker con permisos para training, lectura/escritura en S3 y logs.

## Evidencia
Agregar:
- `TrainingJobName`.
- `ModelArtifacts.S3ModelArtifacts`.
- `data/titanic/sagemaker/evaluation.json`.
- `data/titanic/sagemaker/promotion_decision.json`.

## Criterio de cierre
- Training job lanzado con `ModelTrainer` y completado correctamente.
- Artefacto del modelo descargado para evaluacion.
- `evaluation.json` y `promotion_decision.json` generados y publicados en S3.
- Queda definido el umbral para el pipeline de la fase 03.

## Riesgos/pendientes
- Sin `SAGEMAKER_EXECUTION_ROLE_ARN` la fase no es ejecutable fuera de un runtime gestionado.
- Si cambia la forma de `evaluation.json`, el gate de la fase 03 dejara de funcionar.
- La dependencia local de `xgboost` para evaluacion debe mantenerse compatible con el
  artefacto generado por el entrenamiento.

## Proximo paso
Automatizar el flujo con un pipeline V3 en `docs/tutorials/03-sagemaker-pipeline.md`.
