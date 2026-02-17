#!/usr/bin/env bash
set -euo pipefail

# Ensures Titanic DS IAM policies are present and attached to the DS user.
# Default mode is apply; use --check to validate without changing AWS state.

ACCOUNT_ID="${ACCOUNT_ID:-939122281183}"
IAM_USER="${IAM_USER:-data-science-user}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_PROFILE="${AWS_PROFILE:-data-science-user}"
MODE="apply"
ADMIN_POLICY_NAME="${ADMIN_POLICY_NAME:-DataSciencePolicyAdministration}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
POLICY_DIR="${REPO_ROOT}/docs/aws/policies"

POLICY_NAMES=(
  "DataScienceObservabilityReadOnly"
  "DataScienceAssumeEnvironmentRoles"
  "DataSciencePassroleRestricted"
  "DataSciences3DataAccess"
)

POLICY_FILES=(
  "${POLICY_DIR}/01-ds-observability-readonly.json"
  "${POLICY_DIR}/02-ds-assume-environment-roles.json"
  "${POLICY_DIR}/03-ds-passrole-restricted.json"
  "${POLICY_DIR}/04-ds-s3-data-access.json"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/ensure_ds_policies.sh [--apply|--check]

Description:
  Ensures the 4 project IAM managed policies exist (create/update) and are
  attached to user data-science-user. Uses AWS_PROFILE=data-science-user by
  default.

Prerequisite:
  The user should already have the bootstrap policy
  DataSciencePolicyAdministration attached (or equivalent IAM permissions).

Options:
  --apply   Create/update policies and attach them to the user (default).
  --check   Validate that policies already exist and are attached.
  -h, --help  Show this help.

Environment overrides:
  ACCOUNT_ID   Default: 939122281183
  IAM_USER     Default: data-science-user
  AWS_REGION   Default: eu-west-1
  AWS_PROFILE  Default: data-science-user
  ADMIN_POLICY_NAME  Default: DataSciencePolicyAdministration
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

fatal() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

aws_cmd() {
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        MODE="apply"
        ;;
      --check)
        MODE="check"
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

validate_execution_profile() {
  if [[ "${AWS_PROFILE}" != "data-science-user" ]]; then
    fatal "AWS_PROFILE must be data-science-user. Current: ${AWS_PROFILE}"
  fi
}

require_dependencies() {
  command -v aws >/dev/null 2>&1 || fatal "aws CLI not found in PATH."
  command -v python3 >/dev/null 2>&1 || fatal "python3 not found in PATH."
}

validate_local_policy_files() {
  local i
  for i in "${!POLICY_FILES[@]}"; do
    [[ -f "${POLICY_FILES[$i]}" ]] || fatal "Missing policy file: ${POLICY_FILES[$i]}"
    python3 -m json.tool "${POLICY_FILES[$i]}" >/dev/null || fatal "Invalid JSON: ${POLICY_FILES[$i]}"
  done
}

validate_aws_context() {
  local current_account caller_arn
  current_account="$(aws_cmd sts get-caller-identity --query 'Account' --output text)"
  caller_arn="$(aws_cmd sts get-caller-identity --query 'Arn' --output text)"

  [[ "${current_account}" == "${ACCOUNT_ID}" ]] || fatal "AWS account mismatch. Expected ${ACCOUNT_ID}, got ${current_account}."
  if ! aws_cmd iam get-user --user-name "${IAM_USER}" >/dev/null 2>&1; then
    fatal "Missing iam:GetUser for ${IAM_USER}. Attach ${ADMIN_POLICY_NAME} first."
  fi
  if ! aws_cmd iam list-attached-user-policies --user-name "${IAM_USER}" --max-items 1 >/dev/null 2>&1; then
    fatal "Missing iam:ListAttachedUserPolicies for ${IAM_USER}. Attach ${ADMIN_POLICY_NAME} first."
  fi

  log "AWS caller: ${caller_arn}"
  log "Validated account ${ACCOUNT_ID} and user ${IAM_USER}."
}

policy_arn() {
  local name="$1"
  printf 'arn:aws:iam::%s:policy/%s' "${ACCOUNT_ID}" "${name}"
}

prune_old_policy_version_if_needed() {
  local arn="$1"
  local version_count oldest_non_default

  version_count="$(aws_cmd iam list-policy-versions --policy-arn "${arn}" --query 'length(Versions)' --output text)"
  if [[ "${version_count}" =~ ^[0-9]+$ ]] && (( version_count >= 5 )); then
    oldest_non_default="$(aws_cmd iam list-policy-versions \
      --policy-arn "${arn}" \
      --query 'sort_by(Versions[?IsDefaultVersion==`false`], &CreateDate)[0].VersionId' \
      --output text)"

    [[ -n "${oldest_non_default}" && "${oldest_non_default}" != "None" ]] || fatal "Policy ${arn} reached version limit with no deletable non-default version."
    aws_cmd iam delete-policy-version --policy-arn "${arn}" --version-id "${oldest_non_default}" >/dev/null
    log "Deleted old policy version ${oldest_non_default} for ${arn}."
  fi
}

ensure_policy() {
  local name="$1"
  local file="$2"
  local arn
  arn="$(policy_arn "${name}")"

  if aws_cmd iam get-policy --policy-arn "${arn}" >/dev/null 2>&1; then
    if [[ "${MODE}" == "apply" ]]; then
      prune_old_policy_version_if_needed "${arn}"
      aws_cmd iam create-policy-version \
        --policy-arn "${arn}" \
        --policy-document "file://${file}" \
        --set-as-default >/dev/null
      log "Updated policy ${name}."
    else
      log "Policy exists: ${name}."
    fi
  else
    if [[ "${MODE}" == "apply" ]]; then
      aws_cmd iam create-policy \
        --policy-name "${name}" \
        --policy-document "file://${file}" >/dev/null
      log "Created policy ${name}."
    else
      fatal "Missing policy ${name} (${arn}). Run with --apply."
    fi
  fi
}

is_policy_attached_to_user() {
  local user="$1"
  local arn="$2"
  aws_cmd iam list-attached-user-policies \
    --user-name "${user}" \
    --query "length(AttachedPolicies[?PolicyArn=='${arn}'])" \
    --output text
}

ensure_policy_attached() {
  local name="$1"
  local arn
  local attached_count
  arn="$(policy_arn "${name}")"
  attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"

  if [[ "${attached_count}" == "0" ]]; then
    if [[ "${MODE}" == "apply" ]]; then
      aws_cmd iam attach-user-policy --user-name "${IAM_USER}" --policy-arn "${arn}" >/dev/null
      log "Attached policy ${name} to ${IAM_USER}."
    else
      fatal "Policy ${name} is not attached to ${IAM_USER}. Run with --apply."
    fi
  else
    log "Policy already attached: ${name}."
  fi
}

verify_final_state() {
  local i name arn attached_count
  for i in "${!POLICY_NAMES[@]}"; do
    name="${POLICY_NAMES[$i]}"
    arn="$(policy_arn "${name}")"

    aws_cmd iam get-policy --policy-arn "${arn}" >/dev/null
    attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"
    [[ "${attached_count}" != "0" ]] || fatal "Verification failed: ${name} not attached to ${IAM_USER}."
  done
}

main() {
  export AWS_PAGER=""

  parse_args "$@"
  validate_execution_profile
  require_dependencies
  validate_local_policy_files
  validate_aws_context

  local i
  for i in "${!POLICY_NAMES[@]}"; do
    ensure_policy "${POLICY_NAMES[$i]}" "${POLICY_FILES[$i]}"
    ensure_policy_attached "${POLICY_NAMES[$i]}"
  done

  verify_final_state
  log "Done. Policies are properly applied for ${IAM_USER} (mode=${MODE})."
}

main "$@"
