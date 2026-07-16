#!/usr/bin/env bash
set -Eeuo pipefail

simulator_udid="${1:?simulator UDID required}"
evidence="${2:?evidence directory required}"

bundle_identifier="${VOICEINK_IOS_BUNDLE_IDENTIFIER:-com.prakashjoshipax.VoiceInk}"
expected_phrase="${VOICEINK_IOS_E2E_PHRASE:-The quick brown fox confirms this iPhone speech to text test for Roma just talk.}"
model_url="${VOICEINK_IOS_E2E_MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin}"
model_sha256="${VOICEINK_IOS_E2E_MODEL_SHA256:-60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe}"
timeout_seconds="${VOICEINK_IOS_E2E_TIMEOUT_SECONDS:-120}"
temporary_root="${RUNNER_TEMP:-/tmp}/voiceink-ios-stt-e2e"
model_cache="${VOICEINK_IOS_E2E_MODEL_PATH:-$temporary_root/ggml-base.bin}"
model_download="$model_cache.download.$$"
fixture_aiff="$temporary_root/roma-stt.aiff"
fixture_wav="$temporary_root/roma-stt.wav"

mkdir -p "$evidence" "$temporary_root" "$(dirname "$model_cache")"

describe_ui() {
  axe describe-ui --udid "$simulator_udid"
}

failure_line=unknown

remember_failure_line() {
  failure_line="$1"
}

capture_failure_evidence() {
  local exit_status="$1"

  if (( exit_status == 0 )); then
    return
  fi

  trap - ERR EXIT
  set +e
  rm -f "$model_download"
  if command -v axe >/dev/null 2>&1; then
    describe_ui \
      > "$evidence/stt-failure-final.json" \
      2> "$evidence/stt-failure-final.json.err"
    axe screenshot \
      --output "$evidence/stt-failure-final.png" \
      --udid "$simulator_udid" \
      2> "$evidence/stt-failure-final.png.err"
  else
    echo "AXe was unavailable when failure evidence was captured." \
      > "$evidence/stt-failure-axe-unavailable.txt"
  fi
  cat > "$evidence/stt-e2e-result.txt" <<EOF
result=failed
exit_status=$exit_status
failure_line=$failure_line
bundle_identifier=$bundle_identifier
simulator_udid=$simulator_udid
expected_phrase=$expected_phrase
EOF
  exit "$exit_status"
}

trap 'remember_failure_line "$LINENO"' ERR
trap 'capture_failure_evidence "$?"' EXIT

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds < 1 )); then
  echo "VOICEINK_IOS_E2E_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

for command_name in afconvert afinfo curl jq od say shasum stat xcrun; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name is required" >&2
    exit 1
  }
done

if ! command -v axe >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || {
    echo "axe or Homebrew is required" >&2
    exit 1
  }
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install cameroncooke/axe/axe
fi

axe --version > "$evidence/axe-version.txt"

wait_for_label() {
  local label="$1"
  local output="$2"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if describe_ui > "$output" 2> "$output.err"; then
      if jq -e --arg label "$label" \
        '.. | objects | select(.AXLabel? == $label)' \
        "$output" >/dev/null; then
        return 0
      fi
      if jq -e \
        '.. | objects | .AXLabel? | strings | select(test("Failed to process audio file|Transcription failed"))' \
        "$output" >/dev/null; then
        echo "The app reported a transcription failure while waiting for: $label" >&2
        return 1
      fi
    fi
    sleep 1
  done

  echo "Timed out waiting for accessibility label: $label" >&2
  return 1
}

normalized_expected_phrase="$(
  printf '%s' "$expected_phrase" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' ' ' \
    | sed -E 's/^ +//; s/ +$//'
)"

contains_expected_transcript() {
  local input="$1"

  jq -e --arg expected "$normalized_expected_phrase" \
    '.. | objects | .AXLabel? | strings
      | select((ascii_downcase | gsub("[^a-z0-9]+"; " ")) | contains($expected))' \
    "$input" >/dev/null
}

wait_for_completed_transcript() {
  local output="$1"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if describe_ui > "$output" 2> "$output.err"; then
      if jq -e \
        '.. | objects | select(.AXLabel? == "Completed")' \
        "$output" >/dev/null \
        && contains_expected_transcript "$output"; then
        return 0
      fi
      if jq -e \
        '.. | objects | .AXLabel? | strings | select(test("Failed to process audio file|Transcription failed"))' \
        "$output" >/dev/null; then
        echo "The app reported a transcription failure" >&2
        return 1
      fi
    fi
    sleep 1
  done

  echo "Timed out waiting for the completed expected transcript" >&2
  return 1
}

if [ ! -f "$model_cache" ]; then
  if ! curl -L --fail --retry 3 -o "$model_download" "$model_url"; then
    rm -f "$model_download"
    exit 1
  fi

  downloaded_model_sha256="$(shasum -a 256 "$model_download" | awk '{print $1}')"
  if [ "$downloaded_model_sha256" != "$model_sha256" ]; then
    echo "Unexpected downloaded ggml-base.bin SHA-256: $downloaded_model_sha256" >&2
    rm -f "$model_download"
    exit 1
  fi
  mv "$model_download" "$model_cache"
fi

actual_model_sha256="$(shasum -a 256 "$model_cache" | awk '{print $1}')"
if [ "$actual_model_sha256" != "$model_sha256" ]; then
  echo "Unexpected ggml-base.bin SHA-256: $actual_model_sha256" >&2
  exit 1
fi

say -v Samantha -r 135 -o "$fixture_aiff" "$expected_phrase"
afconvert "$fixture_aiff" "$fixture_wav" -f WAVE -d LEI16@16000 -c 1
afinfo "$fixture_wav" > "$evidence/stt-fixture-afinfo.txt"

app_data_container="$(
  xcrun simctl get_app_container \
    "$simulator_udid" \
    "$bundle_identifier" \
    data
)"
documents="$app_data_container/Documents"
models="$documents/WhisperModels"
fixture_in_container="$documents/roma-stt.wav"

mkdir -p "$models"
cp "$model_cache" "$models/ggml-base.bin"
cp "$fixture_wav" "$fixture_in_container"

xcrun simctl launch \
  --terminate-running-process \
  "$simulator_udid" \
  "$bundle_identifier" \
  -hasCompletedOnboarding YES \
  -enableAnnouncements NO \
  > "$evidence/stt-app-launch.txt"

xcrun simctl openurl "$simulator_udid" "file://$fixture_in_container"
wait_for_label "Start" "$evidence/stt-import-ready.json"
axe screenshot \
  --output "$evidence/stt-import-ready.png" \
  --udid "$simulator_udid"

axe tap --label "Start" --udid "$simulator_udid"
wait_for_completed_transcript "$evidence/stt-completed.json"
axe screenshot \
  --output "$evidence/stt-completed.png" \
  --udid "$simulator_udid"

axe tap --label "View transcript" --udid "$simulator_udid"
wait_for_label "Retranscribe" "$evidence/stt-detail.json"
jq -e \
  '.. | objects | select(.AXLabel? == "Transcript")' \
  "$evidence/stt-detail.json" >/dev/null
contains_expected_transcript "$evidence/stt-detail.json"
axe screenshot \
  --output "$evidence/stt-detail.png" \
  --udid "$simulator_udid"

shopt -s nullglob
stored_recordings=("$documents"/recordings/transcribed_*.wav)
if (( ${#stored_recordings[@]} != 1 )); then
  echo "Expected one prepared recording, found ${#stored_recordings[@]}" >&2
  exit 1
fi
stored_recording="${stored_recordings[0]}"
stored_file_bytes="$(stat -f %z "$stored_recording")"
if (( stored_file_bytes < 44 )); then
  echo "Prepared WAV is smaller than its canonical header: $stored_file_bytes" >&2
  exit 1
fi

assert_wav_tag() {
  local offset="$1"
  local expected="$2"
  local actual

  actual="$(dd if="$stored_recording" bs=1 skip="$offset" count=4 2>/dev/null)"
  if [ "$actual" != "$expected" ]; then
    echo "Prepared WAV tag at byte $offset is '$actual', expected '$expected'" >&2
    exit 1
  fi
}

assert_wav_tag 0 RIFF
assert_wav_tag 8 WAVE
assert_wav_tag 12 "fmt "
assert_wav_tag 36 data
riff_declared_size="$(od -An -tu4 -j4 -N4 "$stored_recording" | tr -d ' ')"
fmt_declared_size="$(od -An -tu4 -j16 -N4 "$stored_recording" | tr -d ' ')"
declared_audio_bytes="$(od -An -tu4 -j40 -N4 "$stored_recording" | tr -d ' ')"
if (( riff_declared_size != stored_file_bytes - 8 )); then
  echo "Prepared WAV RIFF size is invalid: $riff_declared_size != $((stored_file_bytes - 8))" >&2
  exit 1
fi
if (( fmt_declared_size != 16 )); then
  echo "Prepared WAV fmt chunk is not canonical PCM: $fmt_declared_size" >&2
  exit 1
fi
if (( declared_audio_bytes <= 0 )); then
  echo "Prepared WAV contains no declared audio payload" >&2
  exit 1
fi
expected_file_bytes=$((44 + declared_audio_bytes))
if (( stored_file_bytes != expected_file_bytes )); then
  echo "Prepared WAV is truncated: $stored_file_bytes != $expected_file_bytes" >&2
  exit 1
fi

fixture_sha256="$(shasum -a 256 "$fixture_wav" | awk '{print $1}')"
actual_transcript="$(
  jq -r --arg expected "$normalized_expected_phrase" \
    '[.. | objects | .AXLabel? | strings
      | select((ascii_downcase | gsub("[^a-z0-9]+"; " ")) | contains($expected))]
      | sort_by(length) | first' \
    "$evidence/stt-detail.json"
)"
cat > "$evidence/stt-e2e-result.txt" <<EOF
result=passed
bundle_identifier=$bundle_identifier
simulator_udid=$simulator_udid
expected_phrase=$expected_phrase
actual_transcript=$actual_transcript
fixture_sha256=$fixture_sha256
model_sha256=$actual_model_sha256
stored_file_bytes=$stored_file_bytes
riff_declared_size=$riff_declared_size
fmt_declared_size=$fmt_declared_size
declared_audio_bytes=$declared_audio_bytes
expected_file_bytes=$expected_file_bytes
EOF

echo "iOS local STT E2E passed: $expected_phrase"
