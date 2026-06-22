#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dry_run="$(
  cd "$repo_root"
  make --dry-run latency-harness-app-run LATENCY_EXPECTED="roma latency marker"
)"

if grep -Eq '(^|[[:space:]])swiftc([[:space:]]|$)' <<<"$dry_run"; then
  echo "latency-harness-app-run must not rebuild the helper binary after TCC is granted." >&2
  exit 1
fi

if grep -Eq '(^|[[:space:]])codesign([[:space:]]|$)' <<<"$dry_run"; then
  echo "latency-harness-app-run must not re-sign the helper app after TCC is granted." >&2
  exit 1
fi

if grep -Fq 'rm -rf "' <<<"$dry_run" &&
  grep -Fq 'VisibleTextLatencyHarness.app' <<<"$dry_run"; then
  echo "latency-harness-app-run must not delete the helper app after TCC is granted." >&2
  exit 1
fi
