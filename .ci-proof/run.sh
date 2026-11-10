#!/usr/bin/env bash
# Proves type-while-speaking against the real built app on a hosted macOS runner:
# say(1) speech -> BlackHole 2ch -> Roma mic, real left-Shift hold, Parakeet V2 streaming,
# TextEdit field sampled over Accessibility before, during, and after the hold.
# Red/green pair: typeWhileSpeaking=false must leave the field empty until key-up;
# typeWhileSpeaking=true must put text in the field while Shift is still held.
set -euo pipefail

app="$(cd "$1" && pwd -P)"
out="$(mkdir -p "$2" && cd "$2" && pwd -P)"
root="$(cd "$(dirname "$0")/.." && pwd -P)"
work="$(mktemp -d /tmp/rjt-live-typing.XXXXXX)"
bundle_id="com.negentropi.RomaJustTalk"
probe_id="com.negentropi.RomaLiveTypingProbe"
probe_app="$work/LiveTypingProbe.app"
manifest="$root/scripts/runtime-e2e-parakeet-v2.manifest"
model_directory="$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2"
system_tcc_db="/Library/Application Support/com.apple.TCC/TCC.db"
user_tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
log_started="$(date '+%Y-%m-%d %H:%M:%S')"

exec > >(tee -a "$out/run.log") 2>&1
phase() { printf '\n[%s] == %s\n' "$(date -u +%H:%M:%S)" "$*"; }

log_pid=""
cleanup() {
  [ -z "$log_pid" ] || kill "$log_pid" 2>/dev/null || true
  /usr/bin/log show --start "$log_started" --info --debug --style compact \
    --predicate "subsystem == \"$bundle_id\" && (category == \"LiveTranscriptTyper\" || category == \"TranscriptionPipeline\" || category == \"LatencyTrace\" || category == \"StreamingTranscriptionService\" || category == \"FluidAudioStreaming\" || category == \"StreamingTranscriptionSession\" || category == \"VoiceInkEngine\" || category == \"ModelPrewarm\")" \
    > "$out/app-live-typing.log" 2>&1 || true
  screencapture -x "$out/final-desktop.png" >/dev/null 2>&1 &
  killall TextEdit 2>/dev/null || true
  killall "Google Chrome" 2>/dev/null || true
}
trap cleanup EXIT

phase "host and inputs"
sw_vers | tee "$out/host.txt"
uname -m | tee -a "$out/host.txt"
git -C "$root" rev-parse HEAD | tee "$out/source-head.txt"
codesign -dv --verbose=2 "$app" > "$out/app-codesign.txt" 2>&1
shasum -a 256 "$app/Contents/MacOS/"* | tee "$out/app-executable-sha256.txt"
system_profiler SPAudioDataType > "$out/audio-devices.txt"
grep -q "BlackHole 2ch" "$out/audio-devices.txt"

phase "fetch pinned Parakeet V2 files (background)"
# Reuse the harness bootstrap with a curl shim in place of Namespace's artifact cache.
# shellcheck source=../scripts/runtime-e2e-model-bootstrap.sh
source "$root/scripts/runtime-e2e-model-bootstrap.sh"
revision="$(sed -n 's/^# FluidInference\/parakeet-tdt-0.6b-v2-coreml @ \([0-9a-f]*\)$/\1/p' "$manifest")"
test -n "$revision"
cat > "$work/fetch" <<'SH'
#!/usr/bin/env bash
# Called as: fetch artifact cache-url URL --out=PATH
exec curl -fsSL --retry 4 --retry-delay 3 -o "${4#--out=}" "$3"
SH
chmod +x "$work/fetch"
model_started=$SECONDS
runtime_prepare_pinned_model "$manifest" "$model_directory" \
  "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/$revision" \
  "$work/fetch" "$out/model-source.txt" > "$out/model-fetch.log" 2>&1 &
model_pid=$!

phase "speech fixture"
cat > "$out/fixture-long.txt" <<'TXT'
The weather was warm and bright this morning. My sister planted tomatoes and basil in the garden behind the house. Please send the quarterly report to the finance team before Friday afternoon. We will meet at the library tonight after dinner.
TXT
cat > "$out/fixture-short.txt" <<'TXT'
Please send the quarterly report to the finance team before Friday afternoon.
TXT
cat > "$out/fixture-user.txt" <<'TXT'
I think it's not dropped, it's just the logic of how you implement the stream text. I think it's like all aligned, all connected together, you know. It's like the way how you implement that. I don't know, probably it's too independent.
TXT
cat > "$out/fixture-revise.txt" <<'TXT'
Their going to the store, I mean they're going to the store at two, no, at four. Write the right letter to the principal, not the principle. I scream for ice cream, and we'll see if the weather is whether or not.
TXT
for fixture in long short user revise; do
  # Recorded once with say(1); the runner's synthesizer sometimes writes silence.
  cp "$root/.ci-proof/fixture-$fixture.wav" "$work/fixture-$fixture.wav"
  cp "$work/fixture-$fixture.wav" "$out/fixture-$fixture.wav"
  afinfo "$work/fixture-$fixture.wav" | tee "$out/fixture-$fixture-info.txt" | grep -i duration
done

phase "build probe from the runtime harness sources"
harness="$root/Tools/RuntimeE2EHarness"
mkdir -p "$work/build" "$probe_app/Contents/MacOS" "$probe_app/Contents/Frameworks"
swift_flags=(-swift-version 5 -target "$(uname -m)-apple-macosx14.0" -O -parse-as-library)
xcrun swiftc "${swift_flags[@]}" -emit-library -emit-module -module-name RuntimeE2ECore \
  "$harness/Sources/RuntimeE2ECore/RuntimeE2ECore.swift" \
  -emit-module-path "$work/build/RuntimeE2ECore.swiftmodule" \
  -o "$probe_app/Contents/Frameworks/libRuntimeE2ECore.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libRuntimeE2ECore.dylib
harness_sources=()
while IFS= read -r source_file; do harness_sources+=("$source_file"); done < <(
  find "$harness/Sources/RuntimeE2EHarness" -name '*.swift' ! -name main.swift | sort)
xcrun swiftc "${swift_flags[@]}" -module-name LiveTypingProbe -I "$work/build" \
  -L "$probe_app/Contents/Frameworks" -lRuntimeE2ECore \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "${harness_sources[@]}" "$root/.ci-proof/LiveTypingProbe.swift" \
  -o "$probe_app/Contents/MacOS/LiveTypingProbe"
cp "$harness/Info.plist" "$probe_app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$probe_id" "$probe_app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string LiveTypingProbe "$probe_app/Contents/Info.plist"
codesign --force --sign - "$probe_app/Contents/Frameworks/libRuntimeE2ECore.dylib"
codesign --force --sign - "$probe_app"
codesign --verify --deep --strict "$probe_app"

phase "grant TCC to Roma and the probe (disposable runner)"
grant() {
  local bundle="$1" client="$2" db="$3" service="$4" csreq="$work/$2.csreq"
  if [ ! -f "$csreq" ]; then
    codesign -dr - "$bundle" 2>&1 | sed -n -e 's/^# designated => //p' -e 's/^designated => //p' \
      | tee "$out/$client.requirement.txt" | csreq -r- -b "$csreq"
  fi
  local sql="INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('$service','$client',0,2,4,1,readfile('$csreq'),0,'UNUSED',0);"
  if [ "$db" = system ]; then sudo sqlite3 "$system_tcc_db" "$sql"; else sqlite3 "$user_tcc_db" "$sql"; fi
}
for service in kTCCServiceAccessibility kTCCServiceListenEvent kTCCServicePostEvent; do
  grant "$app" "$bundle_id" system "$service"
done
grant "$app" "$bundle_id" user kTCCServiceMicrophone
grant "$probe_app" "$probe_id" system kTCCServiceAccessibility
grant "$probe_app" "$probe_id" system kTCCServicePostEvent
killall tccd 2>/dev/null || true
sudo killall tccd 2>/dev/null || true
sleep 2
{
  sudo sqlite3 -header "$system_tcc_db" "select service,client,auth_value from access where client in ('$bundle_id','$probe_id');"
  sqlite3 -header "$user_tcc_db" "select service,client,auth_value from access where client in ('$bundle_id','$probe_id');"
} | tee "$out/tcc-rows.txt"

phase "app defaults"
defaults write "$bundle_id" hasCompletedOnboarding -bool true
defaults delete "$bundle_id" macOSOnboardingStage 2>/dev/null || true
defaults delete "$bundle_id" macOSOnboardingPermissionKind 2>/dev/null || true
defaults write "$bundle_id" CurrentTranscriptionModel -string parakeet-tdt-0.6b-v2
defaults write "$bundle_id" streaming-enabled-parakeet-tdt-0.6b-v2 -bool true
defaults write "$bundle_id" PrewarmModelOnWake -bool true
defaults write "$bundle_id" isAIEnhancementEnabled -bool false
defaults write "$bundle_id" isSoundFeedbackEnabled -bool false
defaults write "$bundle_id" enableAnnouncements -bool false
defaults write "$bundle_id" restoreClipboardAfterPaste -bool false
defaults write "$bundle_id" appendTrailingSpace -bool false
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
# Large plain-text font so the screen recording is readable.
defaults write com.apple.TextEdit NSFixedPitchFont -string Menlo-Regular
defaults write com.apple.TextEdit NSFixedPitchFontSize -int 30
python3 - "$harness/runtime-e2e.example.json" "$app" "$work" "$work/config.json" <<'PY'
import json, sys
example, app, work, output = sys.argv[1:]
config = json.load(open(example))
config.update({'voiceInkAppPath': app, 'voiceInkBuildDirectory': app.rsplit('/', 1)[0], 'audioDirectory': work,
               'preRollWarmupSeconds': 3, 'repetitions': 1, 'minimumTargetCount': 1,
               'targetAvailabilityPolicy': 'launchIfNeeded', 'targets': [t for t in config['targets'] if t['id'] == 'textedit']})
json.dump(config, open(output, 'w'), indent=2)
PY
cp "$work/config.json" "$out/probe-config.json"

phase "wait for model files"
if ! wait "$model_pid"; then
  cat "$out/model-fetch.log"
  echo "Pinned Parakeet V2 download or verification failed" >&2
  exit 1
fi
echo "model ready in $((SECONDS - model_started))s from $(cat "$out/model-source.txt")"
runtime_write_model_receipt "$manifest" "$model_directory" "$out/model-receipt.txt"

/usr/bin/log stream --level debug --style compact --predicate "subsystem == \"$bundle_id\"" > "$out/app-stream.log" 2>&1 &
log_pid=$!

# Each run: fixture:target:mode. Control (off) first so a red "on" run still has its pair in the same artifact.
runs="${RJT_PROOF_RUNS:-user:chrome:ime revise:chrome:ime user:textedit:ime}"
echo "$runs" > "$out/runs.txt"
for spec in $runs; do
  IFS=: read -r fixture target mode <<<"$spec"
  run="$fixture-$target-$mode"
  phase "probe fixture=$fixture target=$target typeWhileSpeaking=$mode"
  if [ "$mode" = on ]; then value=true; else value=false; fi
  defaults write "$bundle_id" typeWhileSpeaking -bool "$value"
  if [ "$mode" = ime ]; then
    defaults write "$bundle_id" prototypeIMEStream -bool true
    if [ ! -d "$HOME/Library/Input Methods/RomaStream.app" ]; then
      phase "PROTOTYPE: build, install and select the Roma Stream input method"
      ime_src="$root/Prototypes/IMEStreamText"
      ime_app="$HOME/Library/Input Methods/RomaStream.app"
      mkdir -p "$ime_app/Contents/MacOS" "$ime_app/Contents/Resources"
      cp "$ime_src/Info.plist" "$ime_app/Contents/Info.plist"
      sips -s format tiff -z 32 32 /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
        --out "$ime_app/Contents/Resources/icon.tiff" >/dev/null || true
      xcrun swiftc -swift-version 5 -O "$ime_src/RomaStreamInputMethod.swift" -o "$ime_app/Contents/MacOS/RomaStream"
      codesign --force --sign - "$ime_app"
      xcrun swiftc -swift-version 5 "$ime_src/SelectInputSource.swift" -o "$work/SelectInputSource"
      # Stand-in for the user's one-time "add input source" in System Settings, which writes this entry;
      # macOS no longer lets an app enable a third-party input method itself (TISEnableInputSource is a no-op).
      entry='<dict><key>Bundle ID</key><string>com.negentropi.inputmethod.RomaStream</string><key>InputSourceKind</key><string>Keyboard Input Method</string></dict>'
      defaults write com.apple.inputsources AppleEnabledThirdPartyInputSources -array-add "$entry"
      defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add "$entry"
      killall TextInputMenuAgent TextInputSwitcher 2>/dev/null || true
      sleep 2
      "$work/SelectInputSource" "$ime_app" com.negentropi.inputmethod.RomaStream 2>&1 | tee "$out/ime-select.txt" \
        || echo "input method selection did not stick" | tee -a "$out/ime-select.txt"
      defaults read com.apple.HIToolbox AppleSelectedInputSources >> "$out/ime-select.txt" 2>&1 || true
    fi
  else
    defaults write "$bundle_id" prototypeIMEStream -bool false
  fi
  # PROTOTYPE variants that leave the field alone until release: recorder preview, caret bubble, ghost text.
  defaults write "$bundle_id" showLiveTextPreview -bool "$([ "$mode" = preview ] && echo true || echo false)"
  defaults write "$bundle_id" RecorderType -string "$([ "$mode" = preview ] && echo mini || echo none)"
  case "$mode" in bubble|ghost) defaults write "$bundle_id" prototypeOverlayStream -string "$mode" ;;
    *) defaults delete "$bundle_id" prototypeOverlayStream 2>/dev/null || true ;; esac
  rm -f "$out/probe-$run.json"
  # Screen recording of this run; recording-start uptime (same clock as the probe's *Uptime fields) lets the fixture audio be lined up later.
  screencapture -v -x -V 240 "$out/screen-$run.mov" >/dev/null 2>&1 &
  rec_pid=$!
  python3 -c 'import time; print(time.clock_gettime(time.CLOCK_UPTIME_RAW))' > "$out/screen-$run.start-uptime.txt"
  /usr/bin/open -W -n -o "$out/probe-$run.stdout.log" --stderr "$out/probe-$run.stderr.log" "$probe_app" --args \
    --config "$work/config.json" --fixture "$work/fixture-$fixture.wav" --mode "$mode" --target "$target" \
    --output "$out/probe-$run.json" --targets "$work/targets" --cases "${RJT_PROOF_CASES:-2}"
  kill -INT "$rec_pid" 2>/dev/null || true
  wait "$rec_pid" 2>/dev/null || true
  cat "$out/probe-$run.stdout.log" "$out/probe-$run.stderr.log" || true
  test -s "$out/probe-$run.json" || { echo "Probe wrote no report for $run" >&2; exit 1; }
done

cp "$HOME/roma-stream-ime.log" "$out/" 2>/dev/null || true
phase "verdict"
python3 "$root/.ci-proof/verdict.py" "$out"
