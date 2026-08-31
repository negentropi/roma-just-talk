#!/usr/bin/env bash
set -euo pipefail

voiceink_app="${1:?VoiceInk app path required}"
audio_artifact="${2:-}"
evidence="${3:?evidence directory required}"
repetitions="${4:-3}"
mode="${5:-full}"
prebuilt_helper_archive="${6:-}"
require_app_translocation="${RUNTIME_E2E_REQUIRE_APP_TRANSLOCATION:-false}"

case "$repetitions" in
  1|3|5) ;;
  *)
    echo "Repetitions must be 1, 3, or 5" >&2
    exit 2
    ;;
esac

case "$mode" in
  smoke|full) ;;
  *)
    echo "Mode must be smoke or full" >&2
    exit 2
    ;;
esac
case "$require_app_translocation" in
  true|false) ;;
  *)
    echo "RUNTIME_E2E_REQUIRE_APP_TRANSLOCATION must be true or false" >&2
    exit 2
    ;;
esac

repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$repo_root/scripts/runtime-e2e-phase-runner.sh"
source "$repo_root/scripts/runtime-e2e-model-bootstrap.sh"
source "$repo_root/scripts/macos-distribution-runtime-handoff.sh"
audio_source_kind="$(runtime_audio_source_kind "$mode" "$audio_artifact")"
runtime_root="$(dirname "$evidence")/macos-runtime-e2e"
audio_root="$runtime_root/audio"
smoke_audio_root=""
helper_app="$repo_root/.local-build/Tools/RuntimeE2EHarness.app"
helper_bundle_id="com.happyf.roma-just-talk.RuntimeE2EHarness"
voiceink_bundle_id="com.negentropi.RomaJustTalk"
system_tcc_db="/Library/Application Support/com.apple.TCC/TCC.db"
user_tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
nsc_bin="${NAMESPACE_CLI:-/opt/nsc/bin/nsc}"
model_manifest="$repo_root/scripts/runtime-e2e-parakeet-v2.manifest"
model_revision="ee09c569f73759e6d44c9bd16766f477b2b36d39"
model_source_base_url="https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/$model_revision"
model_root="$HOME/Library/Application Support/FluidAudio"
model_directory="$model_root/Models/parakeet-tdt-0.6b-v2"
external_model_cache="${RUNTIME_E2E_MODEL_CACHE_PATH:-}"
expected_first_launch_pid="${RUNTIME_E2E_EXPECTED_FIRST_LAUNCH_PID:-}"
external_model_directory=""
config_smoke="$runtime_root/runtime-e2e-smoke.json"
config_full="$runtime_root/runtime-e2e-full.json"
restore_config="$config_full"
public_smoke_fixture_url="https://huggingface.co/datasets/podscripter-project/test-fixtures/resolve/6e1c1eced6e68bb35b1f1d89c56478229201a2f7/en/fleurs_en_test_3529855487992513201.wav"
public_smoke_fixture_sha256="b15246f0a22a7de701f6a6abd331edc7817ddd8795f3911af5e1c1d51cc77784"
scenario_status=1
current_phase="initialize"
phase_file="$evidence/macos-runtime-e2e-phase.txt"
distribution_verifier="$repo_root/scripts/verify-macos-distribution-launch.sh"
runtime_launch_events="$evidence/runtime-translocation-launch-events.tsv"
runtime_termination_events="$evidence/runtime-translocation-termination-events.tsv"
runtime_verified_launches="$evidence/runtime-translocation-verified-launches.tsv"
runtime_observed_pids="$evidence/runtime-translocation-observed-pids.tsv"
runtime_monitor_stop="$runtime_root/runtime-translocation-monitor-stop"
runtime_crashes_before="$evidence/runtime-translocation-crash-reports-before.txt"
runtime_crashes_after="$evidence/runtime-translocation-crash-reports-after.txt"
runtime_new_crashes="$evidence/runtime-translocation-new-crash-reports.txt"
runtime_verifier_monitor_pid=""
runtime_process_monitor_pid=""
recorded_voiceink_pid=""
launcher_pids=()
model_prepare_pid=""
model_prepare_started_seconds=0

mkdir -p "$runtime_root" "$audio_root" "$evidence"
test -d "$voiceink_app"
test -x "$nsc_bin"
command -v jq >/dev/null
command -v sqlite3 >/dev/null
command -v csreq >/dev/null
test -f "$model_manifest"
if [ "$require_app_translocation" = true ] && [ -n "$external_model_cache" ]; then
  echo "Distribution runtime handoff must not use an external model cache" >&2
  exit 2
fi
if [ -n "$external_model_cache" ]; then
  external_model_directory="$external_model_cache/$(basename "$model_directory")"
  mkdir -p "$external_model_directory" "$model_root/Models"
  if [ -e "$model_directory" ] || [ -L "$model_directory" ]; then
    existing_model_path="$(
      cd "$model_directory" 2>/dev/null && pwd -P || true
    )"
    expected_model_path="$(cd "$external_model_directory" && pwd -P)"
    if [ "$existing_model_path" != "$expected_model_path" ]; then
      echo "The runtime model already exists outside the isolated cache" >&2
      exit 2
    fi
  else
    ln -s "$external_model_directory" "$model_directory"
  fi
fi

mark_phase() {
  current_phase="$1"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$current_phase" \
    | tee -a "$phase_file"
}

write_roma_crash_report_inventory() {
  local output="$1"
  local crash_root="$HOME/Library/Logs/DiagnosticReports"
  : > "$output"
  [[ -d "$crash_root" ]] || return 0
  find "$crash_root" -type f \
    \( -name 'roma just talk*.ips' -o -name 'roma just talk*.crash' \) \
    -print 2>/dev/null \
    | LC_ALL=C sort \
    > "$output"
}

monitor_runtime_processes() {
  local seen=$'\n'
  local candidate_pid=""
  while [ ! -e "$runtime_monitor_stop" ]; do
    while IFS= read -r candidate_pid; do
      [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue
      if [[ "$seen" == *$'\n'"$candidate_pid"$'\n'* ]]; then
        continue
      fi
      seen+="$candidate_pid"$'\n'
      printf '%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$candidate_pid" \
        >> "$runtime_observed_pids"
    done < <(pgrep -x "roma just talk" 2>/dev/null | LC_ALL=C sort -n || true)
    sleep 0.05
  done
}

verify_runtime_launch_events() {
  local processed=0
  local line_count=0
  local event=""
  local timestamp=""
  local launched_pid=""
  local source_sha=""
  local running_sha=""
  local source_path=""
  local running_path=""
  local launch_evidence=""

  while true; do
    line_count="$(awk 'END { print NR + 0 }' "$runtime_launch_events")"
    while (( processed < line_count )); do
      event="$(sed -n "$((processed + 1))p" "$runtime_launch_events")"
      IFS=$'\t' read -r \
        timestamp launched_pid source_sha running_sha source_path running_path \
        <<< "$event"
      [[ "$launched_pid" =~ ^[0-9]+$ ]] || return 1
      [[ -n "$source_sha" && "$source_sha" = "$running_sha" ]] || return 1
      [[ "$source_path" = "$voiceink_app" ]] || return 1
      case "$running_path" in
        */AppTranslocation/*/d/*.app) ;;
        *) return 1 ;;
      esac
      launch_evidence="$evidence/runtime-translocation-pid-$launched_pid"
      if ! DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=true \
        DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED=true \
        DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION="${RUNTIME_E2E_EXPECTED_MACOS_VERSION:-}" \
        DISTRIBUTION_E2E_EXPECTED_MACOS_BUILD="${RUNTIME_E2E_EXPECTED_MACOS_BUILD:-}" \
        DISTRIBUTION_E2E_EXPECTED_QUARANTINE_AGENT=Safari \
        DISTRIBUTION_E2E_CAPTURE_MAPPED_CODE_UNTIL_EXIT=true \
        DISTRIBUTION_E2E_CAPTURE_TIMEOUT_SECONDS=1500 \
        DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
        bash "$distribution_verifier" \
          "$voiceink_app" \
          "$launched_pid" \
          "$launch_evidence"; then
        return 1
      fi
      printf '%s\t%s\t%s\t%s\n' \
        "$timestamp" "$launched_pid" "$source_sha" "$running_path" \
        >> "$runtime_verified_launches"
      processed=$((processed + 1))
      line_count="$(awk 'END { print NR + 0 }' "$runtime_launch_events")"
    done
    if [ -e "$runtime_monitor_stop" ]; then
      return 0
    fi
    sleep 0.05
  done
}

start_runtime_translocation_monitors() {
  test -x "$distribution_verifier"
  rm -f "$runtime_monitor_stop"
  : > "$runtime_launch_events"
  : > "$runtime_termination_events"
  : > "$runtime_verified_launches"
  : > "$runtime_observed_pids"
  write_roma_crash_report_inventory "$runtime_crashes_before"
  export RUNTIME_E2E_VOICEINK_LAUNCH_EVENTS="$runtime_launch_events"
  export RUNTIME_E2E_VOICEINK_TERMINATION_EVENTS="$runtime_termination_events"
  monitor_runtime_processes &
  runtime_process_monitor_pid=$!
  verify_runtime_launch_events &
  runtime_verifier_monitor_pid=$!
}

record_running_voiceink_launch() {
  local launched_pid=""
  local process_files="$runtime_root/prewarm-process-open-files.txt"
  local executable_name=""
  local running_executable=""
  local running_bundle=""
  local source_executable=""
  local source_sha=""
  local running_sha=""
  local launch_deadline=$((SECONDS + 30))

  while (( SECONDS < launch_deadline )); do
    launched_pid="$(pgrep -x "roma just talk" 2>/dev/null || true)"
    if [[ "$launched_pid" =~ ^[0-9]+$ ]]; then
      break
    fi
    if [[ "$launched_pid" == *$'\n'* ]]; then
      echo "More than one Roma process appeared during runtime prewarm" >&2
      return 1
    fi
    sleep 0.1
  done
  [[ "$launched_pid" =~ ^[0-9]+$ ]] || return 1
  executable_name="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
      "$voiceink_app/Contents/Info.plist"
  )"
  source_executable="$voiceink_app/Contents/MacOS/$executable_name"
  while (( SECONDS < launch_deadline )); do
    lsof -p "$launched_pid" -Ffn > "$process_files" 2>/dev/null || true
    running_executable="$(
      awk -v suffix="/Contents/MacOS/$executable_name" '
        $0 == "ftxt" { is_text = 1; next }
        /^f/ { is_text = 0; next }
        is_text && /^n/ {
          path = substr($0, 2)
          if (substr(path, length(path) - length(suffix) + 1) == suffix) {
            print path
            exit
          }
        }
      ' "$process_files"
    )"
    [[ -n "$running_executable" ]] && break
    sleep 0.1
  done
  [[ -n "$running_executable" ]] || return 1
  running_bundle="${running_executable%/Contents/MacOS/$executable_name}"
  source_sha="$(shasum -a 256 "$source_executable" | awk '{print $1}')"
  running_sha="$(shasum -a 256 "$running_executable" | awk '{print $1}')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$launched_pid" \
    "$source_sha" \
    "$running_sha" \
    "$voiceink_app" \
    "$running_bundle" \
    >> "$runtime_launch_events"
  recorded_voiceink_pid="$launched_pid"
}

log_contains_since() {
  local start_line="$1"
  local needle="$2"
  local log_file="$3"
  awk -v start_line="$start_line" -v needle="$needle" '
    NR >= start_line && index($0, needle) { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$log_file"
}

refresh_process_log_since() {
  local process_pid="$1"
  local started_at="$2"
  local output="$3"
  /usr/bin/log show \
    --start "$started_at" \
    --style compact \
    --predicate "processIdentifier == $process_pid" \
    > "$output" 2>&1 || true
}

terminate_runtime_voiceink_pid() {
  local process_pid="$1"
  local termination_result=""
  printf '%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$process_pid" \
    >> "$runtime_termination_events"
  termination_result="$(
    RUNTIME_E2E_TERMINATE_PID="$process_pid" \
      /usr/bin/osascript -l JavaScript -e '
        ObjC.import("AppKit")
        const pid = Number(ObjC.unwrap(
          $.NSProcessInfo.processInfo.environment.objectForKey(
            "RUNTIME_E2E_TERMINATE_PID"
          )
        ))
        const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid)
        app ? ObjC.unwrap(app.terminate) : false
      ' 2>/dev/null || true
  )"
  if [ "$termination_result" != true ]; then
    echo "Could not request normal termination for Roma PID $process_pid" >&2
    return 1
  fi
  local process_deadline=$((SECONDS + 15))
  while kill -0 "$process_pid" 2>/dev/null; do
    if (( SECONDS >= process_deadline )); then
      echo "Roma PID $process_pid did not terminate normally" >&2
      return 1
    fi
    sleep 0.1
  done
}

stop_runtime_translocation_monitors() {
  local verifier_status=0
  touch "$runtime_monitor_stop"
  if [ -n "$runtime_process_monitor_pid" ]; then
    wait "$runtime_process_monitor_pid" 2>/dev/null || true
    runtime_process_monitor_pid=""
  fi
  if [ -n "$runtime_verifier_monitor_pid" ]; then
    wait "$runtime_verifier_monitor_pid" || verifier_status=$?
    runtime_verifier_monitor_pid=""
  fi
  return "$verifier_status"
}

require_verified_runtime_processes() {
  local observed="$runtime_root/runtime-observed-pids.txt"
  local launched="$runtime_root/runtime-launched-pids.txt"
  local verified="$runtime_root/runtime-verified-pids.txt"
  local terminated="$runtime_root/runtime-terminated-pids.txt"
  awk -F '\t' 'NF >= 2 { print $2 }' "$runtime_observed_pids" \
    | LC_ALL=C sort -nu > "$observed"
  awk -F '\t' 'NF >= 2 { print $2 }' "$runtime_launch_events" \
    | LC_ALL=C sort -nu > "$launched"
  awk -F '\t' 'NF >= 2 { print $2 }' "$runtime_verified_launches" \
    | LC_ALL=C sort -nu > "$verified"
  awk -F '\t' 'NF >= 2 { print $2 }' "$runtime_termination_events" \
    | LC_ALL=C sort -nu > "$terminated"
  test -s "$observed"
  cmp -s "$observed" "$launched"
  cmp -s "$launched" "$verified"
  cmp -s "$launched" "$terminated"
  sleep 10
  write_roma_crash_report_inventory "$runtime_crashes_after"
  comm -13 "$runtime_crashes_before" "$runtime_crashes_after" \
    > "$runtime_new_crashes"
  if [ -s "$runtime_new_crashes" ]; then
    mkdir -p "$evidence/runtime-translocation-crash-reports"
    while IFS= read -r crash_report; do
      cp "$crash_report" "$evidence/runtime-translocation-crash-reports/" \
        2>/dev/null || true
    done < "$runtime_new_crashes"
    return 1
  fi
  {
    printf 'runtime_translocation_verdict=passed\n'
    printf 'observed_pid_count=%s\n' "$(awk 'NF { count++ } END { print count + 0 }' "$observed")"
    printf 'source_app=%s\n' "$voiceink_app"
    printf 'new_crash_report_count=0\n'
  } > "$evidence/runtime-translocation-verdict.txt"
}

launch_detached() {
  local output="$1"
  shift
  open "$@" > "$output" 2>&1 &
  launcher_pids+=("$!")
}

stop_launchers() {
  local pid
  for pid in "${launcher_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  launcher_pids=()
}

finish_model_prepare() {
  runtime_wait_background_job "$model_prepare_pid"
  model_prepare_pid=""
}

record_command() {
  local output="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } > "$output" 2>&1
}

capture_tcc() {
  local phase="$1"
  sudo sqlite3 -header -column "$system_tcc_db" \
    "select service,client,client_type,auth_value,auth_reason,length(csreq) as csreq_length,last_modified from access where client in ('$voiceink_bundle_id','$helper_bundle_id') order by client,service;" \
    > "$evidence/tcc-system-$phase.txt"
  sqlite3 -header -column "$user_tcc_db" \
    "select service,client,client_type,auth_value,auth_reason,indirect_object_identifier,length(csreq) as csreq_length,length(indirect_object_code_identity) as indirect_identity_length,last_modified from access where client in ('$voiceink_bundle_id','$helper_bundle_id') order by client,service,indirect_object_identifier;" \
    > "$evidence/tcc-user-$phase.txt"
}

make_csreq() {
  local app="$1"
  local output="$2"
  local requirement
  requirement="$(codesign -dr - "$app" 2>&1 | sed -n \
    -e 's/^# designated => //p' \
    -e 's/^designated => //p')"
  test -n "$requirement"
  printf '%s\n' "$requirement" | csreq -r- -b "$output"
  printf '%s\n' "$requirement"
}

grant_system_tcc() {
  local service="$1"
  local client="$2"
  local csreq_path="$3"
  sudo sqlite3 "$system_tcc_db" <<SQL
INSERT OR REPLACE INTO access(
  service,client,client_type,auth_value,auth_reason,auth_version,csreq,
  indirect_object_identifier_type,indirect_object_identifier,flags
) VALUES(
  '$service','$client',0,2,4,1,readfile('$csreq_path'),0,'UNUSED',0
);
SQL
}

grant_user_tcc() {
  local service="$1"
  local client="$2"
  local csreq_path="$3"
  sqlite3 "$user_tcc_db" <<SQL
INSERT OR REPLACE INTO access(
  service,client,client_type,auth_value,auth_reason,auth_version,csreq,
  indirect_object_identifier_type,indirect_object_identifier,flags
) VALUES(
  '$service','$client',0,2,4,1,readfile('$csreq_path'),0,'UNUSED',0
);
SQL
}

write_config() {
  local output="$1"
  local config_audio_directory="$2"
  local run_repetitions="$3"
  local latency_threshold="$4"
  local config_mode="$5"
  runtime_e2e_config_json \
    "$config_audio_directory" \
    "$voiceink_app" \
    "$run_repetitions" \
    "$latency_threshold" \
    "$config_mode" \
    > "$output"
}

run_harness_phase() {
  local phase="$1"
  local make_target="$2"
  local config="$3"
  local report="$evidence/$phase.json"
  local stdout="$evidence/$phase.stdout.log"
  local stderr="$evidence/$phase.stderr.log"
  local command_log="$evidence/$phase.command.log"

  set +e
  make -C "$repo_root" "$make_target" \
    RUNTIME_E2E_APP="$helper_app" \
    RUNTIME_E2E_CONFIG="$config" \
    RUNTIME_E2E_REPORT="$report" \
    RUNTIME_E2E_STDOUT="$stdout" \
    RUNTIME_E2E_STDERR="$stderr" \
    > "$command_log" 2>&1
  local exit_code=$?
  set -e
  printf '%s\n' "$exit_code" > "$evidence/$phase.exit-code.txt"
  return "$exit_code"
}

cleanup() {
  local exit_code=$?
  set +e
  if [ "$exit_code" -ne 0 ]; then
    scenario_status="$exit_code"
  fi
  finish_model_prepare
  stop_launchers
  if [ -x "$helper_app/Contents/MacOS/RuntimeE2EHarness" ]; then
    make -C "$repo_root" runtime-e2e-restore \
      RUNTIME_E2E_APP="$helper_app" \
      RUNTIME_E2E_CONFIG="$restore_config" \
      > "$evidence/restore.log" 2>&1
  fi
  if [ "$require_app_translocation" = true ]; then
    pkill -9 -x "roma just talk" 2>/dev/null || true
  fi
  stop_runtime_translocation_monitors || true
  defaults read "$voiceink_bundle_id" > "$evidence/voiceink-defaults-final.txt" 2>&1
  system_profiler SPAudioDataType > "$evidence/audio-final.txt" 2>&1
  capture_tcc cleanup || true
  /usr/bin/log show --last 15m --style compact \
    --predicate 'subsystem == "com.apple.TCC" && (eventMessage CONTAINS[c] "RuntimeE2EHarness" || eventMessage CONTAINS[c] "ScreenCapture")' \
    > "$evidence/tcc-runtime.log" 2>&1 || true
  printf '%s\n' "$current_phase" > "$evidence/macos-runtime-e2e-final-phase.txt"
  printf '%s\n' "$scenario_status" > "$evidence/macos-runtime-e2e-exit-code.txt"
}
trap cleanup EXIT

if [ "$require_app_translocation" = true ]; then
  observed_voiceink_pids="$(pgrep -x "roma just talk" 2>/dev/null || true)"
  distribution_runtime_validate_handoff \
    "$expected_first_launch_pid" \
    "$observed_voiceink_pids" \
    "$model_directory" \
    "$external_model_cache"
  terminate_runtime_voiceink_pid "$expected_first_launch_pid"
  {
    printf 'distribution_runtime_handoff=passed\n'
    printf 'first_launch_pid=%s\n' "$expected_first_launch_pid"
    printf 'first_launch_termination=normal\n'
    printf 'runtime_model_directory=%s\n' "$model_directory"
    printf 'external_model_cache=%s\n' "${external_model_cache:-absent}"
  } > "$evidence/distribution-runtime-handoff.txt"
  while IFS= read -r first_launch_model_file; do
    first_launch_relative_path="${first_launch_model_file#"$model_directory"/}"
    first_launch_size="$(stat -f '%z' "$first_launch_model_file")"
    first_launch_sha256="$(shasum -a 256 "$first_launch_model_file" | awk '{print $1}')"
    printf '%s %s %s\n' \
      "$first_launch_sha256" \
      "$first_launch_size" \
      "$first_launch_relative_path"
  done < <(find "$model_directory" -type f -print | LC_ALL=C sort) \
    > "$evidence/first-launch-live-model-files-after-termination.sha256"
  : > "$runtime_termination_events"
else
  pkill -9 -x "roma just talk" 2>/dev/null || true
fi

printf '%s\n' "${RUNTIME_MODEL_CACHE_HIT:-false}" > "$evidence/model-cache-hit.txt"
printf '%s\n' "$model_revision" > "$evidence/model-source-revision.txt"
printf '%s\n' "$model_source_base_url" > "$evidence/model-source-url.txt"
cp "$model_manifest" "$evidence/model-source-manifest.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$evidence/model-prepare-started-at.txt"
model_prepare_started_seconds=$SECONDS
runtime_prepare_pinned_model \
  "$model_manifest" \
  "$model_directory" \
  "$model_source_base_url" \
  "$nsc_bin" \
  "$evidence/model-source-kind.txt" \
  > "$evidence/model-prepare.log" 2>&1 &
model_prepare_pid=$!

mark_phase install-dependencies
record_command "$evidence/blackhole-install.log" \
  env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
  brew install --cask blackhole-2ch
if [ "$mode" = "full" ] && [ ! -d "/Applications/Google Chrome.app" ]; then
  record_command "$evidence/chrome-install.log" \
    env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install --cask google-chrome
fi
if [ "$mode" = "full" ] && [ ! -d "/Applications/Visual Studio Code.app" ]; then
  record_command "$evidence/vscode-install.log" \
    env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install --cask visual-studio-code
fi
if ! command -v fd >/dev/null 2>&1; then
  record_command "$evidence/fd-install.log" \
    env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install fd
fi
sudo killall coreaudiod 2>/dev/null || true
sleep 4
system_profiler SPAudioDataType > "$evidence/audio-after-install.txt"
grep -q "BlackHole 2ch" "$evidence/audio-after-install.txt"

mark_phase stage-audio-fixtures
if [ "$audio_source_kind" = public ]; then
  audio_directory="$audio_root/public"
  public_fixture="$audio_directory/public quick release.wav"
  mkdir -p "$audio_directory"
  "$nsc_bin" artifact cache-url "$public_smoke_fixture_url" \
    --out="$public_fixture" \
    > "$evidence/audio-artifact-download.log" 2>&1
  actual_public_fixture_sha256="$(shasum -a 256 "$public_fixture" | awk '{print $1}')"
  test "$actual_public_fixture_sha256" = "$public_smoke_fixture_sha256"
  printf '%s\n' "$public_smoke_fixture_url" > "$evidence/audio-source-url.txt"
  printf '%s\n' "$actual_public_fixture_sha256" > "$evidence/audio-source-sha256.txt"
else
  "$nsc_bin" artifact download "$audio_artifact" "$runtime_root/audio.zip" \
    > "$evidence/audio-artifact-download.log" 2>&1
  ditto -x -k "$runtime_root/audio.zip" "$audio_root"
fi
first_fixture="$(fd -a -t f -e wav -e wave -e aif -e aiff -e caf -e m4a -e mp3 -e flac . "$audio_root" | sort | head -n 1)"
test -n "$first_fixture"
audio_directory="$(dirname "$first_fixture")"
fixture_count="$(fd -a -t f -e wav -e wave -e aif -e aiff -e caf -e m4a -e mp3 -e flac . "$audio_directory" | wc -l | tr -d ' ')"
minimum_fixture_count=1
if [ "$mode" = full ]; then
  minimum_fixture_count=2
fi
test "$fixture_count" -ge "$minimum_fixture_count"
while IFS= read -r fixture; do
  shasum -a 256 "$fixture"
  afinfo "$fixture"
done < <(fd -a -t f -e wav -e wave -e aif -e aiff -e caf -e m4a -e mp3 -e flac . "$audio_directory" | sort) \
  > "$evidence/audio-fixtures.txt"

smoke_audio_root="$(mktemp -d "$runtime_root/audio-smoke.XXXXXX")"
smoke_fixture="$(select_runtime_smoke_fixture "$audio_directory" 8)"
smoke_fixture_duration="$(runtime_audio_duration_seconds "$smoke_fixture")"
ln -sfn "$smoke_fixture" "$smoke_audio_root/$(basename "$smoke_fixture")"
printf '%s\n' "$smoke_fixture" > "$evidence/smoke-audio-fixture.txt"
printf '%s\n' "$smoke_fixture_duration" > "$evidence/smoke-audio-duration-seconds.txt"

mark_phase build-helper
if [ -n "$prebuilt_helper_archive" ]; then
  test -f "$prebuilt_helper_archive"
  prebuilt_helper_root="$runtime_root/prebuilt-helper"
  test ! -e "$prebuilt_helper_root"
  mkdir -p "$prebuilt_helper_root"
  ditto -x -k "$prebuilt_helper_archive" "$prebuilt_helper_root"
  helper_candidates=()
  while IFS= read -r candidate; do
    helper_candidates+=("$candidate")
  done < <(
    find "$prebuilt_helper_root" \
      -type d \
      -name 'RuntimeE2EHarness.app' \
      -print
  )
  test "${#helper_candidates[@]}" -eq 1
  helper_app="${helper_candidates[0]}"
  printf 'helper_source=prebuilt_build_artifact\nhelper_archive=%s\n' \
    "$prebuilt_helper_archive" \
    > "$evidence/helper-provenance.txt"
  printf 'skipped: using prebuilt helper artifact\n' \
    > "$evidence/harness-check.log"
  printf 'skipped: using prebuilt helper artifact\n' \
    > "$evidence/harness-build.log"
else
  make -C "$repo_root" runtime-e2e-check > "$evidence/harness-check.log" 2>&1
  make -C "$repo_root" runtime-e2e-app > "$evidence/harness-build.log" 2>&1
  printf 'helper_source=built_on_runtime_host\n' \
    > "$evidence/helper-provenance.txt"
fi
helper_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$helper_app/Contents/Info.plist"
)"
helper_minimum_system="$(
  /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$helper_app/Contents/Info.plist"
)"
test "$helper_identifier" = "$helper_bundle_id"
test "$helper_minimum_system" = "14.0"
file "$helper_app/Contents/MacOS/RuntimeE2EHarness" \
  | grep -Fq 'arm64'
codesign --verify --deep --strict --verbose=4 "$helper_app" \
  > "$evidence/helper-codesign-verify.txt" 2>&1
codesign -dv --verbose=4 "$helper_app" > "$evidence/helper-codesign.txt" 2>&1
otool -l "$helper_app/Contents/MacOS/RuntimeE2EHarness" \
  > "$evidence/helper-load-commands.txt"
awk '
  $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build = 1; next }
  in_build && $1 == "minos" && $2 == "14.0" { found = 1; in_build = 0 }
  END { exit(found ? 0 : 1) }
' "$evidence/helper-load-commands.txt"
codesign -dv --verbose=4 "$voiceink_app" > "$evidence/voiceink-codesign.txt" 2>&1
shasum -a 256 "$helper_app/Contents/MacOS/RuntimeE2EHarness" > "$evidence/helper-sha256.txt"
shasum -a 256 "$voiceink_app/Contents/MacOS/roma just talk" > "$evidence/voiceink-sha256.txt"

mark_phase verify-helper-host-loadability
pkill -9 -x RuntimeE2EHarness 2>/dev/null || true
set +e
"$helper_app/Contents/MacOS/RuntimeE2EHarness" --help \
  > "$evidence/helper-host-launch.stdout.log" \
  2> "$evidence/helper-host-launch.stderr.log"
helper_host_launch_status=$?
set -e
printf '%s\n' "$helper_host_launch_status" \
  > "$evidence/helper-host-launch.exit-code.txt"
if [ "$helper_host_launch_status" -ne 0 ] \
  || ! grep -Fq 'Usage:' "$evidence/helper-host-launch.stdout.log"; then
  echo "Runtime E2E helper did not launch on this macOS host" >&2
  exit 11
fi
if pgrep -x RuntimeE2EHarness >/dev/null; then
  echo "Runtime E2E helper did not exit after its host loadability probe" >&2
  exit 11
fi
{
  printf 'helper_host_loadability=passed\n'
  printf 'product_version=%s\n' "$(sw_vers -productVersion)"
  printf 'build_version=%s\n' "$(sw_vers -buildVersion)"
  printf 'host_architecture=%s\n' "$(uname -m)"
  printf 'helper_bundle_id=%s\n' "$helper_identifier"
  printf 'helper_minimum_system_version=%s\n' "$helper_minimum_system"
  printf 'helper_launch_method=direct_bundle_executable\n'
  printf 'helper_launch_exit_code=%s\n' "$helper_host_launch_status"
  printf 'helper_executable_sha256=%s\n' "$(awk 'NR == 1 { print $1 }' "$evidence/helper-sha256.txt")"
} > "$evidence/helper-host-loadability.txt"

killall tccd 2>/dev/null || true
sudo killall tccd 2>/dev/null || true
sleep 2
mark_phase grant-tcc
capture_tcc before-grant
voiceink_requirement="$(make_csreq "$voiceink_app" "$runtime_root/voiceink.csreq")"
helper_requirement="$(make_csreq "$helper_app" "$runtime_root/helper.csreq")"
printf '%s\n' "$voiceink_requirement" > "$evidence/voiceink-designated-requirement.txt"
printf '%s\n' "$helper_requirement" > "$evidence/helper-designated-requirement.txt"

grant_system_tcc kTCCServiceAccessibility "$voiceink_bundle_id" "$runtime_root/voiceink.csreq"
grant_system_tcc kTCCServiceListenEvent "$voiceink_bundle_id" "$runtime_root/voiceink.csreq"
grant_system_tcc kTCCServicePostEvent "$voiceink_bundle_id" "$runtime_root/voiceink.csreq"
grant_user_tcc kTCCServiceMicrophone "$voiceink_bundle_id" "$runtime_root/voiceink.csreq"
grant_system_tcc kTCCServiceAccessibility "$helper_bundle_id" "$runtime_root/helper.csreq"
grant_system_tcc kTCCServicePostEvent "$helper_bundle_id" "$runtime_root/helper.csreq"
grant_system_tcc kTCCServiceScreenCapture "$helper_bundle_id" "$runtime_root/helper.csreq"
grant_user_tcc kTCCServiceScreenCapture "$helper_bundle_id" "$runtime_root/helper.csreq"
capture_tcc after-grant
killall tccd 2>/dev/null || true
sudo killall tccd 2>/dev/null || true
sleep 2

defaults write "$voiceink_bundle_id" hasCompletedOnboarding -bool true
defaults delete "$voiceink_bundle_id" macOSOnboardingStage 2>/dev/null || true
defaults delete "$voiceink_bundle_id" macOSOnboardingPermissionKind 2>/dev/null || true
defaults write "$voiceink_bundle_id" CurrentTranscriptionModel -string "parakeet-tdt-0.6b-v2"
defaults write "$voiceink_bundle_id" PrewarmModelOnWake -bool true
defaults write "$voiceink_bundle_id" isSoundFeedbackEnabled -bool false
defaults write "$voiceink_bundle_id" enableAnnouncements -bool false
defaults write "$voiceink_bundle_id" restoreClipboardAfterPaste -bool false
defaults write "$voiceink_bundle_id" appendTrailingSpace -bool false
killall cfprefsd 2>/dev/null || true

mark_phase prewarm-model
wait "$model_prepare_pid"
model_prepare_pid=""
printf '%s\n' "$((SECONDS - model_prepare_started_seconds))" \
  > "$evidence/model-prepare-wall-seconds.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$evidence/model-prepare-completed-at.txt"
printf '%s\n' false > "$evidence/model-prewarm-completed.txt"
if [ "$require_app_translocation" = true ]; then
  start_runtime_translocation_monitors
fi
prewarm_log_start="$(awk 'END { print NR + 1 }' "$evidence/macos-app.log")"
prewarm_started_at="$(date '+%Y-%m-%d %H:%M:%S')"
open -na "$voiceink_app"
if [ "$require_app_translocation" = true ]; then
  record_running_voiceink_launch
  prewarm_pid="$recorded_voiceink_pid"
fi
model_deadline=$((SECONDS + 1200))
while (( SECONDS < model_deadline )); do
  if [ "$require_app_translocation" = true ]; then
    refresh_process_log_since \
      "$prewarm_pid" "$prewarm_started_at" \
      "$evidence/model-prewarm-process.log"
    if grep -Fq "Prewarm completed" "$evidence/model-prewarm-process.log"; then
      break
    fi
    if grep -Fq "Prewarm failed" "$evidence/model-prewarm-process.log"; then
      echo "VoiceInk model prewarm failed" >&2
      exit 10
    fi
    if ! kill -0 "$prewarm_pid" 2>/dev/null; then
      echo "VoiceInk exited before model prewarm completed" >&2
      exit 10
    fi
  else
    if log_contains_since \
      "$prewarm_log_start" "Prewarm completed" "$evidence/macos-app.log"; then
      break
    fi
    if log_contains_since \
      "$prewarm_log_start" "Prewarm failed" "$evidence/macos-app.log"; then
      echo "VoiceInk model prewarm failed" >&2
      exit 10
    fi
  fi
  sleep 5
done
if [ "$require_app_translocation" = true ]; then
  refresh_process_log_since \
    "$prewarm_pid" "$prewarm_started_at" \
    "$evidence/model-prewarm-process.log"
  grep -Fq "Prewarm completed" "$evidence/model-prewarm-process.log"
else
  log_contains_since \
    "$prewarm_log_start" "Prewarm completed" "$evidence/macos-app.log"
fi
printf '%s\n' true > "$evidence/model-prewarm-completed.txt"
runtime_write_model_receipt \
  "$model_manifest" \
  "$model_directory" \
  "$evidence/model-runtime-receipt.txt"
printf '%s\n' verified > "$evidence/model-runtime-manifest-verification.txt"
fd -L -a -d 4 . "$model_root" | sort > "$evidence/model-cache-tree.txt" 2>&1 || true
if [ -d "$model_directory" ]; then
  printf '%s\n' "$model_directory" > "$evidence/model-cache-directory.txt"
  {
    ls -ld "$model_root/Models" "$model_directory"
    readlink "$model_directory" || true
    df -h "$model_root/Models"
    mount | grep -F '/Volumes/cache' || true
  } > "$evidence/model-cache-mount.txt" 2>&1
  du -sh "$model_directory" > "$evidence/model-cache-size.txt" 2>&1 || true
  while IFS= read -r model_file; do
    stat -f '%z %N' "$model_file"
  done < <(fd -a -t f . "$model_directory" | sort) \
    > "$evidence/model-cache-files.txt" 2>&1 || true
fi

if [ "$require_app_translocation" = true ]; then
  [[ "$prewarm_pid" =~ ^[0-9]+$ ]]
  terminate_runtime_voiceink_pid "$prewarm_pid"
fi

mark_phase open-target-apps
if [ "$mode" = "full" ]; then
  mkdir -p "$HOME/Library/Application Support/Google/Chrome"
  touch "$HOME/Library/Application Support/Google/Chrome/First Run"
  mkdir -p "$HOME/Library/Application Support/Code/User"
  printf '%s\n' \
    '{' \
    '  "editor.accessibilitySupport": "on",' \
    '  "security.workspace.trust.enabled": false,' \
    '  "window.openFilesInNewWindow": "off",' \
    '  "window.restoreWindows": "none",' \
    '  "workbench.startupEditor": "none"' \
    '}' > "$HOME/Library/Application Support/Code/User/settings.json"
fi
lsregister_bin="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ "$mode" = "full" ]; then
  test -x "$lsregister_bin"
  "$lsregister_bin" -f \
    "/Applications/Google Chrome.app" \
    "/Applications/Visual Studio Code.app" \
    > "$evidence/app-registration.log" 2>&1
fi
launch_detached "$evidence/textedit-launch.log" -b com.apple.TextEdit
launch_detached "$evidence/safari-launch.log" -b com.apple.Safari
if [ "$mode" = "full" ]; then
  launch_detached "$evidence/chrome-launch.log" \
    -na "/Applications/Google Chrome.app" --args \
    --force-renderer-accessibility --no-first-run --no-default-browser-check about:blank
  launch_detached "$evidence/vscode-launch.log" \
    -na "/Applications/Visual Studio Code.app" --args \
    --force-renderer-accessibility --disable-extensions --skip-welcome
fi
sleep 15
stop_launchers

write_config "$config_smoke" "$smoke_audio_root" 1 20000 smoke
write_config "$config_full" "$audio_directory" "$repetitions" 250 full
if [ "$mode" = "smoke" ]; then
  restore_config="$config_smoke"
fi
cp "$config_smoke" "$evidence/runtime-e2e-smoke-config.json"
if [ "$mode" = "full" ]; then
  cp "$config_full" "$evidence/runtime-e2e-full-config.json"
fi

scenario_status=0
run_runtime_e2e_phases "$config_smoke" "$config_full" "$mode"
if [ "$require_app_translocation" = true ]; then
  if ! stop_runtime_translocation_monitors \
    || ! require_verified_runtime_processes; then
    printf 'runtime_translocation_verdict=failed\n' \
      > "$evidence/runtime-translocation-verdict.txt"
    scenario_status=12
  fi
fi

summary_report="$evidence/runtime-e2e-report.json"
if [ "$mode" = "smoke" ]; then
  summary_report="$evidence/functional-smoke.json"
fi
if [ -f "$summary_report" ]; then
  jq '{summary, fatalError, restoredOriginalState}' \
    "$summary_report" > "$evidence/runtime-e2e-summary.json"
  jq '[.cases[] | select(.assessment.passed | not) | {
    id,
    target: .target.id,
    fixture: (.fixturePath | split("/") | last),
    status: .assessment.status,
    failureBoundary,
    evidence,
    error
  }]' "$summary_report" > "$evidence/runtime-e2e-failures.json"
fi

capture_tcc final
defaults read "$voiceink_bundle_id" > "$evidence/voiceink-defaults-before-cleanup.txt" 2>&1
mark_phase complete
exit "$scenario_status"
