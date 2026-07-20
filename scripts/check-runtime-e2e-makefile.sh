#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run="$(cd "$repo_root" && make --dry-run runtime-e2e-run)"
preflight_dry_run="$(cd "$repo_root" && make --dry-run runtime-e2e-preflight)"
target_probe_dry_run="$(cd "$repo_root" && make --dry-run runtime-e2e-target-probe)"
relative_path_dry_run="$({
  cd "$repo_root"
  make --dry-run runtime-e2e-run \
    RUNTIME_E2E_CONFIG=runtime-e2e-relative-config.json \
    RUNTIME_E2E_REPORT=.local-build/Tools/runtime-e2e-relative-report.json
})"

for stable_run in "$dry_run" "$preflight_dry_run" "$target_probe_dry_run"; do
  if grep -Eq '(^|[[:space:]])swift (build|run)([[:space:]]|$)' <<<"$stable_run"; then
    echo "runtime E2E invocation must not rebuild the helper after TCC is granted." >&2
    exit 1
  fi

  if grep -Eq '(^|[[:space:]])codesign([[:space:]]|$)' <<<"$stable_run"; then
    echo "runtime E2E invocation must not re-sign the helper after TCC is granted." >&2
    exit 1
  fi

  if grep -Fq 'rm -rf "' <<<"$stable_run" && grep -Fq 'RuntimeE2EHarness.app' <<<"$stable_run"; then
    echo "runtime E2E invocation must not delete the helper after TCC is granted." >&2
    exit 1
  fi
done

if ! grep -Fq -- "--config \"$repo_root/runtime-e2e-relative-config.json\"" <<<"$relative_path_dry_run"; then
  echo "runtime-e2e-run must pass an absolute config path to the helper app." >&2
  exit 1
fi

if ! grep -Fq -- "--json-output \"$repo_root/.local-build/Tools/runtime-e2e-relative-report.json\"" <<<"$relative_path_dry_run"; then
  echo "runtime-e2e-run must pass an absolute report path to the helper app." >&2
  exit 1
fi

if ! grep -Fq 'plutil -extract passed raw' <<<"$preflight_dry_run"; then
  echo "runtime-e2e-preflight must fail when its JSON report is not ready." >&2
  exit 1
fi

if ! grep -Fq -- '--target-probe' <<<"$target_probe_dry_run"; then
  echo "runtime-e2e-target-probe must invoke the isolated target probe mode." >&2
  exit 1
fi

if grep -Eq '[[:digit:]]_[[:digit:]]' "$repo_root/scripts/run-macos-runtime-e2e.sh"; then
  echo "Namespace runtime shell arithmetic must remain compatible with macOS Bash 3.2." >&2
  exit 1
fi
