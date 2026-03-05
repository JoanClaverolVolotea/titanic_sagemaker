---
name: update-sdk
description: Automatically updates the vendored sagemaker-python-sdk when the user asks to update sdk, refresh sdk, sync sagemaker, pull latest sagemaker library changes, or similar requests.
---

# Update Vendored SageMaker SDK

Use this skill when the user wants to sync the local vendored SDK reference with upstream.

## Trigger Phrases

Use this skill for requests such as:

- "update sdk"
- "refresh sdk"
- "sync sagemaker"
- "pull latest sagemaker library"
- "update sagemaker library"

## Runbook

1. Confirm `scripts/update-sdk.sh` exists.
2. Run:

```bash
scripts/update-sdk.sh
```

3. If the user wants a different branch, run:

```bash
scripts/update-sdk.sh --branch <branch-name>
```

4. If the user wants a custom upstream repo URL, run:

```bash
scripts/update-sdk.sh --repo-url <repo-url>
```

## Validation

After completion, verify:

```bash
git status --short
```

Expected:

- The script finished without errors.
- `vendor/sagemaker-python-sdk/` remains local-only (gitignored/untracked in normal operation).

## Notes

- The script automates: shallow clone of upstream -> rsync into vendor path -> cleanup temporary files.
- Default upstream branch is `master` unless overridden.
- Supported flags are `--branch`, `--repo-url`, and `--help`.
