# 03 SageMaker Pipeline

## Objetivo y contexto

Construir y publicar un pipeline durable que procese datos, entrene, evalua `metrics.accuracy`
y registre el modelo en `titanic-survival-xgboost` solo si supera el umbral.

## Resultado minimo esperado

1. Bundle de codigo publicado en S3.
2. Definicion del pipeline creada o actualizada.
3. Ejecucion iniciada y monitorizada.
4. `ModelPackageArn` trazable en el registro.

## Prerequisitos concretos

1. Fases 00, 01 y 02 completadas.
2. Bundle IAM disponible para esta fase: `DataScienceTutorialOperator`.

## Bootstrap auto-contenido

```bash
cd "$HOME/titanic-sagemaker-tutorial"
set -a
source "$HOME/titanic-sagemaker-tutorial/.env.tutorial"
set +a
```

## Paso a paso

### 1. Crear el preprocess reutilizable

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/preprocess.py" <<'EOF'
#!/usr/bin/env python
from __future__ import annotations

import argparse
import csv
from pathlib import Path
from statistics import median

import boto3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-train-uri", required=True)
    parser.add_argument("--input-validation-uri", required=True)
    parser.add_argument("--code-bundle-uri", default="")
    return parser.parse_args()


def parse_s3_uri(uri: str) -> tuple[str, str]:
    if not uri.startswith("s3://"):
        raise ValueError(f"S3 URI invalida: {uri}")
    bucket, key = uri[5:].split("/", 1)
    return bucket, key


def download_csv(uri: str, target: Path) -> None:
    bucket, key = parse_s3_uri(uri)
    target.parent.mkdir(parents=True, exist_ok=True)
    boto3.client("s3").download_file(bucket, key, str(target))


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


def write_csv(path: Path, rows: list[list[float | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    work_dir = Path("/tmp/titanic_preprocess")
    train_input = work_dir / "train.csv"
    validation_input = work_dir / "validation.csv"
    download_csv(args.input_train_uri, train_input)
    download_csv(args.input_validation_uri, validation_input)

    train_rows = read_rows(train_input)
    validation_rows = read_rows(validation_input)
    ages = [v for v in (parse_float(r.get("Age")) for r in train_rows) if v is not None]
    fares = [v for v in (parse_float(r.get("Fare")) for r in train_rows) if v is not None]
    age_fill = float(median(ages)) if ages else 0.0
    fare_fill = float(median(fares)) if fares else 0.0

    train_payload = [[to_int(r["Survived"]), *encode_features(r, age_fill, fare_fill)] for r in train_rows]
    validation_payload = [
        [to_int(r["Survived"]), *encode_features(r, age_fill, fare_fill)] for r in validation_rows
    ]

    write_csv(Path("/opt/ml/processing/output/train/train_xgb.csv"), train_payload)
    write_csv(Path("/opt/ml/processing/output/validation/validation_xgb.csv"), validation_payload)
    print(f"prepared train={len(train_payload)} validation={len(validation_payload)}")


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/preprocess.py"
```

### 2. Crear `requirements.txt` del bundle

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/requirements.txt" <<'EOF'
xgboost==2.1.4
EOF
```

### 3. Crear el publicador del pipeline

```bash
cat > "$TUTORIAL_ROOT/mlops_assets/upsert_pipeline.py" <<'EOF'
#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import os

import boto3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--code-bundle-uri", required=True)
    parser.add_argument("--preprocess-script-uri", required=True)
    parser.add_argument("--evaluate-script-uri", required=True)
    parser.add_argument("--input-train-uri")
    parser.add_argument("--input-validation-uri")
    parser.add_argument("--accuracy-threshold", type=float)
    parser.add_argument("--definition-only", action="store_true")
    return parser.parse_args()


def env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"Falta la variable {name}")
    return value


def build_pipeline(args: argparse.Namespace):
    from sagemaker.core import image_uris, shapes
    from sagemaker.core.helper.session_helper import Session
    from sagemaker.core.model_metrics import MetricsSource, ModelMetrics
    from sagemaker.core.processing import ScriptProcessor
    from sagemaker.core.shapes import (
        ProcessingInput,
        ProcessingOutput,
        ProcessingS3Input,
        ProcessingS3Output,
    )
    from sagemaker.core.workflow import (
        ConditionGreaterThanOrEqualTo,
        Join,
        JsonGet,
        ParameterFloat,
        ParameterString,
        PropertyFile,
    )
    from sagemaker.core.workflow.pipeline_context import PipelineSession
    from sagemaker.mlops.workflow.condition_step import ConditionStep
    from sagemaker.mlops.workflow.model_step import ModelStep
    from sagemaker.mlops.workflow.pipeline import Pipeline
    from sagemaker.mlops.workflow.steps import CacheConfig, ProcessingStep, TrainingStep
    from sagemaker.serve.model_builder import ModelBuilder
    from sagemaker.train import ModelTrainer
    from sagemaker.train.configs import Compute, InputData

    boto_session = boto3.Session(
        profile_name=env("AWS_PROFILE"),
        region_name=env("AWS_REGION"),
    )
    pipeline_session = PipelineSession(
        boto_session=boto_session,
        default_bucket=env("DATA_BUCKET"),
        default_bucket_prefix="pipeline/definitions",
    )
    _ = Session(boto_session=boto_session, default_bucket=env("DATA_BUCKET"))

    input_train_uri_default = args.input_train_uri or f"s3://{env('DATA_BUCKET')}/curated/train.csv"
    input_validation_uri_default = (
        args.input_validation_uri or f"s3://{env('DATA_BUCKET')}/curated/validation.csv"
    )
    accuracy_default = (
        args.accuracy_threshold
        if args.accuracy_threshold is not None
        else float(env("ACCURACY_THRESHOLD"))
    )

    code_bundle_uri = ParameterString(name="CodeBundleUri", default_value=args.code_bundle_uri)
    input_train_uri = ParameterString(name="InputTrainUri", default_value=input_train_uri_default)
    input_validation_uri = ParameterString(
        name="InputValidationUri",
        default_value=input_validation_uri_default,
    )
    accuracy_threshold = ParameterFloat(name="AccuracyThreshold", default_value=accuracy_default)

    runtime_root = f"s3://{env('DATA_BUCKET')}/pipeline/runtime/{env('PIPELINE_NAME')}"
    cache_config = CacheConfig(enable_caching=True, expire_after="P30D")

    preprocess_processor = ScriptProcessor(
        role=env("SAGEMAKER_PIPELINE_ROLE_ARN"),
        image_uri=image_uris.retrieve(
            framework="xgboost",
            region=env("AWS_REGION"),
            version="1.7-1",
            py_version="py3",
            instance_type="ml.m5.large",
        ),
        command=["python3"],
        instance_count=1,
        instance_type="ml.m5.large",
        volume_size_in_gb=30,
        base_job_name=f"{env('PIPELINE_NAME')}-preprocess",
        sagemaker_session=pipeline_session,
    )
    preprocess_args = preprocess_processor.run(
        code=args.preprocess_script_uri,
        outputs=[
            ProcessingOutput(
                output_name="train",
                s3_output=ProcessingS3Output(
                    s3_uri=f"{runtime_root}/preprocess/train",
                    local_path="/opt/ml/processing/output/train",
                    s3_upload_mode="EndOfJob",
                ),
            ),
            ProcessingOutput(
                output_name="validation",
                s3_output=ProcessingS3Output(
                    s3_uri=f"{runtime_root}/preprocess/validation",
                    local_path="/opt/ml/processing/output/validation",
                    s3_upload_mode="EndOfJob",
                ),
            ),
        ],
        arguments=[
            "--input-train-uri",
            input_train_uri,
            "--input-validation-uri",
            input_validation_uri,
            "--code-bundle-uri",
            code_bundle_uri,
        ],
    )
    step_preprocess = ProcessingStep(
        name="DataPreProcessing",
        step_args=preprocess_args,
        cache_config=cache_config,
    )

    trainer = ModelTrainer(
        training_image=image_uris.retrieve(
            framework="xgboost",
            region=env("AWS_REGION"),
            version="1.7-1",
            py_version="py3",
            instance_type="ml.m5.large",
        ),
        compute=Compute(instance_type="ml.m5.large", instance_count=1, volume_size_in_gb=30),
        base_job_name=f"{env('PIPELINE_NAME')}-train",
        sagemaker_session=pipeline_session,
        role=env("SAGEMAKER_PIPELINE_ROLE_ARN"),
        output_data_config=shapes.OutputDataConfig(s3_output_path=f"{runtime_root}/training"),
        hyperparameters={
            "objective": "binary:logistic",
            "num_round": 200,
            "max_depth": 5,
            "eta": 0.2,
            "subsample": 0.8,
            "eval_metric": "logloss",
        },
        input_data_config=[
            InputData(
                channel_name="train",
                data_source=step_preprocess.properties.ProcessingOutputConfig.Outputs["train"].S3Output.S3Uri,
                content_type="text/csv",
            ),
            InputData(
                channel_name="validation",
                data_source=step_preprocess.properties.ProcessingOutputConfig.Outputs["validation"].S3Output.S3Uri,
                content_type="text/csv",
            ),
        ],
    )
    step_train = TrainingStep(name="TrainModel", step_args=trainer.train(), cache_config=cache_config)

    evaluation_report = PropertyFile(
        name="EvaluationReport",
        output_name="evaluation",
        path="evaluation.json",
    )
    evaluation_processor = ScriptProcessor(
        role=env("SAGEMAKER_PIPELINE_ROLE_ARN"),
        image_uri=image_uris.retrieve(
            framework="xgboost",
            region=env("AWS_REGION"),
            version="1.7-1",
            py_version="py3",
            instance_type="ml.m5.large",
        ),
        command=["python3"],
        instance_count=1,
        instance_type="ml.m5.large",
        volume_size_in_gb=30,
        base_job_name=f"{env('PIPELINE_NAME')}-evaluate",
        sagemaker_session=pipeline_session,
    )
    evaluation_args = evaluation_processor.run(
        code=args.evaluate_script_uri,
        inputs=[
            ProcessingInput(
                input_name="model",
                s3_input=ProcessingS3Input(
                    s3_uri=step_train.properties.ModelArtifacts.S3ModelArtifacts,
                    local_path="/opt/ml/processing/model",
                    s3_data_type="S3Prefix",
                    s3_input_mode="File",
                    s3_data_distribution_type="FullyReplicated",
                ),
            ),
            ProcessingInput(
                input_name="validation",
                s3_input=ProcessingS3Input(
                    s3_uri=step_preprocess.properties.ProcessingOutputConfig.Outputs["validation"].S3Output.S3Uri,
                    local_path="/opt/ml/processing/validation",
                    s3_data_type="S3Prefix",
                    s3_input_mode="File",
                    s3_data_distribution_type="FullyReplicated",
                ),
            ),
        ],
        outputs=[
            ProcessingOutput(
                output_name="evaluation",
                s3_output=ProcessingS3Output(
                    s3_uri=f"{runtime_root}/evaluation",
                    local_path="/opt/ml/processing/evaluation",
                    s3_upload_mode="EndOfJob",
                ),
            )
        ],
        arguments=[
            "--model-artifact",
            "/opt/ml/processing/model/model.tar.gz",
            "--validation",
            "/opt/ml/processing/validation/validation_xgb.csv",
            "--accuracy-threshold",
            accuracy_threshold,
            "--output",
            "/opt/ml/processing/evaluation/evaluation.json",
        ],
    )
    step_evaluation = ProcessingStep(
        name="ModelEvaluation",
        step_args=evaluation_args,
        property_files=[evaluation_report],
        cache_config=cache_config,
    )

    evaluation_report_uri = Join(
        on="/",
        values=[
            step_evaluation.properties.ProcessingOutputConfig.Outputs["evaluation"].S3Output.S3Uri,
            "evaluation.json",
        ],
    )
    model_builder = ModelBuilder(
        s3_model_data_url=step_train.properties.ModelArtifacts.S3ModelArtifacts,
        image_uri=image_uris.retrieve(
            framework="xgboost",
            region=env("AWS_REGION"),
            version="1.7-1",
            py_version="py3",
            instance_type="ml.m5.large",
        ),
        sagemaker_session=pipeline_session,
        role_arn=env("SAGEMAKER_PIPELINE_ROLE_ARN"),
    )
    register_step = ModelStep(
        name="RegisterModel-RegisterModel",
        step_args=model_builder.register(
            model_package_group_name=env("MODEL_PACKAGE_GROUP_NAME"),
            content_types=["text/csv"],
            response_types=["text/csv"],
            inference_instances=["ml.m5.large"],
            transform_instances=["ml.m5.large"],
            model_metrics=ModelMetrics(
                model_statistics=MetricsSource(
                    content_type="application/json",
                    s3_uri=evaluation_report_uri,
                )
            ),
            approval_status="PendingManualApproval",
            skip_model_validation="None",
        ),
    )
    quality_gate = ConditionStep(
        name="QualityGateAccuracy",
        conditions=[
            ConditionGreaterThanOrEqualTo(
                left=JsonGet(
                    step_name=step_evaluation.name,
                    property_file=evaluation_report,
                    json_path="metrics.accuracy",
                ),
                right=accuracy_threshold,
            )
        ],
        if_steps=[register_step],
        else_steps=[],
    )

    pipeline = Pipeline(
        name=env("PIPELINE_NAME"),
        parameters=[code_bundle_uri, input_train_uri, input_validation_uri, accuracy_threshold],
        steps=[step_preprocess, step_train, step_evaluation, quality_gate],
        sagemaker_session=pipeline_session,
    )
    return pipeline


def main() -> None:
    args = parse_args()
    pipeline = build_pipeline(args)
    if args.definition_only:
        print(pipeline.definition())
        return
    response = pipeline.upsert(role_arn=env("SAGEMAKER_PIPELINE_ROLE_ARN"))
    print(json.dumps(response, indent=2, default=str))


if __name__ == "__main__":
    main()
EOF
chmod +x "$TUTORIAL_ROOT/mlops_assets/upsert_pipeline.py"
```

### 4. Versionar y publicar el bundle de codigo

```bash
export CODE_VERSION=$(date +%Y%m%d%H%M%S)
export CODE_PREFIX="pipeline/source/$CODE_VERSION"
export CODE_BUNDLE_URI="s3://$DATA_BUCKET/$CODE_PREFIX/pipeline_code.tar.gz"
export PREPROCESS_SCRIPT_S3_URI="s3://$DATA_BUCKET/$CODE_PREFIX/source/preprocess.py"
export EVALUATE_SCRIPT_S3_URI="s3://$DATA_BUCKET/$CODE_PREFIX/source/evaluate.py"

tar -czf "$TUTORIAL_ROOT/artifacts/pipeline_code.tar.gz" \
  -C "$TUTORIAL_ROOT/mlops_assets" \
  preprocess.py \
  evaluate.py \
  requirements.txt

aws s3 cp "$TUTORIAL_ROOT/artifacts/pipeline_code.tar.gz" "$CODE_BUNDLE_URI" --profile "$AWS_PROFILE"
aws s3 cp "$TUTORIAL_ROOT/mlops_assets/preprocess.py" "$PREPROCESS_SCRIPT_S3_URI" --profile "$AWS_PROFILE"
aws s3 cp "$TUTORIAL_ROOT/mlops_assets/evaluate.py" "$EVALUATE_SCRIPT_S3_URI" --profile "$AWS_PROFILE"
```

### 5. Compilar la definicion

```bash
uv run python "$TUTORIAL_ROOT/mlops_assets/upsert_pipeline.py" \
  --code-bundle-uri "$CODE_BUNDLE_URI" \
  --preprocess-script-uri "$PREPROCESS_SCRIPT_S3_URI" \
  --evaluate-script-uri "$EVALUATE_SCRIPT_S3_URI" \
  --definition-only > "$TUTORIAL_ROOT/artifacts/titanic-pipeline-definition.json"
```

### 6. Publicar el pipeline

```bash
uv run python "$TUTORIAL_ROOT/mlops_assets/upsert_pipeline.py" \
  --code-bundle-uri "$CODE_BUNDLE_URI" \
  --preprocess-script-uri "$PREPROCESS_SCRIPT_S3_URI" \
  --evaluate-script-uri "$EVALUATE_SCRIPT_S3_URI"
```

### 7. Iniciar una ejecucion

```bash
uv run python - <<'PY'
import json
import os
from pathlib import Path

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")
response = sm_client.start_pipeline_execution(
    PipelineName=os.environ["PIPELINE_NAME"],
    PipelineParameters=[
        {"Name": "CodeBundleUri", "Value": os.environ["CODE_BUNDLE_URI"]},
        {"Name": "InputTrainUri", "Value": f"s3://{os.environ['DATA_BUCKET']}/curated/train.csv"},
        {"Name": "InputValidationUri", "Value": f"s3://{os.environ['DATA_BUCKET']}/curated/validation.csv"},
        {"Name": "AccuracyThreshold", "Value": os.environ["ACCURACY_THRESHOLD"]},
    ],
)
target = Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "pipeline_execution_arn.txt"
target.write_text(response["PipelineExecutionArn"] + "\n", encoding="utf-8")
print(json.dumps(response, indent=2))
PY
```

### 8. Monitorizar el run y localizar el ultimo package

```bash
uv run python - <<'PY'
import os
import time
from pathlib import Path

import boto3

session = boto3.Session(
    profile_name=os.environ["AWS_PROFILE"],
    region_name=os.environ["AWS_REGION"],
)
sm_client = session.client("sagemaker")
execution_arn = (Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "pipeline_execution_arn.txt").read_text(
    encoding="utf-8"
).strip()

terminal = {"Succeeded", "Failed", "Stopped"}
while True:
    desc = sm_client.describe_pipeline_execution(PipelineExecutionArn=execution_arn)
    status = desc["PipelineExecutionStatus"]
    print(f"pipeline_status={status}")
    steps = sm_client.list_pipeline_execution_steps(
        PipelineExecutionArn=execution_arn,
        SortOrder="Ascending",
    )["PipelineExecutionSteps"]
    for step in steps:
        print(f"  {step['StepName']} -> {step['StepStatus']}")
    if status in terminal:
        break
    time.sleep(30)

packages = sm_client.list_model_packages(
    ModelPackageGroupName=os.environ["MODEL_PACKAGE_GROUP_NAME"],
    SortBy="CreationTime",
    SortOrder="Descending",
    MaxResults=1,
)["ModelPackageSummaryList"]

if packages:
    latest = packages[0]["ModelPackageArn"]
    target = Path(os.environ["TUTORIAL_ROOT"]) / "artifacts" / "latest_model_package_arn.txt"
    target.write_text(latest + "\n", encoding="utf-8")
    print(f"latest_model_package_arn={latest}")
PY
```

## IAM usado

- `DataScienceTutorialOperator` para publicar codigo, crear el pipeline e iniciar runs.

## Evidencia requerida

1. `CODE_BUNDLE_URI`
2. `titanic-pipeline-definition.json`
3. `pipeline_execution_arn.txt`
4. `latest_model_package_arn.txt`

## Criterio de cierre

- Pipeline publicado.
- Run ejecutado.
- Gate de calidad evaluado.
- `ModelPackageArn` disponible para serving.

## Riesgos/pendientes

- Si no rotas `CODE_VERSION`, puedes perder trazabilidad del bundle.
- Si el pipeline falla antes del gate, no habra `ModelPackageArn` nuevo.

## Proximo paso

Continuar con [`04-serving-sagemaker.md`](/Users/jclave/Desktop/volotea/projects/titanic_sagemaker/docs/tutorials/04-serving-sagemaker.md).
