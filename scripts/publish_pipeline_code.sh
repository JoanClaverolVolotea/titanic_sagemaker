#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
PREFIX="pipeline/code"
BUCKET="${BUCKET:-}"
CODE_VERSION="${CODE_VERSION:-}"
EMIT_EXPORTS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PIPELINE_CODE_DIR="${REPO_ROOT}/pipeline/code"

usage() {
  cat <<'EOF'
Usage:
  scripts/publish_pipeline_code.sh --bucket <name> [options]

Options:
  --bucket <name>         S3 bucket destino para scripts y bundle.
  --code-version <value>  Identificador de version del bundle. Default: git short SHA o timestamp UTC.
  --prefix <value>        Prefijo S3. Default: pipeline/code
  --profile <value>       AWS profile opcional. Default: usar AWS_PROFILE si existe.
  --region <value>        AWS region. Default: eu-west-1
  --emit-exports          Imprime export statements para eval/sourcing.
  -h, --help              Show this help

Outputs:
  - s3://<bucket>/<prefix>/<code-version>/pipeline_code.tar.gz
  - s3://<bucket>/<prefix>/scripts/preprocess.py
  - s3://<bucket>/<prefix>/scripts/evaluate.py
EOF
}

log() {
  printf '[INFO] %s\n' "$*" >&2
}

fatal() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

aws_cmd() {
  if [[ -n "${AWS_PROFILE}" ]]; then
    aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" "$@"
  else
    aws --region "${AWS_REGION}" "$@"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bucket)
        BUCKET="${2:-}"
        shift
        ;;
      --code-version)
        CODE_VERSION="${2:-}"
        shift
        ;;
      --prefix)
        PREFIX="${2:-}"
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
      --emit-exports)
        EMIT_EXPORTS=1
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

resolve_defaults() {
  if [[ -z "${BUCKET}" ]]; then
    BUCKET="$(terraform -chdir="${REPO_ROOT}/terraform/00_foundations" output -raw data_bucket_name 2>/dev/null || true)"
  fi
  [[ -n "${BUCKET}" ]] || fatal "Bucket is required. Pass --bucket or configure terraform/00_foundations output."

  if [[ -z "${CODE_VERSION}" ]]; then
    CODE_VERSION="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  if [[ -z "${CODE_VERSION}" ]]; then
    CODE_VERSION="$(date -u +%Y%m%d%H%M%S)"
  fi
}

validate_inputs() {
  command -v aws >/dev/null 2>&1 || fatal "aws CLI not found."
  command -v tar >/dev/null 2>&1 || fatal "tar not found."
  [[ -d "${PIPELINE_CODE_DIR}" ]] || fatal "Missing directory ${PIPELINE_CODE_DIR}"
  [[ -f "${PIPELINE_CODE_DIR}/preprocess.py" ]] || fatal "Missing ${PIPELINE_CODE_DIR}/preprocess.py"
  [[ -f "${PIPELINE_CODE_DIR}/evaluate.py" ]] || fatal "Missing ${PIPELINE_CODE_DIR}/evaluate.py"
}

publish_artifacts() {
  local tmp_dir bundle_path
  tmp_dir="$(mktemp -d)"
  bundle_path="${tmp_dir}/pipeline_code.tar.gz"
  trap "rm -rf '${tmp_dir}'" EXIT

  tar \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -C "${REPO_ROOT}/pipeline" \
    -czf "${bundle_path}" \
    code

  CODE_BUNDLE_URI="s3://${BUCKET}/${PREFIX}/${CODE_VERSION}/pipeline_code.tar.gz"
  PREPROCESS_SCRIPT_S3_URI="s3://${BUCKET}/${PREFIX}/scripts/preprocess.py"
  EVALUATE_SCRIPT_S3_URI="s3://${BUCKET}/${PREFIX}/scripts/evaluate.py"

  log "Uploading bundle to ${CODE_BUNDLE_URI}"
  aws_cmd s3 cp "${bundle_path}" "${CODE_BUNDLE_URI}" >/dev/null

  log "Uploading preprocess.py to ${PREPROCESS_SCRIPT_S3_URI}"
  aws_cmd s3 cp "${PIPELINE_CODE_DIR}/preprocess.py" "${PREPROCESS_SCRIPT_S3_URI}" >/dev/null

  log "Uploading evaluate.py to ${EVALUATE_SCRIPT_S3_URI}"
  aws_cmd s3 cp "${PIPELINE_CODE_DIR}/evaluate.py" "${EVALUATE_SCRIPT_S3_URI}" >/dev/null

  if [[ -f "${PIPELINE_CODE_DIR}/requirements.txt" ]]; then
    log "Uploading requirements.txt to s3://${BUCKET}/${PREFIX}/scripts/requirements.txt"
    aws_cmd s3 cp "${PIPELINE_CODE_DIR}/requirements.txt" "s3://${BUCKET}/${PREFIX}/scripts/requirements.txt" >/dev/null
  fi

  if (( EMIT_EXPORTS )); then
    printf 'export DATA_BUCKET=%q\n' "${BUCKET}"
    printf 'export CODE_VERSION=%q\n' "${CODE_VERSION}"
    printf 'export CODE_BUNDLE_URI=%q\n' "${CODE_BUNDLE_URI}"
    printf 'export PREPROCESS_SCRIPT_S3_URI=%q\n' "${PREPROCESS_SCRIPT_S3_URI}"
    printf 'export EVALUATE_SCRIPT_S3_URI=%q\n' "${EVALUATE_SCRIPT_S3_URI}"
  else
    printf 'DATA_BUCKET=%s\n' "${BUCKET}"
    printf 'CODE_VERSION=%s\n' "${CODE_VERSION}"
    printf 'CODE_BUNDLE_URI=%s\n' "${CODE_BUNDLE_URI}"
    printf 'PREPROCESS_SCRIPT_S3_URI=%s\n' "${PREPROCESS_SCRIPT_S3_URI}"
    printf 'EVALUATE_SCRIPT_S3_URI=%s\n' "${EVALUATE_SCRIPT_S3_URI}"
  fi
}

main() {
  parse_args "$@"
  resolve_defaults
  validate_inputs
  publish_artifacts
}

main "$@"
