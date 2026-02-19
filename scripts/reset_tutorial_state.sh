#!/usr/bin/env bash
set -euo pipefail

TARGET=""
DRY_RUN=1
APPLY=0
CONFIRM_VALUE=""

AWS_PROFILE="${AWS_PROFILE:-data-science-user}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
DATA_BUCKET="${DATA_BUCKET:-titanic-data-bucket-939122281183-data-science-user}"
PROJECT_TAG="${PROJECT_TAG:-titanic-sagemaker}"
NAME_PREFIX="${NAME_PREFIX:-titanic-}"
PHASE2_PREFIX="${PHASE2_PREFIX:-titanic-xgb-}"
VERBOSE=0

DELETED=()
SKIPPED=()
WARNINGS=()

TRAINING_JOBS=()
TRANSFORM_JOBS=()
MODELS=()
ENDPOINTS=()
ENDPOINT_CONFIGS=()
PIPELINES=()
MODEL_PACKAGES=()
MODEL_PACKAGE_GROUPS=()

usage() {
  cat <<'EOF'
Usage:
  scripts/reset_tutorial_state.sh --target after-tutorial-2|all [options]

Targets:
  after-tutorial-2   Limpia artefactos y recursos generados por la fase 02.
  all                Limpia recursos del tutorial (SageMaker + S3 prefixes), conserva IAM y bucket.

Safety defaults:
  --dry-run está activo por defecto.
  Para ejecutar borrado real, usar: --apply --confirm RESET

Options:
  --target <value>            Required: after-tutorial-2 | all
  --dry-run                   Plan de borrado (default)
  --apply                     Ejecuta cambios (requiere --confirm RESET)
  --confirm <value>           Debe ser RESET cuando se usa --apply
  --profile <name>            AWS profile (default: data-science-user)
  --region <name>             AWS region (default: eu-west-1)
  --bucket <name>             S3 bucket tutorial (default: titanic-data-bucket-939122281183-data-science-user)
  --project-tag <value>       Tag value para key project (default: titanic-sagemaker)
  --name-prefix <value>       Prefijo fallback de nombres (default: titanic-)
  --verbose                   Logs detallados
  -h, --help                  Show this help

Examples:
  scripts/reset_tutorial_state.sh --target after-tutorial-2
  scripts/reset_tutorial_state.sh --target after-tutorial-2 --apply --confirm RESET
  scripts/reset_tutorial_state.sh --target all --apply --confirm RESET
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

debug() {
  if (( VERBOSE )); then
    printf '[DEBUG] %s\n' "$*"
  fi
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
  WARNINGS+=("$*")
}

fatal() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

aws_cmd() {
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" "$@"
}

record_deleted() {
  DELETED+=("$*")
}

record_skipped() {
  SKIPPED+=("$*")
}

text_to_lines() {
  tr '\t' '\n' | sed '/^[[:space:]]*$/d'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        TARGET="${2:-}"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        APPLY=0
        ;;
      --apply)
        APPLY=1
        DRY_RUN=0
        ;;
      --confirm)
        CONFIRM_VALUE="${2:-}"
        shift
        ;;
      --profile)
        AWS_PROFILE="${2:-}"
        shift
        ;;
      --region)
        AWS_REGION="${2:-}"
        shift
        ;;
      --bucket)
        DATA_BUCKET="${2:-}"
        shift
        ;;
      --project-tag)
        PROJECT_TAG="${2:-}"
        shift
        ;;
      --name-prefix)
        NAME_PREFIX="${2:-}"
        shift
        ;;
      --verbose)
        VERBOSE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        fatal "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

validate_inputs() {
  [[ -n "${TARGET}" ]] || fatal "--target is required."
  [[ "${TARGET}" == "after-tutorial-2" || "${TARGET}" == "all" ]] || fatal "--target must be after-tutorial-2 or all."

  if (( APPLY )); then
    [[ "${CONFIRM_VALUE}" == "RESET" ]] || fatal "--apply requires --confirm RESET."
  fi

  [[ "${AWS_PROFILE}" == "data-science-user" ]] || fatal "AWS profile must be data-science-user. Current: ${AWS_PROFILE}"
  command -v aws >/dev/null 2>&1 || fatal "aws CLI not found."
}

validate_aws_context() {
  local account arn
  account="$(aws_cmd sts get-caller-identity --query 'Account' --output text 2>/dev/null || true)"
  arn="$(aws_cmd sts get-caller-identity --query 'Arn' --output text 2>/dev/null || true)"
  [[ -n "${account}" && "${account}" != "None" ]] || fatal "Unable to resolve AWS caller identity. Check profile ${AWS_PROFILE}."
  log "AWS caller: ${arn}"
  log "AWS account: ${account}"
}

resource_has_project_tag() {
  local arn="$1"
  local count
  if ! count="$(aws_cmd sagemaker list-tags \
      --resource-arn "${arn}" \
      --query "length(Tags[?Key=='project' && Value=='${PROJECT_TAG}'])" \
      --output text 2>/dev/null)"; then
    warn "No se pudo leer tags de ${arn}; se usará fallback por prefijo."
    echo "unknown"
    return
  fi
  if [[ "${count}" == "None" || "${count}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

match_name_for_after_tutorial_2() {
  local name="$1"
  [[ "${name}" == "${PHASE2_PREFIX}"* ]]
}

match_name_for_all() {
  local name="$1"
  [[ "${name}" == "${NAME_PREFIX}"* ]]
}

should_include_named_resource() {
  local name="$1"
  local arn="${2:-}"
  local tag_state="no"

  if [[ -n "${arn}" && "${arn}" != "None" ]]; then
    tag_state="$(resource_has_project_tag "${arn}")"
  fi

  if [[ "${TARGET}" == "after-tutorial-2" ]]; then
    if match_name_for_after_tutorial_2 "${name}"; then
      echo "prefix:${PHASE2_PREFIX}"
      return 0
    fi
    if [[ "${tag_state}" == "yes" && "${name}" == *xgb* ]]; then
      echo "tag:project=${PROJECT_TAG}+pattern:xgb"
      return 0
    fi
    return 1
  fi

  if [[ "${tag_state}" == "yes" ]]; then
    echo "tag:project=${PROJECT_TAG}"
    return 0
  fi
  if match_name_for_all "${name}"; then
    echo "prefix:${NAME_PREFIX}"
    return 0
  fi
  return 1
}

should_include_model_package_arn() {
  local arn="$1"
  local tag_state="no"

  tag_state="$(resource_has_project_tag "${arn}")"
  if [[ "${tag_state}" == "yes" ]]; then
    echo "tag:project=${PROJECT_TAG}"
    return 0
  fi
  if [[ "${arn}" == *"${NAME_PREFIX}"* ]]; then
    echo "arn-contains:${NAME_PREFIX}"
    return 0
  fi
  return 1
}

discover_training_jobs() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-training-job --training-job-name "${name}" --query 'TrainingJobArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      TRAINING_JOBS+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-training-jobs --max-results 100 --query 'TrainingJobSummaries[].TrainingJobName' --output text 2>/dev/null | text_to_lines || true)
}

discover_transform_jobs() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-transform-job --transform-job-name "${name}" --query 'TransformJobArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      TRANSFORM_JOBS+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-transform-jobs --max-results 100 --query 'TransformJobSummaries[].TransformJobName' --output text 2>/dev/null | text_to_lines || true)
}

discover_models() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-model --model-name "${name}" --query 'ModelArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      MODELS+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-models --max-results 100 --query 'Models[].ModelName' --output text 2>/dev/null | text_to_lines || true)
}

discover_endpoints() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-endpoint --endpoint-name "${name}" --query 'EndpointArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      ENDPOINTS+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-endpoints --max-results 100 --query 'Endpoints[].EndpointName' --output text 2>/dev/null | text_to_lines || true)
}

discover_endpoint_configs() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-endpoint-config --endpoint-config-name "${name}" --query 'EndpointConfigArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      ENDPOINT_CONFIGS+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-endpoint-configs --max-results 100 --query 'EndpointConfigs[].EndpointConfigName' --output text 2>/dev/null | text_to_lines || true)
}

discover_pipelines() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-pipeline --pipeline-name "${name}" --query 'PipelineArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      PIPELINES+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-pipelines --max-results 100 --query 'PipelineSummaries[].PipelineName' --output text 2>/dev/null | text_to_lines || true)
}

discover_model_package_groups() {
  local name arn reason
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-model-package-group --model-package-group-name "${name}" --query 'ModelPackageGroupArn' --output text 2>/dev/null || true)"
    if reason="$(should_include_named_resource "${name}" "${arn}")"; then
      MODEL_PACKAGE_GROUPS+=("${name}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-model-package-groups --max-results 100 --query 'ModelPackageGroupSummaryList[].ModelPackageGroupName' --output text 2>/dev/null | text_to_lines || true)
}

discover_model_packages() {
  local arn reason
  while IFS= read -r arn; do
    [[ -n "${arn}" ]] || continue
    if reason="$(should_include_model_package_arn "${arn}")"; then
      MODEL_PACKAGES+=("${arn}|${reason}")
    fi
  done < <(aws_cmd sagemaker list-model-packages --max-results 100 --query 'ModelPackageSummaryList[].ModelPackageArn' --output text 2>/dev/null | text_to_lines || true)
}

discover_resources() {
  log "Discovering resources for target=${TARGET} (hybrid: tag+prefix)..."
  discover_training_jobs
  discover_transform_jobs
  discover_models

  if [[ "${TARGET}" == "all" ]]; then
    discover_endpoints
    discover_endpoint_configs
    discover_pipelines
    discover_model_package_groups
    discover_model_packages
  fi
}

print_snapshot() {
  printf '\n=== Snapshot ===\n'
  printf 'Target: %s\n' "${TARGET}"
  printf 'Mode: %s\n' "$([[ "${DRY_RUN}" -eq 1 ]] && echo "dry-run" || echo "apply")"
  printf 'Bucket: %s\n' "${DATA_BUCKET}"
  printf 'Profile/Region: %s / %s\n' "${AWS_PROFILE}" "${AWS_REGION}"
  printf '\n'

  printf 'Training jobs: %s\n' "${#TRAINING_JOBS[@]}"
  printf 'Transform jobs: %s\n' "${#TRANSFORM_JOBS[@]}"
  printf 'Models: %s\n' "${#MODELS[@]}"
  printf 'Endpoints: %s\n' "${#ENDPOINTS[@]}"
  printf 'Endpoint configs: %s\n' "${#ENDPOINT_CONFIGS[@]}"
  printf 'Pipelines: %s\n' "${#PIPELINES[@]}"
  printf 'Model packages: %s\n' "${#MODEL_PACKAGES[@]}"
  printf 'Model package groups: %s\n' "${#MODEL_PACKAGE_GROUPS[@]}"
}

perform_action() {
  local description="$1"
  shift
  if (( DRY_RUN )); then
    debug "DRY-RUN -> ${description}"
    record_skipped "[dry-run] ${description}"
    return 0
  fi

  if "$@"; then
    record_deleted "${description}"
  else
    warn "Failed action: ${description}"
    return 0
  fi
}

stop_and_delete_training_jobs() {
  local entry name status
  for entry in "${TRAINING_JOBS[@]}"; do
    name="${entry%%|*}"
    status="$(aws_cmd sagemaker describe-training-job --training-job-name "${name}" --query 'TrainingJobStatus' --output text 2>/dev/null || true)"
    if [[ "${status}" == "InProgress" || "${status}" == "Stopping" ]]; then
      perform_action "stop training job ${name}" aws_cmd sagemaker stop-training-job --training-job-name "${name}"
    fi
    perform_action "delete training job ${name}" aws_cmd sagemaker delete-training-job --training-job-name "${name}"
  done
}

stop_transform_jobs_with_warning() {
  local entry name status
  for entry in "${TRANSFORM_JOBS[@]}"; do
    name="${entry%%|*}"
    status="$(aws_cmd sagemaker describe-transform-job --transform-job-name "${name}" --query 'TransformJobStatus' --output text 2>/dev/null || true)"
    if [[ "${status}" == "InProgress" || "${status}" == "Stopping" ]]; then
      perform_action "stop transform job ${name}" aws_cmd sagemaker stop-transform-job --transform-job-name "${name}"
    fi
    record_skipped "transform job ${name} (SageMaker no expone delete-transform-job API)"
  done
}

delete_endpoints_and_configs() {
  local entry name
  for entry in "${ENDPOINTS[@]}"; do
    name="${entry%%|*}"
    perform_action "delete endpoint ${name}" aws_cmd sagemaker delete-endpoint --endpoint-name "${name}"
  done
  for entry in "${ENDPOINT_CONFIGS[@]}"; do
    name="${entry%%|*}"
    perform_action "delete endpoint config ${name}" aws_cmd sagemaker delete-endpoint-config --endpoint-config-name "${name}"
  done
}

delete_models() {
  local entry name
  for entry in "${MODELS[@]}"; do
    name="${entry%%|*}"
    perform_action "delete model ${name}" aws_cmd sagemaker delete-model --model-name "${name}"
  done
}

delete_registry_and_pipelines() {
  local entry name arn
  for entry in "${MODEL_PACKAGES[@]}"; do
    arn="${entry%%|*}"
    perform_action "delete model package ${arn}" aws_cmd sagemaker delete-model-package --model-package-name "${arn}"
  done
  for entry in "${MODEL_PACKAGE_GROUPS[@]}"; do
    name="${entry%%|*}"
    perform_action "delete model package group ${name}" aws_cmd sagemaker delete-model-package-group --model-package-group-name "${name}"
  done
  for entry in "${PIPELINES[@]}"; do
    name="${entry%%|*}"
    perform_action "delete pipeline ${name}" aws_cmd sagemaker delete-pipeline --pipeline-name "${name}"
  done
}

cleanup_s3_prefixes() {
  local prefixes=()
  local prefix
  if [[ "${TARGET}" == "after-tutorial-2" ]]; then
    prefixes=("training/xgboost/" "evaluation/xgboost/")
  else
    prefixes=("raw/" "curated/" "training/" "evaluation/")
  fi

  for prefix in "${prefixes[@]}"; do
    perform_action "delete s3://$DATA_BUCKET/${prefix}" aws_cmd s3 rm "s3://${DATA_BUCKET}/${prefix}" --recursive
  done
}

cleanup_local_artifacts() {
  local local_dir="data/titanic/sagemaker"
  if (( DRY_RUN )); then
    record_skipped "[dry-run] delete local ${local_dir}"
    return
  fi
  if [[ -d "${local_dir}" ]]; then
    rm -rf "${local_dir}"
    record_deleted "delete local ${local_dir}"
  else
    record_skipped "local ${local_dir} not present"
  fi
}

print_final_report() {
  local item
  printf '\n=== Deleted ===\n'
  if [[ ${#DELETED[@]} -eq 0 ]]; then
    printf '(none)\n'
  else
    for item in "${DELETED[@]}"; do
      printf '%s\n' "- ${item}"
    done
  fi

  printf '\n=== Skipped ===\n'
  if [[ ${#SKIPPED[@]} -eq 0 ]]; then
    printf '(none)\n'
  else
    for item in "${SKIPPED[@]}"; do
      printf '%s\n' "- ${item}"
    done
  fi

  printf '\n=== Warnings ===\n'
  if [[ ${#WARNINGS[@]} -eq 0 ]]; then
    printf '(none)\n'
  else
    for item in "${WARNINGS[@]}"; do
      printf '%s\n' "- ${item}"
    done
  fi
}

run_cleanup() {
  # Order: snapshot -> stop -> dependents -> registry/pipeline -> s3 -> local -> report
  stop_and_delete_training_jobs
  stop_transform_jobs_with_warning

  if [[ "${TARGET}" == "all" ]]; then
    delete_endpoints_and_configs
  fi

  delete_models

  if [[ "${TARGET}" == "all" ]]; then
    delete_registry_and_pipelines
  fi

  cleanup_s3_prefixes
  cleanup_local_artifacts
}

main() {
  export AWS_PAGER=""

  parse_args "$@"
  validate_inputs
  validate_aws_context

  discover_resources
  print_snapshot

  run_cleanup
  print_final_report

  if (( DRY_RUN )); then
    log "Dry-run complete. Re-run with --apply --confirm RESET to execute."
  else
    log "Apply complete."
  fi
}

main "$@"
