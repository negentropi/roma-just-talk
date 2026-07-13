#!/usr/bin/env bash
set -euo pipefail

target="${1:?target required}"
hold_minutes="${2:?hold minutes required}"
inputs_root="${3:?inputs root required}"
stage_root="${4:?stage root required}"

case "$target" in
  both|macos|ios) ;;
  *)
    echo "Unsupported target: $target" >&2
    exit 2
    ;;
esac

if ! [[ "$hold_minutes" =~ ^[0-9]+$ ]] || (( hold_minutes < 1 || hold_minutes > 60 )); then
  echo "Hold minutes must be between 1 and 60" >&2
  exit 2
fi

desktop="$HOME/Desktop"
evidence="$stage_root/evidence"
done_file="/tmp/voiceink-remote-e2e-stage-done"
ready_file="$stage_root/READY"
simulator_udid=""
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
  local preferences="$HOME/Library/Preferences/com.prakashjoshipax.VoiceInk.plist"
  local preferences_backup="$HOME/Library/Preferences/ccom.prakashjoshipax.VoiceInk.plist"

  test -f "$archive"
  mkdir -p "$HOME/Applications" "$stage_root/macos"
  ditto -x -k "$archive" "$stage_root/macos"
  test -d "$stage_root/macos/roma just talk.app"
  ditto "$stage_root/macos/roma just talk.app" "$app"
  xattr -cr "$app"

  if [ -f "$preferences" ] && [ ! -f "$preferences_backup" ]; then
    mv "$preferences" "$preferences_backup"
  fi
  defaults delete com.prakashjoshipax.VoiceInk hasCompletedOnboarding 2>/dev/null || true
  defaults delete com.prakashjoshipax.VoiceInk macOSOnboardingStage 2>/dev/null || true
  defaults delete com.prakashjoshipax.VoiceInk macOSOnboardingPermissionKind 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true

  /usr/bin/log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/macos-app.log" 2>&1 &
  log_pids+=("$!")

  open -na "$app"
  echo "$app" > "$stage_root/macos-app-path.txt"
}

prepare_ios() {
  local archive="$inputs_root/ios/roma.just.talk.ios-simulator.app.zip"
  local unpacked="$stage_root/ios"
  local app="$unpacked/roma just talk.app"

  test -f "$archive"
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
  xcrun simctl launch "$simulator_udid" com.prakashjoshipax.VoiceInk

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

cat > "$desktop/REMOTE E2E STAGE READY.txt" <<EOF
roma just talk remote E2E stage

Target: $target
GitHub run: ${GITHUB_RUN_ID:-local}
Stage root: $stage_root

The desktop is ready for manual VNC or future Computer Use interaction.
No scripted scenario is running.

To finish early, double-click:
Finish Remote E2E Stage.command
EOF

cat > "$desktop/Finish Remote E2E Stage.command" <<EOF
#!/usr/bin/env bash
touch "$done_file"
EOF
chmod +x "$desktop/Finish Remote E2E Stage.command"
ln -sfn "$stage_root" "$desktop/Remote E2E Stage"

cat > "$stage_root/stage-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "status": "ready",
  "target": "$target",
  "githubRunId": "${GITHUB_RUN_ID:-local}",
  "doneFile": "$done_file",
  "evidenceDirectory": "$evidence",
  "macOSBundleIdentifier": "com.prakashjoshipax.VoiceInk",
  "iOSBundleIdentifier": "com.prakashjoshipax.VoiceInk",
  "simulatorUDID": "$simulator_udid"
}
EOF

touch "$ready_file"
capture_desktop ready
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-ready.png" 2>/dev/null || true
fi

echo "REMOTE E2E STAGE READY"
echo "Open Namespace dashboard -> this GitHub job -> Remote Display."
echo "Target: $target"
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
