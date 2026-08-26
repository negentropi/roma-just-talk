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

source "$repo_root/scripts/runtime-e2e-phase-runner.sh"

phase_calls=""
phase_failure="functional-smoke"
scenario_status=0
mark_phase() {
  phase_calls="$phase_calls|phase:$1"
}
run_harness_phase() {
  phase_calls="$phase_calls|run:$1:$2:$3"
  [ "$1" != "$phase_failure" ]
}

run_runtime_e2e_phases smoke.json full.json
if [ "$scenario_status" -eq 0 ] \
  || ! grep -Fq '|run:runtime-e2e-report:runtime-e2e-run:full.json' <<<"$phase_calls"; then
  echo "A failed functional smoke must remain failed and still run the repeated matrix." >&2
  exit 1
fi

phase_calls=""
phase_failure="preflight"
scenario_status=0
if run_runtime_e2e_phases smoke.json full.json; then
  echo "A failed preflight must stop runtime phase execution." >&2
  exit 1
fi
if grep -Fq '|phase:target-probe' <<<"$phase_calls"; then
  echo "Target probing must not run after a failed preflight." >&2
  exit 1
fi

phase_calls=""
phase_failure="none"
scenario_status=0
run_runtime_e2e_phases smoke.json full.json smoke
if ! grep -Fq '|run:preflight:runtime-e2e-preflight:smoke.json' <<<"$phase_calls" \
  || ! grep -Fq '|run:functional-smoke:runtime-e2e-run:smoke.json' <<<"$phase_calls"; then
  echo "Runtime smoke must use the reduced config from preflight through execution." >&2
  exit 1
fi
if grep -Fq '|phase:repeated-runtime-matrix' <<<"$phase_calls"; then
  echo "Runtime smoke must not run the repeated matrix." >&2
  exit 1
fi

if run_runtime_e2e_phases smoke.json full.json unsupported >/dev/null 2>&1; then
  echo "Unsupported runtime modes must fail closed." >&2
  exit 1
fi

if ! grep -Fq -- '- "scripts/runtime-e2e-phase-runner.sh"' \
  "$repo_root/.github/workflows/voiceink-remote-e2e-stage.yml"; then
  echo "Remote E2E must run when its phase router changes." >&2
  exit 1
fi

fd() {
  printf '%s\n' \
    '/fixtures/quick-release-a-slow.wav' \
    '/fixtures/quick-release-b-short.wav'
}
afinfo() {
  case "$2" in
    *-a-slow.wav) printf '%s\n' 'estimated duration: 12.000 sec' ;;
    *-b-short.wav) printf '%s\n' 'estimated duration: 3.250 sec' ;;
    *) return 1 ;;
  esac
}

selected_fixture="$(select_runtime_smoke_fixture /fixtures 8)"
if [ "$selected_fixture" != '/fixtures/quick-release-b-short.wav' ]; then
  echo "Runtime smoke must select a measured fixture within its duration bound." >&2
  exit 1
fi

fd() {
  printf '%s\n' '/fixtures/quick-release-a-slow.wav'
}
if select_runtime_smoke_fixture /fixtures 8 >/dev/null 2>&1; then
  echo "Runtime smoke must fail closed without a bounded quick-release fixture." >&2
  exit 1
fi
