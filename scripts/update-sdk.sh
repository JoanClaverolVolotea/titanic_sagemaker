#!/usr/bin/env bash
set -euo pipefail

REMOTE_URL="${REMOTE_URL:-https://github.com/aws/sagemaker-python-sdk.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
VENDOR_PATH="${VENDOR_PATH:-vendor/sagemaker-python-sdk}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-sdk.sh [--branch <name>] [--repo-url <url>]

Options:
  --branch <name>    Upstream branch to pull (default: master)
  --repo-url <url>   Upstream repo URL
  -h, --help         Show this help

Environment overrides:
  REMOTE_URL, UPSTREAM_BRANCH, VENDOR_PATH
USAGE
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[INFO] %s\n' "$*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch)
        UPSTREAM_BRANCH="${2:-}"
        shift
        ;;
      --repo-url)
        REMOTE_URL="${2:-}"
        shift
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

ensure_tools() {
  command -v git >/dev/null 2>&1 || die "git is required"
  command -v rsync >/dev/null 2>&1 || die "rsync is required"
}

main() {
  local tmp_dir
  local clone_dir

  parse_args "$@"
  ensure_git_repo
  ensure_tools

  tmp_dir="$(mktemp -d)"
  clone_dir="${tmp_dir}/sagemaker-python-sdk"
  trap "rm -rf -- '${tmp_dir}'" EXIT

  info "Cloning ${REMOTE_URL} (${UPSTREAM_BRANCH})"
  git clone --depth 1 --branch "${UPSTREAM_BRANCH}" "${REMOTE_URL}" "${clone_dir}" >/dev/null

  mkdir -p "${VENDOR_PATH}"

  info "Refreshing ${VENDOR_PATH} from upstream"
  rsync -a --delete --exclude ".git" "${clone_dir}/" "${VENDOR_PATH}/"

  info "Done. ${VENDOR_PATH} is updated locally and remains gitignored"
}

main "$@"
