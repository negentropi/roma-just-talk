#!/usr/bin/env bash
set -euo pipefail

site_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$site_root"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Real-audio demo E2E requires macOS." >&2
  exit 2
fi

for command_name in SwitchAudioSource afplay node; do
  if ! command -v "$command_name" >/dev/null; then
    echo "Missing required command: $command_name" >&2
    exit 2
  fi
done
if [ ! -x "node_modules/.bin/playwright" ]; then
  echo "Run npm install before the real-audio E2E." >&2
  exit 2
fi

fixture="${ROMA_DEMO_AUDIO_FIXTURE:-}"
expected="${ROMA_DEMO_EXPECTED_TRANSCRIPT:-}"
audio_device="${ROMA_DEMO_AUDIO_DEVICE:-BlackHole 2ch}"

if [ -z "$fixture" ] || [ ! -f "$fixture" ]; then
  echo "ROMA_DEMO_AUDIO_FIXTURE must name an existing WAV file." >&2
  exit 2
fi
if [ "${fixture##*.}" != "wav" ] && [ "${fixture##*.}" != "WAV" ]; then
  echo "ROMA_DEMO_AUDIO_FIXTURE must be a WAV file." >&2
  exit 2
fi
if [ -z "$expected" ]; then
  echo "ROMA_DEMO_EXPECTED_TRANSCRIPT is required." >&2
  exit 2
fi

current_uid() {
  SwitchAudioSource -c -f json -t "$1" \
    | node -e 'let value=""; process.stdin.on("data", chunk => { value += chunk; }); process.stdin.on("end", () => process.stdout.write(JSON.parse(value).uid));'
}

original_input_uid="$(current_uid input)"
original_output_uid="$(current_uid output)"
original_system_output_uid="$(current_uid system)"
[ -n "$original_input_uid" ]
[ -n "$original_output_uid" ]
[ -n "$original_system_output_uid" ]
audio_changed=false
loopback_level_captured=false
original_loopback_output_volume=""
original_loopback_output_muted=""

output_volume() {
  /usr/bin/osascript -e 'output volume of (get volume settings)'
}

output_muted() {
  /usr/bin/osascript -e 'output muted of (get volume settings)'
}

write_output_level() {
  local destination="$1"
  local volume="$2"
  local muted="$3"
  if [ -n "$destination" ]; then
    printf 'output_volume=%s\noutput_muted=%s\n' "$volume" "$muted" > "$destination"
  fi
}

restore_loopback_level() {
  local restore_exit=0
  local restored_volume=""
  local restored_muted=""
  local mute_clause="without output muted"
  if [ "$loopback_level_captured" != true ]; then
    return 0
  fi
  if [ "$original_loopback_output_muted" = true ]; then
    mute_clause="with output muted"
  fi
  /usr/bin/osascript -e \
    "set volume output volume $original_loopback_output_volume $mute_clause" \
    >/dev/null 2>&1 || restore_exit=1
  restored_volume="$(output_volume 2>/dev/null || true)"
  restored_muted="$(output_muted 2>/dev/null || true)"
  write_output_level \
    "${ROMA_DEMO_AUDIO_LEVEL_AFTER:-}" \
    "$restored_volume" \
    "$restored_muted" || restore_exit=1
  if [ "$restored_volume" != "$original_loopback_output_volume" ] \
    || [ "$restored_muted" != "$original_loopback_output_muted" ]; then
    restore_exit=1
  fi
  if [ "$restore_exit" -ne 0 ]; then
    echo "Could not verify the original BlackHole output level was restored." >&2
  fi
  return "$restore_exit"
}

restore_audio() {
  local restore_exit=0
  local restored_input_uid=""
  local restored_output_uid=""
  local restored_system_output_uid=""
  if [ "$audio_changed" = true ]; then
    restore_loopback_level || restore_exit=1
    SwitchAudioSource -u "$original_input_uid" -t input >/dev/null 2>&1 || restore_exit=1
    SwitchAudioSource -u "$original_output_uid" -t output >/dev/null 2>&1 || restore_exit=1
    SwitchAudioSource -u "$original_system_output_uid" -t system >/dev/null 2>&1 || restore_exit=1
    restored_input_uid="$(current_uid input 2>/dev/null || true)"
    restored_output_uid="$(current_uid output 2>/dev/null || true)"
    restored_system_output_uid="$(current_uid system 2>/dev/null || true)"
    if [ "$restored_input_uid" != "$original_input_uid" ] \
      || [ "$restored_output_uid" != "$original_output_uid" ] \
      || [ "$restored_system_output_uid" != "$original_system_output_uid" ]; then
      restore_exit=1
    fi
  fi
  if [ "$restore_exit" -ne 0 ]; then
    echo "Could not verify the original macOS audio route was restored." >&2
  fi
  return "$restore_exit"
}

finish() {
  local test_exit=$?
  trap - EXIT
  if ! restore_audio; then
    test_exit=4
  fi
  exit "$test_exit"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

audio_changed=true
SwitchAudioSource -s "$audio_device" -t input >/dev/null
SwitchAudioSource -s "$audio_device" -t output >/dev/null
SwitchAudioSource -s "$audio_device" -t system >/dev/null

actual_input="$(SwitchAudioSource -c -t input)"
actual_output="$(SwitchAudioSource -c -t output)"
actual_system_output="$(SwitchAudioSource -c -t system)"
if [ "$actual_input" != "$audio_device" ] \
  || [ "$actual_output" != "$audio_device" ] \
  || [ "$actual_system_output" != "$audio_device" ]; then
  echo "BlackHole did not become the default input, output, and system output." >&2
  exit 3
fi

original_loopback_output_volume="$(output_volume)"
original_loopback_output_muted="$(output_muted)"
if [[ ! "$original_loopback_output_volume" =~ ^[0-9]+$ ]] \
  || { [ "$original_loopback_output_muted" != true ] && [ "$original_loopback_output_muted" != false ]; }; then
  echo "BlackHole did not expose restorable output volume and mute controls." >&2
  exit 3
fi
write_output_level \
  "${ROMA_DEMO_AUDIO_LEVEL_BEFORE:-}" \
  "$original_loopback_output_volume" \
  "$original_loopback_output_muted"
loopback_level_captured=true

export ROMA_DEMO_AUDIO_FIXTURE="$fixture"
export ROMA_DEMO_EXPECTED_TRANSCRIPT="$expected"
export ROMA_DEMO_AUDIO_DEVICE="$audio_device"

node_modules/.bin/playwright test --config playwright.real-audio.config.mjs
