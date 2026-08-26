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
source "$repo_root/scripts/runtime-e2e-model-bootstrap.sh"

model_manifest="$repo_root/scripts/runtime-e2e-parakeet-v2.manifest"
model_file_count="$(awk '!/^#/ && NF { count += 1 } END { print count + 0 }' "$model_manifest")"
model_path_digest="$(awk '!/^#/ && NF { print $3 }' "$model_manifest" | sort | shasum -a 256 | awk '{print $1}')"
model_first_entry="$(awk '!/^#/ && NF { print; exit }' "$model_manifest")"
if [ "$model_file_count" -ne 22 ] \
  || [ "$model_path_digest" != 0b563ca5e98413afbd98a0e68c4bafa5d3f72f08458b78786f5369a3319a90e7 ] \
  || [ "$model_first_entry" != '4adc7ad44f9d05e1bffeb2b06d3bb02861a5c7602dff63a6b494aed3bf8a6c3e 445187200 Encoder.mlmodelc/weights/weight.bin' ] \
  || ! awk '!/^#/ && NF { if (seen && $2 > previous) exit 1; previous = $2; seen = 1 } END { if (!seen) exit 1 }' "$model_manifest" \
  || ! grep -Fq 'model_revision="ee09c569f73759e6d44c9bd16766f477b2b36d39"' \
    "$repo_root/scripts/run-macos-runtime-e2e.sh"; then
  echo "Runtime model manifest must pin the complete measured Parakeet V2 directory." >&2
  exit 1
fi

model_test_root="$(mktemp -d /tmp/roma-runtime-model-check.XXXXXX)"
model_test_source="$model_test_root/source.bin"
model_test_manifest="$model_test_root/model.manifest"
model_test_directory="$model_test_root/model"
model_test_kind="$model_test_root/source-kind.txt"
printf '%s' 'pinned model bytes' > "$model_test_source"
model_test_sha256="$(shasum -a 256 "$model_test_source" | awk '{print $1}')"
model_test_size="$(wc -c < "$model_test_source" | tr -d ' ')"
printf '%s %s %s\n' "$model_test_sha256" "$model_test_size" model.bin \
  > "$model_test_manifest"
runtime_fake_nsc() {
  [ "$#" -eq 4 ]
  [ "$1" = artifact ]
  [ "$2" = cache-url ]
  [ "$3" = https://example.invalid/model/model.bin ]
  case "$4" in
    --out=*) ;;
    *) return 2 ;;
  esac
  cp "$model_test_source" "${4#--out=}"
}
runtime_prepare_pinned_model \
  "$model_test_manifest" \
  "$model_test_directory" \
  https://example.invalid/model \
  runtime_fake_nsc \
  "$model_test_kind" \
  1 \
  1
if [ "$(cat "$model_test_kind")" != namespace-url-artifact ] \
  || ! runtime_model_manifest_valid "$model_test_manifest" "$model_test_directory" 1; then
  echo "Runtime model bootstrap must hydrate and verify missing pinned files." >&2
  exit 1
fi
runtime_fake_nsc() { return 99; }
runtime_prepare_pinned_model \
  "$model_test_manifest" \
  "$model_test_directory" \
  https://example.invalid/model \
  runtime_fake_nsc \
  "$model_test_kind" \
  1 \
  1
if [ "$(cat "$model_test_kind")" != verified-existing ]; then
  echo "Runtime model bootstrap must reuse a complete verified model." >&2
  exit 1
fi
printf '%s' 'pinned model byteX' > "$model_test_directory/model.bin"
if runtime_prepare_pinned_model \
  "$model_test_manifest" \
  "$model_test_directory" \
  https://example.invalid/model \
  runtime_fake_nsc \
  "$model_test_kind" \
  1 \
  1 >/dev/null 2>&1; then
  echo "Runtime model bootstrap must fail closed when fetched bytes mismatch." >&2
  exit 1
fi

printf '%s' 'pinned model bytes' > "$model_test_directory/model.bin"
model_test_receipt="$model_test_root/receipt.txt"
runtime_write_model_receipt \
  "$model_test_manifest" \
  "$model_test_directory" \
  "$model_test_receipt" \
  1
if ! cmp -s "$model_test_manifest" "$model_test_receipt"; then
  echo "Runtime model receipt must record the verified bytes after app prewarm." >&2
  exit 1
fi

model_test_duplicate_manifest="$model_test_root/duplicate.manifest"
printf '%s %s %s\n%s %s %s\n' \
  "$model_test_sha256" "$model_test_size" model.bin \
  "$model_test_sha256" "$model_test_size" model.bin \
  > "$model_test_duplicate_manifest"
if runtime_model_manifest_shape_valid "$model_test_duplicate_manifest" 2; then
  echo "Runtime model manifest must reject duplicate paths." >&2
  exit 1
fi
model_test_truncated_manifest="$model_test_root/truncated.manifest"
printf '%s %s %s' "$model_test_sha256" "$model_test_size" model.bin \
  > "$model_test_truncated_manifest"
if runtime_model_manifest_shape_valid "$model_test_truncated_manifest" 1; then
  echo "Runtime model manifest must reject a missing final newline." >&2
  exit 1
fi
if runtime_model_manifest_shape_valid "$model_test_manifest" 2; then
  echo "Runtime model manifest must enforce the expected file count." >&2
  exit 1
fi

model_parallel_manifest="$model_test_root/parallel.manifest"
model_parallel_source_a="$model_test_root/parallel-a.source"
model_parallel_source_b="$model_test_root/parallel-b.source"
model_parallel_source_c="$model_test_root/parallel-c.source"
model_parallel_source_d="$model_test_root/parallel-d.source"
model_parallel_directory="$model_test_root/parallel-model"
model_parallel_kind="$model_test_root/parallel-kind.txt"
model_parallel_marker_a="$model_test_root/parallel-a.started"
model_parallel_marker_b="$model_test_root/parallel-b.started"
model_parallel_marker_c="$model_test_root/parallel-c.started"
model_parallel_marker_d="$model_test_root/parallel-d.started"
printf '%s' parallel-aaaa > "$model_parallel_source_a"
printf '%s' parallel-bbb > "$model_parallel_source_b"
printf '%s' parallel-cc > "$model_parallel_source_c"
printf '%s' parallel-d > "$model_parallel_source_d"
model_parallel_sha_a="$(shasum -a 256 "$model_parallel_source_a" | awk '{print $1}')"
model_parallel_sha_b="$(shasum -a 256 "$model_parallel_source_b" | awk '{print $1}')"
model_parallel_sha_c="$(shasum -a 256 "$model_parallel_source_c" | awk '{print $1}')"
model_parallel_sha_d="$(shasum -a 256 "$model_parallel_source_d" | awk '{print $1}')"
model_parallel_size_a="$(wc -c < "$model_parallel_source_a" | tr -d ' ')"
model_parallel_size_b="$(wc -c < "$model_parallel_source_b" | tr -d ' ')"
model_parallel_size_c="$(wc -c < "$model_parallel_source_c" | tr -d ' ')"
model_parallel_size_d="$(wc -c < "$model_parallel_source_d" | tr -d ' ')"
printf '%s %s %s\n%s %s %s\n%s %s %s\n%s %s %s\n' \
  "$model_parallel_sha_a" "$model_parallel_size_a" a.bin \
  "$model_parallel_sha_b" "$model_parallel_size_b" b.bin \
  "$model_parallel_sha_c" "$model_parallel_size_c" c.bin \
  "$model_parallel_sha_d" "$model_parallel_size_d" d.bin \
  > "$model_parallel_manifest"
runtime_parallel_nsc() {
  local source
  local marker
  local deadline=$((SECONDS + 3))
  case "$3" in
    */a.bin) source="$model_parallel_source_a"; marker="$model_parallel_marker_a" ;;
    */b.bin) source="$model_parallel_source_b"; marker="$model_parallel_marker_b" ;;
    */c.bin) source="$model_parallel_source_c"; marker="$model_parallel_marker_c" ;;
    */d.bin) source="$model_parallel_source_d"; marker="$model_parallel_marker_d" ;;
    *) return 2 ;;
  esac
  : > "$marker"
  while [ ! -f "$model_parallel_marker_a" ] \
    || [ ! -f "$model_parallel_marker_b" ] \
    || [ ! -f "$model_parallel_marker_c" ] \
    || [ ! -f "$model_parallel_marker_d" ]; do
    [ "$SECONDS" -lt "$deadline" ] || return 3
    sleep 0.05
  done
  cp "$source" "${4#--out=}"
}
runtime_prepare_pinned_model \
  "$model_parallel_manifest" \
  "$model_parallel_directory" \
  https://example.invalid/model \
  runtime_parallel_nsc \
  "$model_parallel_kind" \
  4
if [ "$(cat "$model_parallel_kind")" != namespace-url-artifact ] \
  || ! runtime_model_manifest_valid "$model_parallel_manifest" "$model_parallel_directory" 4; then
  echo "Runtime model bootstrap must hydrate all four default URL partitions concurrently." >&2
  exit 1
fi

model_failure_directory="$model_test_root/failure-model"
runtime_failure_nsc() {
  case "$3" in
    */a.bin) cp "$model_parallel_source_a" "${4#--out=}" ;;
    */b.bin) return 99 ;;
    */c.bin) cp "$model_parallel_source_c" "${4#--out=}" ;;
    */d.bin) cp "$model_parallel_source_d" "${4#--out=}" ;;
    *) return 2 ;;
  esac
}
if runtime_prepare_pinned_model \
  "$model_parallel_manifest" \
  "$model_failure_directory" \
  https://example.invalid/model \
  runtime_failure_nsc \
  "$model_parallel_kind" \
  4 >/dev/null 2>&1; then
  echo "Runtime model bootstrap must propagate a failed download partition." >&2
  exit 1
fi

(
  sleep 0.1
) &
model_test_job_pid=$!
runtime_wait_background_job "$model_test_job_pid"
if kill -0 "$model_test_job_pid" 2>/dev/null; then
  echo "Runtime cleanup must wait for model preparation before cache save." >&2
  exit 1
fi

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
  and ([.targets[].id] == ["textedit", "safari"])
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
if ! grep -Fq -- '- "scripts/runtime-e2e-model-bootstrap.sh"' \
  "$repo_root/.github/workflows/voiceink-remote-e2e-stage.yml"; then
  echo "Remote E2E must run when its model bootstrap changes." >&2
  exit 1
fi
if ! grep -Fq -- '- "scripts/runtime-e2e-parakeet-v2.manifest"' \
  "$repo_root/.github/workflows/voiceink-remote-e2e-stage.yml"; then
  echo "Remote E2E must run when its pinned model manifest changes." >&2
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
