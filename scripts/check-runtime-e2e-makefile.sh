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

if [ "$(runtime_audio_source_kind smoke '')" != public ] \
  || [ "$(runtime_audio_source_kind smoke runtime-audio.zip)" != namespace ] \
  || [ "$(runtime_audio_source_kind full runtime-audio.zip)" != namespace ] \
  || runtime_audio_source_kind full '' >/dev/null 2>&1; then
  echo "Runtime smoke must use public fallback audio without weakening full input requirements." >&2
  exit 1
fi

runtime_debug_binary="$repo_root/.local-build/RuntimeE2EHarness/debug/RuntimeE2EHarness"
runtime_debug_binary="${1:-$runtime_debug_binary}"
if [ ! -x "$runtime_debug_binary" ]; then
  echo "runtime-e2e-check must build the playback lifecycle probe before running this check." >&2
  exit 1
fi
"$runtime_debug_binary" --playback-check

custom_scratch=/tmp/roma-runtime-e2e-custom-scratch
custom_check_dry_run="$(
  cd "$repo_root"
  make --dry-run runtime-e2e-check RUNTIME_E2E_SCRATCH="$custom_scratch"
)"
if ! grep -Fq -- "bash scripts/check-runtime-e2e-makefile.sh \"$custom_scratch/debug/RuntimeE2EHarness\"" \
  <<<"$custom_check_dry_run"; then
  echo "runtime-e2e-check must validate the helper built in its configured scratch path." >&2
  exit 1
fi

smoke_config_json="$(
  runtime_e2e_config_json \
    /fixtures \
    '/Applications/roma just talk.app' \
    1 \
    20000 \
    smoke
)"
full_config_json="$(
  runtime_e2e_config_json \
    /fixtures \
    '/Applications/roma just talk.app' \
    3 \
    250 \
    full
)"
if ! jq -e '
  .preRollWarmupSeconds == 12
  and .targetTextTimeoutSeconds == 3
  and .minimumTargetCount == 2
  and ([.targets[].id] == ["textedit", "chrome"])
' <<<"$smoke_config_json" >/dev/null; then
  echo "Runtime smoke must emit the proven warmup and reduced target set." >&2
  exit 1
fi
if ! jq -e '
  .targetTextTimeoutSeconds == 20
  and .minimumTargetCount == 4
  and .repetitions == 3
' <<<"$full_config_json" >/dev/null; then
  echo "Full runtime proof must preserve its observation and repetition budget." >&2
  exit 1
fi

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

workflow="$repo_root/.github/workflows/voiceink-remote-e2e-stage.yml"
ruby - "$workflow" <<'RUBY'
require "yaml"

jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
stage = jobs.fetch("stage")
steps = stage.fetch("steps")
cache = steps.find { |step| step["id"] == "runtime-model-cache" }
prepare = steps.find { |step| step["name"] == "Prepare desktop and hold for Remote Display" }
verdict = jobs.fetch("verdict")
verdict_step = verdict.fetch("steps").find { |step| step["name"] == "Check remote stage result" }

abort "Remote E2E must mount the pinned persistent Parakeet model cache." unless
  cache&.fetch("uses", nil) ==
    "namespacelabs/nscloud-cache-action@c5f8dab7560444c4bf8dbc64f1b203431873c547" &&
  cache.dig("with", "path") ==
    "~/Library/Application Support/FluidAudio/Models" &&
  !cache.key?("continue-on-error")

abort "Remote E2E must record the cache action's authoritative hit output." unless
  prepare&.dig("env", "RUNTIME_MODEL_CACHE_HIT") ==
    "${{ steps.runtime-model-cache.outputs.cache-hit }}"

abort "Scenario failures must not suppress the cache action's post-save." unless
  prepare["id"] == "prepare-stage" &&
  prepare["continue-on-error"] == true &&
  stage.dig("outputs", "scenario-outcome") ==
    "${{ steps.prepare-stage.outcome }}"

abort "Remote E2E must preserve a truthful workflow verdict after cache save." unless
  verdict["if"] == "always()" &&
  verdict["needs"] == "stage" &&
  verdict_step&.dig("env", "STAGE_RESULT") == "${{ needs.stage.result }}" &&
  verdict_step&.dig("env", "SCENARIO_OUTCOME") ==
    "${{ needs.stage.outputs.scenario-outcome }}" &&
  verdict_step.fetch("run").include?('test "$STAGE_RESULT" = success') &&
  verdict_step.fetch("run").include?('test "$SCENARIO_OUTCOME" = success')
RUBY

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
