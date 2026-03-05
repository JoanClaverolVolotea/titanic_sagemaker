#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME="${REMOTE_NAME:-sagemaker-sdk}"
REMOTE_URL="${REMOTE_URL:-https://github.com/aws/sagemaker-python-sdk.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
VENDOR_PATH="${VENDOR_PATH:-vendor/sagemaker-python-sdk}"

TEMP_COMMIT_MSG="temp: re-track vendored sagemaker sdk for subtree pull"
FINAL_COMMIT_MSG="chore: refresh local-only vendored sagemaker sdk"

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-sdk.sh [--branch <name>] [--message <commit message>] [--allow-dirty]

Options:
  --branch <name>    Upstream branch to pull (default: master)
  --message <text>   Final commit message (default: chore: refresh local-only vendored sagemaker sdk)
  --allow-dirty      Skip clean working tree check
  -h, --help         Show this help

Environment overrides:
  REMOTE_NAME, REMOTE_URL, UPSTREAM_BRANCH, VENDOR_PATH
USAGE
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[INFO] %s\n' "$*"
}

ALLOW_DIRTY=0

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch)
        UPSTREAM_BRANCH="${2:-}"
        shift
        ;;
      --message)
        FINAL_COMMIT_MSG="${2:-}"
        shift
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

ensure_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this script inside a git repository"
}

ensure_clean_tree() {
  if (( ALLOW_DIRTY == 1 )); then
    return
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    die "Working tree is not clean. Commit/stash changes or rerun with --allow-dirty"
  fi
}

ensure_remote() {
  if git remote get-url "${REMOTE_NAME}" >/dev/null 2>&1; then
    return
  fi

  info "Adding remote ${REMOTE_NAME} -> ${REMOTE_URL}"
  git remote add "${REMOTE_NAME}" "${REMOTE_URL}"
}

ensure_vendor_exists() {
  [[ -d "${VENDOR_PATH}" ]] || die "Vendor path not found: ${VENDOR_PATH}"
}

main() {
  parse_args "$@"
  ensure_git_repo
  ensure_clean_tree
  ensure_remote
  ensure_vendor_exists

  info "Fetching ${REMOTE_NAME}/${UPSTREAM_BRANCH}"
  git fetch "${REMOTE_NAME}" "${UPSTREAM_BRANCH}"

  info "Temporarily re-tracking ${VENDOR_PATH}"
  git add -f "${VENDOR_PATH}"
  git commit -m "${TEMP_COMMIT_MSG}"

  info "Pulling subtree updates"
  git subtree pull --prefix="${VENDOR_PATH}" "${REMOTE_NAME}" "${UPSTREAM_BRANCH}" --squash

  info "Untracking ${VENDOR_PATH} again"
  git rm -r --cached "${VENDOR_PATH}"
  git commit -m "${FINAL_COMMIT_MSG}"

  info "Done. ${VENDOR_PATH} remains local-only via .gitignore"
}

main "$@"
