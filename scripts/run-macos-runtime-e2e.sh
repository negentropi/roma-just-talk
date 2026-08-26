#!/usr/bin/env bash
set -euo pipefail

voiceink_app="${1:?VoiceInk app path required}"
audio_artifact="${2:-}"
evidence="${3:?evidence directory required}"
repetitions="${4:-3}"
mode="${5:-full}"

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

repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$repo_root/scripts/runtime-e2e-phase-runner.sh"
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
config_smoke="$runtime_root/runtime-e2e-smoke.json"
config_full="$runtime_root/runtime-e2e-full.json"
restore_config="$config_full"
public_smoke_fixture_url="https://huggingface.co/datasets/podscripter-project/test-fixtures/resolve/6e1c1eced6e68bb35b1f1d89c56478229201a2f7/en/fleurs_en_test_3529855487992513201.wav"
public_smoke_fixture_sha256="b15246f0a22a7de701f6a6abd331edc7817ddd8795f3911af5e1c1d51cc77784"
scenario_status=1
current_phase="initialize"
phase_file="$evidence/macos-runtime-e2e-phase.txt"
launcher_pids=()

mkdir -p "$runtime_root" "$audio_root" "$evidence"
test -d "$voiceink_app"
test -x "$nsc_bin"
command -v jq >/dev/null
command -v sqlite3 >/dev/null
command -v csreq >/dev/null

mark_phase() {
  current_phase="$1"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$current_phase" \
    | tee -a "$phase_file"
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
  stop_launchers
  if [ -x "$helper_app/Contents/MacOS/RuntimeE2EHarness" ]; then
    make -C "$repo_root" runtime-e2e-restore \
      RUNTIME_E2E_CONFIG="$restore_config" \
      > "$evidence/restore.log" 2>&1
  fi
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

mark_phase install-dependencies
record_command "$evidence/blackhole-install.log" \
  env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
  brew install --cask blackhole-2ch
if [ ! -d "/Applications/Google Chrome.app" ]; then
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
make -C "$repo_root" runtime-e2e-check > "$evidence/harness-check.log" 2>&1
make -C "$repo_root" runtime-e2e-app > "$evidence/harness-build.log" 2>&1
codesign -dv --verbose=4 "$helper_app" > "$evidence/helper-codesign.txt" 2>&1
codesign -dv --verbose=4 "$voiceink_app" > "$evidence/voiceink-codesign.txt" 2>&1
shasum -a 256 "$helper_app/Contents/MacOS/RuntimeE2EHarness" > "$evidence/helper-sha256.txt"
shasum -a 256 "$voiceink_app/Contents/MacOS/roma just talk" > "$evidence/voiceink-sha256.txt"

pkill -9 -x "roma just talk" 2>/dev/null || true
pkill -9 -x RuntimeE2EHarness 2>/dev/null || true
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
printf '%s\n' "${RUNTIME_MODEL_CACHE_HIT:-false}" > "$evidence/model-cache-hit.txt"
printf '%s\n' false > "$evidence/model-prewarm-completed.txt"
open -na "$voiceink_app"
model_deadline=$((SECONDS + 1200))
while (( SECONDS < model_deadline )); do
  if grep -Fq "Prewarm completed" "$evidence/macos-app.log"; then
    break
  fi
  if grep -Fq "Prewarm failed" "$evidence/macos-app.log"; then
    echo "VoiceInk model prewarm failed" >&2
    exit 10
  fi
  sleep 5
done
grep -Fq "Prewarm completed" "$evidence/macos-app.log"
printf '%s\n' true > "$evidence/model-prewarm-completed.txt"
model_root="$HOME/Library/Application Support/FluidAudio"
model_directory="$model_root/Models/parakeet-tdt-0.6b-v2"
fd -L -a -d 4 . "$model_root" | sort > "$evidence/model-cache-tree.txt" 2>&1 || true
if [ -d "$model_directory" ]; then
  printf '%s\n' "$model_directory" > "$evidence/model-cache-directory.txt"
  {
    ls -ld "$model_root/Models" "$model_directory"
    readlink "$model_root/Models" || true
    df -h "$model_root/Models"
    mount | grep -F '/Volumes/cache' || true
  } > "$evidence/model-cache-mount.txt" 2>&1
  du -sh "$model_directory" > "$evidence/model-cache-size.txt" 2>&1 || true
  while IFS= read -r model_file; do
    stat -f '%z %N' "$model_file"
  done < <(fd -a -t f . "$model_directory" | sort) \
    > "$evidence/model-cache-files.txt" 2>&1 || true
fi

mark_phase open-target-apps
mkdir -p "$HOME/Library/Application Support/Google/Chrome"
touch "$HOME/Library/Application Support/Google/Chrome/First Run"
if [ "$mode" = "full" ]; then
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
test -x "$lsregister_bin"
if [ "$mode" = "full" ]; then
  "$lsregister_bin" -f \
    "/Applications/Google Chrome.app" \
    "/Applications/Visual Studio Code.app" \
    > "$evidence/app-registration.log" 2>&1
else
  "$lsregister_bin" -f "/Applications/Google Chrome.app" \
    > "$evidence/app-registration.log" 2>&1
fi
launch_detached "$evidence/textedit-launch.log" -b com.apple.TextEdit
launch_detached "$evidence/chrome-launch.log" \
  -na "/Applications/Google Chrome.app" --args \
  --force-renderer-accessibility --no-first-run --no-default-browser-check about:blank
if [ "$mode" = "full" ]; then
  launch_detached "$evidence/safari-launch.log" -b com.apple.Safari
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
