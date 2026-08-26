#!/usr/bin/env bash
set -euo pipefail

target="${1:?target required}"
hold_minutes="${2:?hold minutes required}"
inputs_root="${3:?inputs root required}"
stage_root="${4:?stage root required}"
ios_scenario="${5:-none}"
macos_scenario="${6:-none}"
macos_audio_artifact="${7:-}"
macos_repetitions="${8:-3}"

case "$target" in
  both|macos|ios) ;;
  *)
    echo "Unsupported target: $target" >&2
    exit 2
    ;;
esac

if ! [[ "$hold_minutes" =~ ^[0-9]+$ ]] || (( hold_minutes < 0 || hold_minutes > 60 )); then
  echo "Hold minutes must be between 0 and 60" >&2
  exit 2
fi

case "$ios_scenario" in
  none|local-whisper-import) ;;
  *)
    echo "Unsupported iOS scenario: $ios_scenario" >&2
    exit 2
    ;;
esac

case "$macos_scenario" in
  none|runtime-smoke|runtime-e2e) ;;
  *)
    echo "Unsupported macOS scenario: $macos_scenario" >&2
    exit 2
    ;;
esac

if [ "$target" = "ios" ] && [ "$macos_scenario" != "none" ]; then
  echo "A macOS scenario requires the macos or both target" >&2
  exit 2
fi

if [ "$macos_scenario" != "none" ] && [ -z "$macos_audio_artifact" ]; then
  echo "$macos_scenario requires a private Namespace audio artifact" >&2
  exit 2
fi

case "$macos_repetitions" in
  1|3|5) ;;
  *)
    echo "macOS repetitions must be 1, 3, or 5" >&2
    exit 2
    ;;
esac

if [ "$target" = "macos" ] && [ "$ios_scenario" != "none" ]; then
  echo "An iOS scenario requires the ios or both target" >&2
  exit 2
fi

desktop="$HOME/Desktop"
evidence="$stage_root/evidence"
done_file="/tmp/voiceink-remote-e2e-stage-done"
ready_file="$stage_root/READY"
simulator_udid=""
macos_artifact_run_id=""
ios_artifact_run_id=""
macos_scenario_status=0
ios_scenario_status=0
log_pids=()

mkdir -p "$desktop" "$evidence"
rm -f "$done_file"

stop_logs() {
  for pid in "${log_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap stop_logs EXIT

capture_desktop() {
  local phase="$1"
  local image="$evidence/desktop-$phase.png"
  local error_log="$evidence/desktop-$phase-screencapture.err"

  if ! /usr/sbin/screencapture -x "$image" 2> "$error_log"; then
    echo "Namespace VNC is available, but screencapture cannot see its display from the runner shell." \
      > "$evidence/desktop-$phase-controller-capture-required.txt"
  fi
}

prepare_macos() {
  local archive="$inputs_root/macos/roma.just.talk.app.zip"
  local app="$HOME/Applications/roma just talk.app"
  local preferences="$HOME/Library/Preferences/com.negentropi.RomaJustTalk.plist"
  local preferences_backup="$HOME/Library/Preferences/ccom.negentropi.RomaJustTalk.plist"

  test -f "$archive"
  read -r macos_artifact_run_id < "$inputs_root/macos/build-run-id.txt"
  mkdir -p "$HOME/Applications" "$stage_root/macos"
  ditto -x -k "$archive" "$stage_root/macos"
  test -d "$stage_root/macos/roma just talk.app"
  ditto "$stage_root/macos/roma just talk.app" "$app"
  xattr -cr "$app"

  if [ -f "$preferences" ] && [ ! -f "$preferences_backup" ]; then
    mv "$preferences" "$preferences_backup"
  fi
  defaults delete com.negentropi.RomaJustTalk hasCompletedOnboarding 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk macOSOnboardingStage 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk macOSOnboardingPermissionKind 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true

  /usr/bin/log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/macos-app.log" 2>&1 &
  log_pids+=("$!")

  if [ "$macos_scenario" = "none" ]; then
    open -na "$app"
  fi
  echo "$app" > "$stage_root/macos-app-path.txt"
}

prepare_ios() {
  local archive="$inputs_root/ios/roma.just.talk.ios-simulator.app.zip"
  local unpacked="$stage_root/ios"
  local app="$unpacked/roma just talk.app"

  test -f "$archive"
  read -r ios_artifact_run_id < "$inputs_root/ios/build-run-id.txt"
  mkdir -p "$unpacked"
  ditto -x -k "$archive" "$unpacked"
  test -d "$app"

  simulator_udid="$(
    xcrun simctl list devices available --json \
      | jq -r '[.devices[][] | select(.name | startswith("iPhone"))][0].udid'
  )"
  test -n "$simulator_udid"
  test "$simulator_udid" != "null"

  xcrun simctl shutdown "$simulator_udid" 2>/dev/null || true
  xcrun simctl erase "$simulator_udid"
  xcrun simctl boot "$simulator_udid"
  xcrun simctl bootstatus "$simulator_udid" -b
  xcrun simctl install "$simulator_udid" "$app"
  open -a Simulator
  xcrun simctl launch "$simulator_udid" com.negentropi.RomaJustTalk

  xcrun simctl spawn "$simulator_udid" log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/ios-app.log" 2>&1 &
  log_pids+=("$!")

  echo "$simulator_udid" > "$stage_root/ios-simulator-udid.txt"
}

case "$target" in
  both)
    prepare_macos
    prepare_ios
    ;;
  macos)
    prepare_macos
    ;;
  ios)
    prepare_ios
    ;;
esac

write_manifest() {
  local status="$1"

  cat > "$stage_root/stage-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "status": "$status",
  "target": "$target",
  "macOSScenario": "$macos_scenario",
  "macOSScenarioExitCode": $macos_scenario_status,
  "macOSAudioArtifact": "$macos_audio_artifact",
  "macOSRepetitions": $macos_repetitions,
  "iOSScenario": "$ios_scenario",
  "iOSScenarioExitCode": $ios_scenario_status,
  "githubRunId": "${GITHUB_RUN_ID:-local}",
  "githubSha": "${GITHUB_SHA:-local}",
  "githubRef": "${GITHUB_REF:-local}",
  "macOSArtifactRunId": "$macos_artifact_run_id",
  "iOSArtifactRunId": "$ios_artifact_run_id",
  "doneFile": "$done_file",
  "evidenceDirectory": "$evidence",
  "macOSBundleIdentifier": "com.negentropi.RomaJustTalk",
  "iOSBundleIdentifier": "com.negentropi.RomaJustTalk",
  "simulatorUDID": "$simulator_udid"
}
EOF
  cp "$stage_root/stage-manifest.json" "$evidence/stage-manifest.json"
}

write_manifest scenario-running

if [ "$macos_scenario" != "none" ]; then
  macos_runtime_mode="full"
  if [ "$macos_scenario" = "runtime-smoke" ]; then
    macos_runtime_mode="smoke"
  fi
  set +e
  bash "$(dirname "$0")/run-macos-runtime-e2e.sh" \
    "$HOME/Applications/roma just talk.app" \
    "$macos_audio_artifact" \
    "$evidence" \
    "$macos_repetitions" \
    "$macos_runtime_mode"
  macos_scenario_status=$?
  set -e
fi

if [ "$ios_scenario" = "local-whisper-import" ]; then
  set +e
  bash "$(dirname "$0")/run-ios-remote-stt-e2e.sh" \
    "$simulator_udid" \
    "$evidence"
  ios_scenario_status=$?
  set -e
fi

if [ "$macos_scenario_status" -ne 0 ] || [ "$ios_scenario_status" -ne 0 ]; then
  scenario_summary="A scripted scenario failed. Inspect the uploaded evidence before assigning ownership."
elif [ "$macos_scenario" = "none" ] && [ "$ios_scenario" = "none" ]; then
  scenario_summary="No scripted scenario ran."
else
  scenario_summary="The requested scripted scenario completed successfully."
fi

cat > "$desktop/REMOTE E2E STAGE READY.txt" <<EOF
roma just talk remote E2E stage

Target: $target
macOS scenario: $macos_scenario
iOS scenario: $ios_scenario
GitHub run: ${GITHUB_RUN_ID:-local}
Stage root: $stage_root

$scenario_summary
The desktop is ready for manual VNC or Computer Use interaction during the remaining hold.

To finish early, double-click:
Finish Remote E2E Stage.command
EOF

cat > "$desktop/Finish Remote E2E Stage.command" <<EOF
#!/usr/bin/env bash
touch "$done_file"
EOF
chmod +x "$desktop/Finish Remote E2E Stage.command"
ln -sfn "$stage_root" "$desktop/Remote E2E Stage"

if [ "$macos_scenario_status" -eq 0 ] && [ "$ios_scenario_status" -eq 0 ]; then
  write_manifest ready
else
  write_manifest scenario-failed
fi

touch "$ready_file"
capture_desktop ready
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-ready.png" 2>/dev/null || true
fi

echo "REMOTE E2E STAGE READY"
echo "Open Namespace dashboard -> this GitHub job -> Remote Display."
echo "Target: $target"
echo "macOS scenario: $macos_scenario (exit $macos_scenario_status)"
echo "iOS scenario: $ios_scenario (exit $ios_scenario_status)"
echo "Hold: $hold_minutes minutes"
echo "Finish early: double-click Finish Remote E2E Stage.command on the remote desktop."

deadline=$((SECONDS + hold_minutes * 60))
while (( SECONDS < deadline )) && [ ! -f "$done_file" ]; do
  remaining=$(((deadline - SECONDS + 59) / 60))
  echo "Stage alive; about $remaining minute(s) remaining."
  sleep 30
done

capture_desktop final
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-final.png" 2>/dev/null || true
fi
xcodebuild -version > "$evidence/xcode-version.txt"
sw_vers > "$evidence/macos-version.txt"
xcrun simctl list devices > "$evidence/simulator-devices.txt"

if [ -f "$done_file" ]; then
  echo "Remote E2E stage finished early."
else
  echo "Remote E2E stage hold expired."
fi

if [ "$macos_scenario_status" -eq 0 ] && [ "$ios_scenario_status" -eq 0 ]; then
  write_manifest completed
else
  write_manifest scenario-failed
fi

if [ "$macos_scenario_status" -ne 0 ]; then
  exit "$macos_scenario_status"
fi
if [ "$ios_scenario_status" -ne 0 ]; then
  exit "$ios_scenario_status"
fi
