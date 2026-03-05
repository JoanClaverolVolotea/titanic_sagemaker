---
name: sagemaker-knowledge
description: Use when the task involves AWS SageMaker Python SDK guidance, code, APIs, or architecture decisions and answers must align with the vendored SDK documentation in vendor/sagemaker-python-sdk. Always run update-sdk first.
---

# SageMaker Knowledge

## Overview

Use this skill to ground SageMaker SDK guidance in the local vendored docs at:

- `vendor/sagemaker-python-sdk/`

This skill is documentation-first. Prefer official docs and examples from the vendored SDK over memory.

## Mandatory First Step

Before doing any SageMaker analysis in this process, run the `update-sdk` skill.

- Rule: `update-sdk` must be executed first unless it was already run in the current session and the user explicitly asked to skip refreshing.
- Purpose: keep local documentation context aligned with the latest vendored SDK snapshot.

## When to Use This Skill

Use this skill when the user asks about:

- SageMaker Python SDK classes, methods, parameters, or behavior
- Training, inference, processing, pipelines, model registry, or feature store with SageMaker SDK
- V2 to V3 migration questions
- Designing code that imports from `sagemaker.*`

## Documentation Scope (Docs Only)

Search documentation and examples only:

- `vendor/sagemaker-python-sdk/docs/`
- `vendor/sagemaker-python-sdk/docs/api/`
- `vendor/sagemaker-python-sdk/v3-examples/`
- `vendor/sagemaker-python-sdk/README.rst`
- `vendor/sagemaker-python-sdk/migration.md`

Do not rely on source or test directories as primary authority for this skill unless the user explicitly asks for source-level behavior.

## Topic to Doc Mapping

- Core/session/config/jumpstart/image URIs/serializers: `docs/sagemaker_core/`, `docs/api/sagemaker_core.rst`
- Training/fine-tuning/tuning/distributed: `docs/training/`, `docs/model_customization/`, `docs/api/sagemaker_train.rst`
- Inference/serving/model builder/batch/async: `docs/inference/`, `docs/api/sagemaker_serve.rst`
- Pipelines/feature store/mlops: `docs/ml_ops/`, `docs/api/sagemaker_mlops.rst`
- General setup/overview/migration: `docs/index.rst`, `docs/quickstart.rst`, `docs/installation.rst`, `migration.md`

## Workflow

1. Run `update-sdk` skill first.
2. Identify the SDK area (core/train/serve/mlops).
3. Search matching docs paths and API reference pages.
4. Pull supporting example(s) from `v3-examples/` when useful.
5. Answer with explicit alignment to the vendored documentation.

## Output Rules

- Do not invent API names, flags, defaults, or constraints.
- If documentation is missing or ambiguous, say so clearly.
- Prefer SageMaker SDK V3 terminology and patterns when docs indicate V3.
- Include file-path evidence from `vendor/sagemaker-python-sdk/...` in the response.

## Validation Checklist

Before finalizing an answer:

1. Confirm `update-sdk` was run first in this process.
2. Confirm at least one relevant doc path was consulted.
3. Confirm claims match the consulted docs/examples.
4. Confirm no undocumented assumptions were presented as facts.
