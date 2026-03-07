#!/usr/bin/env python3
"""Create or update the Titanic SageMaker pipeline without Terraform."""

from __future__ import annotations

import argparse
import json

import boto3

from resolve_project_env import build_env, load_manifest


def build_boto_session(env: dict[str, str]) -> boto3.Session:
    profile = env.get("AWS_PROFILE", "")
    region = env["AWS_REGION"]
    available_profiles = boto3.session.Session().available_profiles
    if profile and profile in available_profiles:
        return boto3.Session(profile_name=profile, region_name=region)
    return boto3.Session(region_name=region)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", help="Path to config/project-manifest.json")
    parser.add_argument("--code-bundle-uri", required=True)
    parser.add_argument("--input-train-uri")
    parser.add_argument("--input-validation-uri")
    parser.add_argument("--accuracy-threshold", type=float)
    parser.add_argument("--approval-status")
    parser.add_argument("--definition-only", action="store_true")
    return parser.parse_args()


def build_pipeline(args: argparse.Namespace):
    from sagemaker.core import shapes
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

    manifest = load_manifest(args.manifest)
    env = build_env(manifest)

    input_train_uri_default = f"s3://{env['DATA_BUCKET']}/curated/train.csv"
    input_validation_uri_default = f"s3://{env['DATA_BUCKET']}/curated/validation.csv"
    accuracy_default = (
        args.accuracy_threshold
        if args.accuracy_threshold is not None
        else float(env["QUALITY_THRESHOLD_ACCURACY"])
    )
    approval_status = args.approval_status or env["MODEL_APPROVAL_STATUS"]

    boto_session = build_boto_session(env)
    pipeline_session = PipelineSession(
        boto_session=boto_session,
        default_bucket=env["DATA_BUCKET"],
        default_bucket_prefix="pipeline/definitions",
    )
    _ = Session(boto_session=boto_session, default_bucket=env["DATA_BUCKET"])

    code_bundle_uri = ParameterString(
        name="CodeBundleUri",
        default_value=args.code_bundle_uri,
    )
    input_train_uri = ParameterString(
        name="InputTrainUri",
        default_value=args.input_train_uri or input_train_uri_default,
    )
    input_validation_uri = ParameterString(
        name="InputValidationUri",
        default_value=args.input_validation_uri or input_validation_uri_default,
    )
    accuracy_threshold = ParameterFloat(
        name="AccuracyThreshold",
        default_value=accuracy_default,
    )

    cache_config = CacheConfig(enable_caching=True, expire_after="P30D")
    preprocess_script_uri = f"s3://{env['DATA_BUCKET']}/{env['CODE_S3_PREFIX']}/scripts/preprocess.py"
    evaluate_script_uri = f"s3://{env['DATA_BUCKET']}/{env['CODE_S3_PREFIX']}/scripts/evaluate.py"
    runtime_root = f"s3://{env['DATA_BUCKET']}/{env['PIPELINE_RUNTIME_S3_PREFIX']}"

    preprocess_processor = ScriptProcessor(
        role=env["SAGEMAKER_PIPELINE_ROLE_ARN"],
        image_uri=env["PROCESSING_IMAGE_URI"],
        command=["python3"],
        instance_count=1,
        instance_type="ml.m5.large",
        volume_size_in_gb=30,
        base_job_name=f"{env['PIPELINE_NAME']}-preprocess",
        sagemaker_session=pipeline_session,
    )
    preprocess_args = preprocess_processor.run(
        code=preprocess_script_uri,
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

    model_trainer = ModelTrainer(
        training_image=env["TRAINING_IMAGE_URI"],
        compute=Compute(
            instance_type="ml.m5.large",
            instance_count=1,
            volume_size_in_gb=30,
        ),
        base_job_name=f"{env['PIPELINE_NAME']}-train",
        sagemaker_session=pipeline_session,
        role=env["SAGEMAKER_PIPELINE_ROLE_ARN"],
        output_data_config=shapes.OutputDataConfig(
            s3_output_path=f"{runtime_root}/training",
        ),
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
                data_source=step_preprocess.properties.ProcessingOutputConfig.Outputs[
                    "train"
                ].S3Output.S3Uri,
                content_type="text/csv",
            ),
            InputData(
                channel_name="validation",
                data_source=step_preprocess.properties.ProcessingOutputConfig.Outputs[
                    "validation"
                ].S3Output.S3Uri,
                content_type="text/csv",
            ),
        ],
    )
    train_args = model_trainer.train()
    step_train = TrainingStep(
        name="TrainModel",
        step_args=train_args,
        cache_config=cache_config,
    )

    evaluation_property_file = PropertyFile(
        name="EvaluationReport",
        output_name="evaluation",
        path="evaluation.json",
    )
    evaluation_processor = ScriptProcessor(
        role=env["SAGEMAKER_PIPELINE_ROLE_ARN"],
        image_uri=env["EVALUATION_IMAGE_URI"],
        command=["python3"],
        instance_count=1,
        instance_type="ml.m5.large",
        volume_size_in_gb=30,
        base_job_name=f"{env['PIPELINE_NAME']}-evaluate",
        sagemaker_session=pipeline_session,
    )
    evaluation_args = evaluation_processor.run(
        code=evaluate_script_uri,
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
                    s3_uri=step_preprocess.properties.ProcessingOutputConfig.Outputs[
                        "validation"
                    ].S3Output.S3Uri,
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
        ],
    )
    step_evaluation = ProcessingStep(
        name="ModelEvaluation",
        step_args=evaluation_args,
        property_files=[evaluation_property_file],
        cache_config=cache_config,
    )

    model_builder = ModelBuilder(
        s3_model_data_url=step_train.properties.ModelArtifacts.S3ModelArtifacts,
        image_uri=env["TRAINING_IMAGE_URI"],
        sagemaker_session=pipeline_session,
        role_arn=env["SAGEMAKER_PIPELINE_ROLE_ARN"],
    )
    evaluation_report_uri = Join(
        on="/",
        values=[
            step_evaluation.properties.ProcessingOutputConfig.Outputs["evaluation"].S3Output.S3Uri,
            "evaluation.json",
        ],
    )
    register_step = ModelStep(
        name="RegisterModel-RegisterModel",
        step_args=model_builder.register(
            model_package_group_name=env["MODEL_PACKAGE_GROUP_NAME"],
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
            approval_status=approval_status,
            skip_model_validation="None",
        ),
    )
    quality_gate = ConditionStep(
        name="QualityGateAccuracy",
        conditions=[
            ConditionGreaterThanOrEqualTo(
                left=JsonGet(
                    step_name=step_evaluation.name,
                    property_file=evaluation_property_file,
                    json_path="metrics.accuracy",
                ),
                right=accuracy_threshold,
            )
        ],
        if_steps=[register_step],
        else_steps=[],
    )

    pipeline = Pipeline(
        name=env["PIPELINE_NAME"],
        parameters=[
            code_bundle_uri,
            input_train_uri,
            input_validation_uri,
            accuracy_threshold,
        ],
        steps=[
            step_preprocess,
            step_train,
            step_evaluation,
            quality_gate,
        ],
        sagemaker_session=pipeline_session,
    )

    return pipeline, env


def main() -> None:
    args = parse_args()
    pipeline, env = build_pipeline(args)
    if args.definition_only:
        print(pipeline.definition())
        return

    response = pipeline.upsert(role_arn=env["SAGEMAKER_PIPELINE_ROLE_ARN"])
    print(json.dumps(response, indent=2, default=str))


if __name__ == "__main__":
    main()
