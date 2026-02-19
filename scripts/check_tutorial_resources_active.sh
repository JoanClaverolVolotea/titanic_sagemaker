#!/usr/bin/env bash
set -euo pipefail

PHASE="all"
AWS_PROFILE="${AWS_PROFILE:-data-science-user}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
PROJECT_TAG="${PROJECT_TAG:-titanic-sagemaker}"
NAME_PREFIX="${NAME_PREFIX:-titanic-}"
DATA_BUCKET="${DATA_BUCKET:-titanic-data-bucket-939122281183-data-science-use}"
FAIL_IF_ACTIVE=0

ACCOUNT_ID=""

WARNINGS=()
RESULTS=()
INCLUDED_SERVICES=()

TOTAL_ACTIVE=0
TOTAL_INACTIVE=0
TOTAL_UNKNOWN=0

# shellcheck disable=SC2034
SERVICE_ORDER=(s3 sagemaker ecs lambda stepfunctions eventbridge scheduler cloudwatch ecr ec2 budgets)

declare -A SERVICE_ACTIVE=()
declare -A SERVICE_INACTIVE=()
declare -A SERVICE_UNKNOWN=()

declare -A PHASE_SERVICES=(
  [00]="s3 budgets"
  [01]="s3"
  [02]="s3 sagemaker"
  [03]="sagemaker stepfunctions eventbridge scheduler lambda"
  [04]="sagemaker ecs ecr"
  [05]="sagemaker ecs ecr stepfunctions lambda eventbridge scheduler"
  [06]="cloudwatch sagemaker stepfunctions lambda ecs"
  [07]="budgets scheduler eventbridge cloudwatch sagemaker ecs ec2"
  [all]="s3 sagemaker ecs lambda stepfunctions eventbridge scheduler cloudwatch ecr ec2 budgets"
)

usage() {
  cat <<'USAGE'
Usage:
  scripts/check_tutorial_resources_active.sh [options]

Options:
  --phase <all|00|01|02|03|04|05|06|07>  Fase a verificar (default: all)
  --profile <name>                         AWS profile (default: data-science-user)
  --region <name>                          AWS region (default: eu-west-1)
  --project-tag <value>                    Valor del tag project (default: titanic-sagemaker)
  --name-prefix <value>                    Prefijo fallback de nombres (default: titanic-)
  --bucket <name>                          Bucket S3 principal del tutorial
  --fail-if-active                         Exit code 2 si detecta recursos activos
  -h, --help                               Show this help

Comportamiento:
- Script de solo lectura.
- Perfil obligatorio: data-science-user.
- Filtro de recursos: tag project=<project-tag> y fallback por prefijo.
- Si faltan permisos en un servicio, reporta warning y marca estado unknown.

Examples:
  scripts/check_tutorial_resources_active.sh --phase all
  scripts/check_tutorial_resources_active.sh --phase 04 --fail-if-active
  scripts/check_tutorial_resources_active.sh --project-tag titanic-sagemaker --name-prefix titanic-
USAGE
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
  WARNINGS+=("$*")
}

fatal() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

text_to_lines() {
  tr '\t' '\n' | sed '/^[[:space:]]*$/d'
}

aws_cmd() {
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" "$@"
}

init_counters() {
  local service
  for service in "${INCLUDED_SERVICES[@]}"; do
    SERVICE_ACTIVE["${service}"]=0
    SERVICE_INACTIVE["${service}"]=0
    SERVICE_UNKNOWN["${service}"]=0
  done
}

add_result() {
  local service="$1"
  local resource="$2"
  local status="$3"
  local detail="$4"

  RESULTS+=("${service}|${resource}|${status}|${detail}")

  case "${status}" in
    active)
      SERVICE_ACTIVE["${service}"]=$(( SERVICE_ACTIVE["${service}"] + 1 ))
      TOTAL_ACTIVE=$(( TOTAL_ACTIVE + 1 ))
      ;;
    inactive)
      SERVICE_INACTIVE["${service}"]=$(( SERVICE_INACTIVE["${service}"] + 1 ))
      TOTAL_INACTIVE=$(( TOTAL_INACTIVE + 1 ))
      ;;
    unknown)
      SERVICE_UNKNOWN["${service}"]=$(( SERVICE_UNKNOWN["${service}"] + 1 ))
      TOTAL_UNKNOWN=$(( TOTAL_UNKNOWN + 1 ))
      ;;
    *)
      warn "Unknown status ${status} for ${service}:${resource}"
      ;;
  esac
}

run_aws_text() {
  # run_aws_text <__outvar> <description> <aws-args...>
  local __outvar="$1"
  local description="$2"
  shift 2

  local output
  if ! output="$(aws_cmd "$@" 2>&1)"; then
    warn "${description}: ${output//$'\n'/ }"
    printf -v "${__outvar}" '%s' ""
    return 1
  fi

  printf -v "${__outvar}" '%s' "${output}"
  return 0
}

has_project_tag_sagemaker() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd sagemaker list-tags --resource-arn "${arn}" --query "length(Tags[?Key=='project' && Value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_ecs() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd ecs list-tags-for-resource --resource-arn "${arn}" --query "length(tags[?key=='project' && value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_lambda() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd lambda list-tags --resource "${arn}" --query "Tags.project" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "${PROJECT_TAG}" ]]; then
    echo "yes"
  elif [[ "${out}" == "None" ]]; then
    echo "no"
  else
    echo "no"
  fi
}

has_project_tag_stepfunctions() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd stepfunctions list-tags-for-resource --resource-arn "${arn}" --query "length(tags[?key=='project' && value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_eventbridge() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd events list-tags-for-resource --resource-arn "${arn}" --query "length(Tags[?Key=='project' && Value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_scheduler() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd scheduler list-tags-for-resource --resource-arn "${arn}" --query "length(Tags[?Key=='project' && Value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_cloudwatch_alarm() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd cloudwatch list-tags-for-resource --resource-arn "${arn}" --query "length(Tags[?Key=='project' && Value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_log_group() {
  local log_group="$1"
  local out
  if ! out="$(aws_cmd logs list-tags-log-group --log-group-name "${log_group}" --query "tags.project" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "${PROJECT_TAG}" ]]; then
    echo "yes"
  elif [[ "${out}" == "None" ]]; then
    echo "no"
  else
    echo "no"
  fi
}

has_project_tag_ecr() {
  local arn="$1"
  local out
  if ! out="$(aws_cmd ecr list-tags-for-resource --resource-arn "${arn}" --query "length(tags[?Key=='project' && Value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

has_project_tag_s3_bucket() {
  local bucket="$1"
  local out
  if ! out="$(aws_cmd s3api get-bucket-tagging --bucket "${bucket}" --query "length(TagSet[?Key=='project' && Value=='${PROJECT_TAG}'])" --output text 2>/dev/null)"; then
    echo "unknown"
    return
  fi
  if [[ "${out}" == "None" || "${out}" == "0" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

matches_name_or_tag() {
  # matches_name_or_tag <name> <tag_state>
  local name="$1"
  local tag_state="$2"

  if [[ "${name}" == "${NAME_PREFIX}"* ]]; then
    echo "prefix:${NAME_PREFIX}"
    return 0
  fi

  if [[ "${tag_state}" == "yes" ]]; then
    echo "tag:project=${PROJECT_TAG}"
    return 0
  fi

  return 1
}

check_s3() {
  local bucket_exists=0
  local bucket_tag_state="unknown"

  if aws_cmd s3api head-bucket --bucket "${DATA_BUCKET}" >/dev/null 2>&1; then
    bucket_exists=1
    bucket_tag_state="$(has_project_tag_s3_bucket "${DATA_BUCKET}")"
    add_result "s3" "bucket:${DATA_BUCKET}" "active" "exists; tag=${bucket_tag_state}"
  else
    add_result "s3" "bucket:${DATA_BUCKET}" "inactive" "not found or not accessible"
  fi

  local prefixes=("raw/" "curated/" "training/" "evaluation/" "training/xgboost/" "evaluation/xgboost/")
  local prefix out

  for prefix in "${prefixes[@]}"; do
    if (( bucket_exists == 0 )); then
      add_result "s3" "s3://${DATA_BUCKET}/${prefix}" "unknown" "bucket unavailable"
      continue
    fi

    if run_aws_text out "s3 list objects ${prefix}" s3api list-objects-v2 --bucket "${DATA_BUCKET}" --prefix "${prefix}" --max-keys 1 --query 'Contents[0].Key' --output text; then
      if [[ "${out}" == "None" || -z "${out}" ]]; then
        add_result "s3" "s3://${DATA_BUCKET}/${prefix}" "inactive" "no objects"
      else
        add_result "s3" "s3://${DATA_BUCKET}/${prefix}" "active" "objects present"
      fi
    else
      add_result "s3" "s3://${DATA_BUCKET}/${prefix}" "unknown" "permission or API error"
    fi
  done
}

check_sagemaker_training_jobs() {
  local names name arn tag_state reason status
  if ! run_aws_text names "sagemaker list training jobs" sagemaker list-training-jobs --max-results 100 --query 'TrainingJobSummaries[].TrainingJobName' --output text; then
    add_result "sagemaker" "training-jobs" "unknown" "cannot list training jobs"
    return
  fi

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-training-job --training-job-name "${name}" --query 'TrainingJobArn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_sagemaker "${arn}")"
    fi
    if reason="$(matches_name_or_tag "${name}" "${tag_state}")"; then
      status="$(aws_cmd sagemaker describe-training-job --training-job-name "${name}" --query 'TrainingJobStatus' --output text 2>/dev/null || echo "unknown")"
      case "${status}" in
        InProgress|Stopping)
          add_result "sagemaker" "training-job:${name}" "active" "status=${status}; ${reason}"
          ;;
        Completed|Stopped|Failed)
          add_result "sagemaker" "training-job:${name}" "inactive" "status=${status}; ${reason}"
          ;;
        *)
          add_result "sagemaker" "training-job:${name}" "unknown" "status=${status}; ${reason}"
          ;;
      esac
    fi
  done < <(printf '%s' "${names}" | text_to_lines)
}

check_sagemaker_transform_jobs() {
  local names name arn tag_state reason status
  if ! run_aws_text names "sagemaker list transform jobs" sagemaker list-transform-jobs --max-results 100 --query 'TransformJobSummaries[].TransformJobName' --output text; then
    add_result "sagemaker" "transform-jobs" "unknown" "cannot list transform jobs"
    return
  fi

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-transform-job --transform-job-name "${name}" --query 'TransformJobArn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_sagemaker "${arn}")"
    fi
    if reason="$(matches_name_or_tag "${name}" "${tag_state}")"; then
      status="$(aws_cmd sagemaker describe-transform-job --transform-job-name "${name}" --query 'TransformJobStatus' --output text 2>/dev/null || echo "unknown")"
      case "${status}" in
        InProgress|Stopping)
          add_result "sagemaker" "transform-job:${name}" "active" "status=${status}; ${reason}"
          ;;
        Completed|Stopped|Failed)
          add_result "sagemaker" "transform-job:${name}" "inactive" "status=${status}; ${reason}"
          ;;
        *)
          add_result "sagemaker" "transform-job:${name}" "unknown" "status=${status}; ${reason}"
          ;;
      esac
    fi
  done < <(printf '%s' "${names}" | text_to_lines)
}

check_sagemaker_models() {
  local names name arn tag_state reason
  if ! run_aws_text names "sagemaker list models" sagemaker list-models --max-results 100 --query 'Models[].ModelName' --output text; then
    add_result "sagemaker" "models" "unknown" "cannot list models"
    return
  fi

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-model --model-name "${name}" --query 'ModelArn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_sagemaker "${arn}")"
    fi
    if reason="$(matches_name_or_tag "${name}" "${tag_state}")"; then
      add_result "sagemaker" "model:${name}" "active" "exists; ${reason}"
    fi
  done < <(printf '%s' "${names}" | text_to_lines)
}

check_sagemaker_endpoints() {
  local names name arn tag_state reason status config_name
  if ! run_aws_text names "sagemaker list endpoints" sagemaker list-endpoints --max-results 100 --query 'Endpoints[].EndpointName' --output text; then
    add_result "sagemaker" "endpoints" "unknown" "cannot list endpoints"
    return
  fi

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-endpoint --endpoint-name "${name}" --query 'EndpointArn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_sagemaker "${arn}")"
    fi
    if reason="$(matches_name_or_tag "${name}" "${tag_state}")"; then
      status="$(aws_cmd sagemaker describe-endpoint --endpoint-name "${name}" --query 'EndpointStatus' --output text 2>/dev/null || echo "unknown")"
      config_name="$(aws_cmd sagemaker describe-endpoint --endpoint-name "${name}" --query 'EndpointConfigName' --output text 2>/dev/null || echo "unknown")"
      case "${status}" in
        InService|Creating|Updating|SystemUpdating|RollingBack|Deleting)
          add_result "sagemaker" "endpoint:${name}" "active" "status=${status}; config=${config_name}; ${reason}"
          ;;
        Failed|OutOfService)
          add_result "sagemaker" "endpoint:${name}" "inactive" "status=${status}; config=${config_name}; ${reason}"
          ;;
        *)
          add_result "sagemaker" "endpoint:${name}" "unknown" "status=${status}; config=${config_name}; ${reason}"
          ;;
      esac
    fi
  done < <(printf '%s' "${names}" | text_to_lines)
}

check_sagemaker_pipelines() {
  local names name arn tag_state reason latest_status
  if ! run_aws_text names "sagemaker list pipelines" sagemaker list-pipelines --max-results 100 --query 'PipelineSummaries[].PipelineName' --output text; then
    add_result "sagemaker" "pipelines" "unknown" "cannot list pipelines"
    return
  fi

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    arn="$(aws_cmd sagemaker describe-pipeline --pipeline-name "${name}" --query 'PipelineArn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_sagemaker "${arn}")"
    fi
    if reason="$(matches_name_or_tag "${name}" "${tag_state}")"; then
      latest_status="$(aws_cmd sagemaker list-pipeline-executions --pipeline-name "${name}" --max-results 1 --query 'PipelineExecutionSummaries[0].PipelineExecutionStatus' --output text 2>/dev/null || echo "unknown")"
      case "${latest_status}" in
        Executing|Stopping)
          add_result "sagemaker" "pipeline:${name}" "active" "latest_execution=${latest_status}; ${reason}"
          ;;
        Succeeded|Failed|Stopped|None)
          add_result "sagemaker" "pipeline:${name}" "inactive" "latest_execution=${latest_status}; ${reason}"
          ;;
        *)
          add_result "sagemaker" "pipeline:${name}" "unknown" "latest_execution=${latest_status}; ${reason}"
          ;;
      esac
    fi
  done < <(printf '%s' "${names}" | text_to_lines)
}

check_sagemaker_registry() {
  local groups group arn tag_state reason
  local packages pkg_arn tag_state_pkg

  if ! run_aws_text groups "sagemaker list model package groups" sagemaker list-model-package-groups --max-results 100 --query 'ModelPackageGroupSummaryList[].ModelPackageGroupName' --output text; then
    add_result "sagemaker" "model-package-groups" "unknown" "cannot list model package groups"
    return
  fi

  while IFS= read -r group; do
    [[ -n "${group}" ]] || continue
    arn="$(aws_cmd sagemaker describe-model-package-group --model-package-group-name "${group}" --query 'ModelPackageGroupArn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_sagemaker "${arn}")"
    fi
    if reason="$(matches_name_or_tag "${group}" "${tag_state}")"; then
      add_result "sagemaker" "model-package-group:${group}" "active" "exists; ${reason}"
    fi
  done < <(printf '%s' "${groups}" | text_to_lines)

  if ! run_aws_text packages "sagemaker list model packages" sagemaker list-model-packages --max-results 100 --query 'ModelPackageSummaryList[].ModelPackageArn' --output text; then
    add_result "sagemaker" "model-packages" "unknown" "cannot list model packages"
    return
  fi

  while IFS= read -r pkg_arn; do
    [[ -n "${pkg_arn}" ]] || continue
    tag_state_pkg="$(has_project_tag_sagemaker "${pkg_arn}")"
    if [[ "${tag_state_pkg}" == "yes" || "${pkg_arn}" == *"${NAME_PREFIX}"* ]]; then
      add_result "sagemaker" "model-package:${pkg_arn}" "active" "exists; tag=${tag_state_pkg}"
    elif [[ "${tag_state_pkg}" == "unknown" ]]; then
      add_result "sagemaker" "model-package:${pkg_arn}" "unknown" "cannot resolve tags"
    fi
  done < <(printf '%s' "${packages}" | text_to_lines)
}

check_sagemaker() {
  check_sagemaker_training_jobs
  check_sagemaker_transform_jobs
  check_sagemaker_models
  check_sagemaker_endpoints
  check_sagemaker_pipelines
  check_sagemaker_registry
}

check_ecs() {
  local clusters cluster_arn cluster_name tag_state reason
  local service_arns service_arn service_name running desired

  if ! run_aws_text clusters "ecs list clusters" ecs list-clusters --max-results 100 --query 'clusterArns' --output text; then
    add_result "ecs" "clusters" "unknown" "cannot list clusters"
    return
  fi

  while IFS= read -r cluster_arn; do
    [[ -n "${cluster_arn}" ]] || continue
    cluster_name="${cluster_arn##*/}"
    tag_state="$(has_project_tag_ecs "${cluster_arn}")"
    if reason="$(matches_name_or_tag "${cluster_name}" "${tag_state}")"; then
      if run_aws_text service_arns "ecs list services ${cluster_name}" ecs list-services --cluster "${cluster_arn}" --max-results 100 --query 'serviceArns' --output text; then
        if [[ -z "${service_arns}" || "${service_arns}" == "None" ]]; then
          add_result "ecs" "cluster:${cluster_name}" "inactive" "no services; ${reason}"
        else
          while IFS= read -r service_arn; do
            [[ -n "${service_arn}" ]] || continue
            service_name="${service_arn##*/}"
            running="$(aws_cmd ecs describe-services --cluster "${cluster_arn}" --services "${service_arn}" --query 'services[0].runningCount' --output text 2>/dev/null || echo "unknown")"
            desired="$(aws_cmd ecs describe-services --cluster "${cluster_arn}" --services "${service_arn}" --query 'services[0].desiredCount' --output text 2>/dev/null || echo "unknown")"
            if [[ "${running}" == "unknown" || "${desired}" == "unknown" ]]; then
              add_result "ecs" "service:${service_name}" "unknown" "cluster=${cluster_name}; ${reason}"
            elif (( running > 0 || desired > 0 )); then
              add_result "ecs" "service:${service_name}" "active" "cluster=${cluster_name}; running=${running}; desired=${desired}; ${reason}"
            else
              add_result "ecs" "service:${service_name}" "inactive" "cluster=${cluster_name}; running=${running}; desired=${desired}; ${reason}"
            fi
          done < <(printf '%s' "${service_arns}" | text_to_lines)
        fi
      else
        add_result "ecs" "cluster:${cluster_name}" "unknown" "cannot list services; ${reason}"
      fi
    fi
  done < <(printf '%s' "${clusters}" | text_to_lines)
}

check_lambda() {
  local functions fn_arn fn_name tag_state reason state

  if ! run_aws_text functions "lambda list functions" lambda list-functions --max-items 100 --query 'Functions[].FunctionArn' --output text; then
    add_result "lambda" "functions" "unknown" "cannot list functions"
    return
  fi

  while IFS= read -r fn_arn; do
    [[ -n "${fn_arn}" ]] || continue
    fn_name="${fn_arn##*:function:}"
    tag_state="$(has_project_tag_lambda "${fn_arn}")"
    if reason="$(matches_name_or_tag "${fn_name}" "${tag_state}")"; then
      state="$(aws_cmd lambda get-function-configuration --function-name "${fn_name}" --query 'State' --output text 2>/dev/null || echo "unknown")"
      if [[ "${state}" == "Active" ]]; then
        add_result "lambda" "function:${fn_name}" "active" "state=${state}; ${reason}"
      elif [[ "${state}" == "Inactive" ]]; then
        add_result "lambda" "function:${fn_name}" "inactive" "state=${state}; ${reason}"
      else
        add_result "lambda" "function:${fn_name}" "unknown" "state=${state}; ${reason}"
      fi
    fi
  done < <(printf '%s' "${functions}" | text_to_lines)
}

check_stepfunctions() {
  local sms sm_arn sm_name tag_state reason running

  if ! run_aws_text sms "stepfunctions list state machines" stepfunctions list-state-machines --max-results 100 --query 'stateMachines[].stateMachineArn' --output text; then
    add_result "stepfunctions" "state-machines" "unknown" "cannot list state machines"
    return
  fi

  while IFS= read -r sm_arn; do
    [[ -n "${sm_arn}" ]] || continue
    sm_name="${sm_arn##*:stateMachine:}"
    tag_state="$(has_project_tag_stepfunctions "${sm_arn}")"
    if reason="$(matches_name_or_tag "${sm_name}" "${tag_state}")"; then
      running="$(aws_cmd stepfunctions list-executions --state-machine-arn "${sm_arn}" --status-filter RUNNING --max-results 1 --query 'length(executions)' --output text 2>/dev/null || echo "unknown")"
      if [[ "${running}" == "unknown" ]]; then
        add_result "stepfunctions" "state-machine:${sm_name}" "unknown" "cannot read running executions; ${reason}"
      elif (( running > 0 )); then
        add_result "stepfunctions" "state-machine:${sm_name}" "active" "running_executions=${running}; ${reason}"
      else
        add_result "stepfunctions" "state-machine:${sm_name}" "inactive" "running_executions=${running}; ${reason}"
      fi
    fi
  done < <(printf '%s' "${sms}" | text_to_lines)
}

check_eventbridge() {
  local rules rule_name rule_arn state tag_state reason

  if ! run_aws_text rules "eventbridge list rules" events list-rules --limit 100 --query 'Rules[].Name' --output text; then
    add_result "eventbridge" "rules" "unknown" "cannot list rules"
    return
  fi

  while IFS= read -r rule_name; do
    [[ -n "${rule_name}" ]] || continue
    rule_arn="$(aws_cmd events describe-rule --name "${rule_name}" --query 'Arn' --output text 2>/dev/null || true)"
    tag_state="unknown"
    if [[ -n "${rule_arn}" && "${rule_arn}" != "None" ]]; then
      tag_state="$(has_project_tag_eventbridge "${rule_arn}")"
    fi
    if reason="$(matches_name_or_tag "${rule_name}" "${tag_state}")"; then
      state="$(aws_cmd events describe-rule --name "${rule_name}" --query 'State' --output text 2>/dev/null || echo "unknown")"
      if [[ "${state}" == "ENABLED" ]]; then
        add_result "eventbridge" "rule:${rule_name}" "active" "state=${state}; ${reason}"
      elif [[ "${state}" == "DISABLED" ]]; then
        add_result "eventbridge" "rule:${rule_name}" "inactive" "state=${state}; ${reason}"
      else
        add_result "eventbridge" "rule:${rule_name}" "unknown" "state=${state}; ${reason}"
      fi
    fi
  done < <(printf '%s' "${rules}" | text_to_lines)
}

check_scheduler() {
  local schedules line schedule_name group_name arn state tag_state reason

  if ! run_aws_text schedules "scheduler list schedules" scheduler list-schedules --max-results 100 --query 'Schedules[].[Name,GroupName,Arn,State]' --output text; then
    add_result "scheduler" "schedules" "unknown" "cannot list schedules"
    return
  fi

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    schedule_name="$(awk '{print $1}' <<<"${line}")"
    group_name="$(awk '{print $2}' <<<"${line}")"
    arn="$(awk '{print $3}' <<<"${line}")"
    state="$(awk '{print $4}' <<<"${line}")"

    tag_state="unknown"
    if [[ -n "${arn}" && "${arn}" != "None" ]]; then
      tag_state="$(has_project_tag_scheduler "${arn}")"
    fi

    if reason="$(matches_name_or_tag "${schedule_name}" "${tag_state}")"; then
      if [[ "${state}" == "ENABLED" ]]; then
        add_result "scheduler" "schedule:${group_name}/${schedule_name}" "active" "state=${state}; ${reason}"
      elif [[ "${state}" == "DISABLED" ]]; then
        add_result "scheduler" "schedule:${group_name}/${schedule_name}" "inactive" "state=${state}; ${reason}"
      else
        add_result "scheduler" "schedule:${group_name}/${schedule_name}" "unknown" "state=${state}; ${reason}"
      fi
    fi
  done < <(printf '%s' "${schedules}" | text_to_lines)
}

check_cloudwatch() {
  local alarms alarm_name alarm_arn state tag_state reason
  local log_groups lg_name lg_tag_state lg_reason
  local dashboards db_name

  if run_aws_text alarms "cloudwatch describe alarms" cloudwatch describe-alarms --max-records 100 --query 'MetricAlarms[].[AlarmName,AlarmArn,StateValue]' --output text; then
    while IFS= read -r alarm_line; do
      [[ -n "${alarm_line}" ]] || continue
      alarm_name="$(awk '{print $1}' <<<"${alarm_line}")"
      alarm_arn="$(awk '{print $2}' <<<"${alarm_line}")"
      state="$(awk '{print $3}' <<<"${alarm_line}")"

      tag_state="unknown"
      if [[ -n "${alarm_arn}" && "${alarm_arn}" != "None" ]]; then
        tag_state="$(has_project_tag_cloudwatch_alarm "${alarm_arn}")"
      fi

      if reason="$(matches_name_or_tag "${alarm_name}" "${tag_state}")"; then
        if [[ "${state}" == "INSUFFICIENT_DATA" ]]; then
          add_result "cloudwatch" "alarm:${alarm_name}" "inactive" "state=${state}; ${reason}"
        else
          add_result "cloudwatch" "alarm:${alarm_name}" "active" "state=${state}; ${reason}"
        fi
      fi
    done < <(printf '%s' "${alarms}" | text_to_lines)
  else
    add_result "cloudwatch" "alarms" "unknown" "cannot describe alarms"
  fi

  if run_aws_text log_groups "logs describe log groups" logs describe-log-groups --limit 50 --query 'logGroups[].logGroupName' --output text; then
    while IFS= read -r lg_name; do
      [[ -n "${lg_name}" ]] || continue
      lg_tag_state="$(has_project_tag_log_group "${lg_name}")"
      if lg_reason="$(matches_name_or_tag "${lg_name}" "${lg_tag_state}")"; then
        add_result "cloudwatch" "log-group:${lg_name}" "active" "exists; ${lg_reason}"
      fi
    done < <(printf '%s' "${log_groups}" | text_to_lines)
  else
    add_result "cloudwatch" "log-groups" "unknown" "cannot describe log groups"
  fi

  if run_aws_text dashboards "cloudwatch list dashboards" cloudwatch list-dashboards --query 'DashboardEntries[].DashboardName' --output text; then
    while IFS= read -r db_name; do
      [[ -n "${db_name}" ]] || continue
      if [[ "${db_name}" == "${NAME_PREFIX}"* || "${db_name}" == *"${PROJECT_TAG}"* ]]; then
        add_result "cloudwatch" "dashboard:${db_name}" "active" "matches naming convention"
      fi
    done < <(printf '%s' "${dashboards}" | text_to_lines)
  else
    add_result "cloudwatch" "dashboards" "unknown" "cannot list dashboards"
  fi
}

check_ecr() {
  local repos repo_name repo_arn tag_state reason

  if ! run_aws_text repos "ecr describe repositories" ecr describe-repositories --max-results 100 --query 'repositories[].[repositoryName,repositoryArn]' --output text; then
    add_result "ecr" "repositories" "unknown" "cannot describe repositories"
    return
  fi

  while IFS= read -r repo_line; do
    [[ -n "${repo_line}" ]] || continue
    repo_name="$(awk '{print $1}' <<<"${repo_line}")"
    repo_arn="$(awk '{print $2}' <<<"${repo_line}")"
    tag_state="unknown"
    if [[ -n "${repo_arn}" && "${repo_arn}" != "None" ]]; then
      tag_state="$(has_project_tag_ecr "${repo_arn}")"
    fi
    if reason="$(matches_name_or_tag "${repo_name}" "${tag_state}")"; then
      add_result "ecr" "repository:${repo_name}" "active" "exists; ${reason}"
    fi
  done < <(printf '%s' "${repos}" | text_to_lines)
}

check_ec2() {
  local instances line instance_id state name project_tag reason

  if ! run_aws_text instances "ec2 describe instances" ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`]|[0].Value,Tags[?Key==`project`]|[0].Value]' --output text; then
    add_result "ec2" "instances" "unknown" "cannot describe instances"
    return
  fi

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    instance_id="$(awk '{print $1}' <<<"${line}")"
    state="$(awk '{print $2}' <<<"${line}")"
    name="$(awk '{print $3}' <<<"${line}")"
    project_tag="$(awk '{print $4}' <<<"${line}")"

    reason=""
    if [[ "${name}" == "${NAME_PREFIX}"* ]]; then
      reason="prefix:${NAME_PREFIX}"
    elif [[ "${project_tag}" == "${PROJECT_TAG}" ]]; then
      reason="tag:project=${PROJECT_TAG}"
    fi

    if [[ -n "${reason}" ]]; then
      case "${state}" in
        running|pending)
          add_result "ec2" "instance:${instance_id}" "active" "state=${state}; ${reason}"
          ;;
        stopped|stopping|shutting-down|terminated)
          add_result "ec2" "instance:${instance_id}" "inactive" "state=${state}; ${reason}"
          ;;
        *)
          add_result "ec2" "instance:${instance_id}" "unknown" "state=${state}; ${reason}"
          ;;
      esac
    fi
  done < <(printf '%s' "${instances}" | text_to_lines)
}

check_budgets() {
  local budgets budget_name matched=0

  if ! run_aws_text budgets "budgets describe budgets" budgets describe-budgets --account-id "${ACCOUNT_ID}" --query 'Budgets[].BudgetName' --output text; then
    add_result "budgets" "budgets" "unknown" "cannot describe budgets"
    return
  fi

  while IFS= read -r budget_name; do
    [[ -n "${budget_name}" ]] || continue
    if [[ "${budget_name}" == "${NAME_PREFIX}"* || "${budget_name}" == *"${PROJECT_TAG}"* || "${budget_name}" == *"titanic"* ]]; then
      add_result "budgets" "budget:${budget_name}" "active" "exists"
      matched=1
    fi
  done < <(printf '%s' "${budgets}" | text_to_lines)

  if (( matched == 0 )); then
    add_result "budgets" "budget:project" "inactive" "no project budget matched by name"
  fi
}

run_checks() {
  local service
  for service in "${INCLUDED_SERVICES[@]}"; do
    case "${service}" in
      s3) check_s3 ;;
      sagemaker) check_sagemaker ;;
      ecs) check_ecs ;;
      lambda) check_lambda ;;
      stepfunctions) check_stepfunctions ;;
      eventbridge) check_eventbridge ;;
      scheduler) check_scheduler ;;
      cloudwatch) check_cloudwatch ;;
      ecr) check_ecr ;;
      ec2) check_ec2 ;;
      budgets) check_budgets ;;
      *) warn "Unknown service in phase map: ${service}" ;;
    esac
  done
}

print_summary() {
  local service

  printf '\n=== Tutorial Resource Activity Summary ===\n'
  printf 'Phase: %s\n' "${PHASE}"
  printf 'Profile/Region: %s / %s\n' "${AWS_PROFILE}" "${AWS_REGION}"
  printf 'Project tag: %s\n' "${PROJECT_TAG}"
  printf 'Name prefix: %s\n' "${NAME_PREFIX}"
  printf 'Bucket: %s\n\n' "${DATA_BUCKET}"

  printf '%-14s %-8s %-9s %-8s\n' "Service" "Active" "Inactive" "Unknown"
  printf '%-14s %-8s %-9s %-8s\n' "-------" "------" "--------" "-------"
  for service in "${INCLUDED_SERVICES[@]}"; do
    printf '%-14s %-8s %-9s %-8s\n' \
      "${service}" \
      "${SERVICE_ACTIVE[${service}]:-0}" \
      "${SERVICE_INACTIVE[${service}]:-0}" \
      "${SERVICE_UNKNOWN[${service}]:-0}"
  done

  printf '\nTotals -> active=%s inactive=%s unknown=%s\n' "${TOTAL_ACTIVE}" "${TOTAL_INACTIVE}" "${TOTAL_UNKNOWN}"
}

print_details() {
  local service entry entry_service resource status detail

  printf '\n=== Resource Details ===\n'
  for service in "${INCLUDED_SERVICES[@]}"; do
    printf '\n[%s]\n' "${service}"
    for entry in "${RESULTS[@]}"; do
      entry_service="${entry%%|*}"
      if [[ "${entry_service}" != "${service}" ]]; then
        continue
      fi
      resource="$(cut -d'|' -f2 <<<"${entry}")"
      status="$(cut -d'|' -f3 <<<"${entry}")"
      detail="$(cut -d'|' -f4- <<<"${entry}")"
      printf -- '- %-8s %s (%s)\n' "${status}" "${resource}" "${detail}"
    done
  done
}

print_warnings() {
  local w
  printf '\n=== Warnings ===\n'
  if [[ ${#WARNINGS[@]} -eq 0 ]]; then
    printf '(none)\n'
    return
  fi

  for w in "${WARNINGS[@]}"; do
    printf -- '- %s\n' "${w}"
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --phase)
        PHASE="${2:-}"
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
      --project-tag)
        PROJECT_TAG="${2:-}"
        shift
        ;;
      --name-prefix)
        NAME_PREFIX="${2:-}"
        shift
        ;;
      --bucket)
        DATA_BUCKET="${2:-}"
        shift
        ;;
      --fail-if-active)
        FAIL_IF_ACTIVE=1
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
  [[ -n "${PHASE}" ]] || fatal "--phase is required"
  [[ -n "${PHASE_SERVICES[${PHASE}]:-}" ]] || fatal "--phase must be one of all|00|01|02|03|04|05|06|07"

  command -v aws >/dev/null 2>&1 || fatal "aws CLI not found"

  if [[ "${AWS_PROFILE}" != "data-science-user" ]]; then
    fatal "AWS profile must be data-science-user. Current: ${AWS_PROFILE}"
  fi

  INCLUDED_SERVICES=(${PHASE_SERVICES[${PHASE}]})
  init_counters
}

validate_aws_context() {
  local caller account
  if ! run_aws_text caller "sts get caller identity arn" sts get-caller-identity --query 'Arn' --output text; then
    fatal "Unable to resolve AWS caller identity for profile ${AWS_PROFILE}"
  fi
  if ! run_aws_text account "sts get caller identity account" sts get-caller-identity --query 'Account' --output text; then
    fatal "Unable to resolve AWS account for profile ${AWS_PROFILE}"
  fi

  ACCOUNT_ID="${account}"
  log "AWS caller: ${caller}"
  log "AWS account: ${ACCOUNT_ID}"
}

final_exit_code() {
  if (( FAIL_IF_ACTIVE == 1 )) && (( TOTAL_ACTIVE > 0 )); then
    return 2
  fi
  return 0
}

main() {
  export AWS_PAGER=""

  parse_args "$@"
  validate_inputs
  validate_aws_context

  run_checks
  print_summary
  print_details
  print_warnings

  if final_exit_code; then
    exit 0
  fi
  exit 2
}

main "$@"
