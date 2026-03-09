#!/usr/bin/env bash
set -euo pipefail

# Admin helper to converge the active Titanic DS IAM policy bundles.
# Not required to complete docs/tutorials/00-07.

ACCOUNT_ID="${ACCOUNT_ID:-939122281183}"
IAM_USER="${IAM_USER:-data-science-user}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_PROFILE="${AWS_PROFILE:-data-science-user}"
MODE="apply"
ATTACH_SPEC="${ATTACH_SPEC:-operator}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
POLICY_DIR="${REPO_ROOT}/docs/aws/policies"

POLICY_NAMES=(
  "DataScienceTutorialBootstrap"
  "DataScienceTutorialOperator"
  "DataScienceTutorialCleanup"
)

POLICY_FILES=(
  "${POLICY_DIR}/01-ds-tutorial-bootstrap.json"
  "${POLICY_DIR}/02-ds-tutorial-operator.json"
  "${POLICY_DIR}/03-ds-tutorial-cleanup.json"
)

LEGACY_POLICY_NAMES=(
  "DataScienceObservabilityReadOnly"
  "DataSciencePassroleRestricted"
  "DataSciences3DataAccess"
  "DataScienceS3TutorialBucketBootstrap"
  "DataScienceSageMakerTrainingJobLifecycle"
  "DataScienceSageMakerAuthoringRuntime"
  "DataScienceSageMakerCleanupNonProd"
  "DataScienceServiceQuotasReadOnly"
  "DataScienceBootstrapIamResources"
)

DESIRED_ATTACHED_POLICIES=()
UNWANTED_CURRENT_POLICIES=()

usage() {
  cat <<'EOF'
Usage:
  scripts/ensure_ds_policies.sh [--apply|--check]

Description:
  Ensures the 3 active project IAM managed policies exist (create/update) and are
  available for user data-science-user. Uses AWS_PROFILE=data-science-user by
  default. In --apply, attaches only the requested capability bundles and
  detaches current bundles not requested plus any superseded legacy tutorial
  policies still attached to the user.

Prerequisite:
  The caller should already have equivalent IAM administration permissions to
  create policy versions and attach/detach user policies.

Options:
  --apply   Create/update policies and attach them to the user (default).
  --check   Validate that policies already exist and are attached.
  --attach <spec>  Desired attached current bundles. Values:
                   operator (default), bootstrap, cleanup, comma-separated
                   combinations, all, or none.
  -h, --help  Show this help.

Environment overrides:
  ACCOUNT_ID   Default: 939122281183
  IAM_USER     Default: data-science-user
  AWS_REGION   Default: eu-west-1
  AWS_PROFILE  Default: data-science-user
  ATTACH_SPEC  Default: operator
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
      --attach)
        ATTACH_SPEC="${2:-}"
        shift
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

resolve_attach_selection() {
  local ids=()
  local id name desired found

  case "${ATTACH_SPEC}" in
    all)
      DESIRED_ATTACHED_POLICIES=("${POLICY_NAMES[@]}")
      ;;
    none|"")
      DESIRED_ATTACHED_POLICIES=()
      ;;
    *)
      IFS=',' read -r -a ids <<<"${ATTACH_SPEC}"
      for id in "${ids[@]}"; do
        case "${id}" in
          bootstrap)
            name="DataScienceTutorialBootstrap"
            ;;
          operator)
            name="DataScienceTutorialOperator"
            ;;
          cleanup)
            name="DataScienceTutorialCleanup"
            ;;
          *)
            fatal "Unknown --attach value: ${id}. Use bootstrap,operator,cleanup,all,none."
            ;;
        esac

        found=0
        for desired in "${DESIRED_ATTACHED_POLICIES[@]}"; do
          if [[ "${desired}" == "${name}" ]]; then
            found=1
            break
          fi
        done
        if [[ "${found}" == "0" ]]; then
          DESIRED_ATTACHED_POLICIES+=("${name}")
        fi
      done
      ;;
  esac

  UNWANTED_CURRENT_POLICIES=()
  for name in "${POLICY_NAMES[@]}"; do
    found=0
    for desired in "${DESIRED_ATTACHED_POLICIES[@]}"; do
      if [[ "${desired}" == "${name}" ]]; then
        found=1
        break
      fi
    done
    if [[ "${found}" == "0" ]]; then
      UNWANTED_CURRENT_POLICIES+=("${name}")
    fi
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
    fatal "Missing iam:GetUser for ${IAM_USER}. Use a caller with equivalent IAM admin permissions."
  fi
  if ! aws_cmd iam list-attached-user-policies --user-name "${IAM_USER}" --max-items 1 >/dev/null 2>&1; then
    fatal "Missing iam:ListAttachedUserPolicies for ${IAM_USER}. Use a caller with equivalent IAM admin permissions."
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
  done

  for name in "${DESIRED_ATTACHED_POLICIES[@]}"; do
    arn="$(policy_arn "${name}")"
    attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"
    [[ "${attached_count}" != "0" ]] || fatal "Verification failed: ${name} not attached to ${IAM_USER}."
  done

  for name in "${UNWANTED_CURRENT_POLICIES[@]}"; do
    arn="$(policy_arn "${name}")"
    attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"
    [[ "${attached_count}" == "0" ]] || fatal "Verification failed: current policy ${name} is still attached to ${IAM_USER}."
  done

  for name in "${LEGACY_POLICY_NAMES[@]}"; do
    arn="$(policy_arn "${name}")"
    attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"
    [[ "${attached_count}" == "0" ]] || fatal "Verification failed: legacy policy ${name} is still attached to ${IAM_USER}."
  done
}

ensure_legacy_policy_detached() {
  local name="$1"
  local arn
  local attached_count
  arn="$(policy_arn "${name}")"
  attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"

  if [[ "${attached_count}" == "0" ]]; then
    return 0
  fi

  if [[ "${MODE}" == "apply" ]]; then
    aws_cmd iam detach-user-policy --user-name "${IAM_USER}" --policy-arn "${arn}" >/dev/null
    log "Detached legacy policy ${name} from ${IAM_USER}."
  else
    fatal "Legacy policy ${name} is still attached to ${IAM_USER}. Run with --apply."
  fi
}

ensure_policy_detached() {
  local name="$1"
  local arn
  local attached_count
  arn="$(policy_arn "${name}")"
  attached_count="$(is_policy_attached_to_user "${IAM_USER}" "${arn}")"

  if [[ "${attached_count}" == "0" ]]; then
    return 0
  fi

  if [[ "${MODE}" == "apply" ]]; then
    aws_cmd iam detach-user-policy --user-name "${IAM_USER}" --policy-arn "${arn}" >/dev/null
    log "Detached policy ${name} from ${IAM_USER}."
  else
    fatal "Policy ${name} is attached to ${IAM_USER} but not requested by --attach. Run with --apply."
  fi
}

main() {
  export AWS_PAGER=""

  parse_args "$@"
  resolve_attach_selection
  validate_execution_profile
  require_dependencies
  validate_local_policy_files
  validate_aws_context

  local i
  for i in "${!POLICY_NAMES[@]}"; do
    ensure_policy "${POLICY_NAMES[$i]}" "${POLICY_FILES[$i]}"
  done

  for name in "${DESIRED_ATTACHED_POLICIES[@]}"; do
    ensure_policy_attached "${name}"
  done

  for name in "${UNWANTED_CURRENT_POLICIES[@]}"; do
    ensure_policy_detached "${name}"
  done

  for name in "${LEGACY_POLICY_NAMES[@]}"; do
    ensure_legacy_policy_detached "${name}"
  done

  verify_final_state
  log "Done. Policies are properly applied for ${IAM_USER} (mode=${MODE}, attach=${ATTACH_SPEC})."
}

main "$@"
