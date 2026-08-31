#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/macos-distribution-runtime-handoff.sh"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-runtime-handoff.XXXXXX")"
MODEL_DIRECTORY="$TEMP_ROOT/Models/parakeet-tdt-0.6b-v2"
trap 'rm -rf "$TEMP_ROOT"' EXIT
mkdir -p "$MODEL_DIRECTORY"

expect_failure() {
  local expected_message="$1"
  shift
  local output=""

  if output="$("$@" 2>&1)"; then
    echo "expected command to fail: $*" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    echo "failure did not contain: $expected_message" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

distribution_runtime_validate_handoff \
  4812 \
  4812 \
  "$MODEL_DIRECTORY" \
  ""

expect_failure \
  "missing the verified first-launch PID" \
  distribution_runtime_validate_handoff \
  "" 4812 "$MODEL_DIRECTORY" ""
expect_failure \
  "requires only the verified first-launch PID" \
  distribution_runtime_validate_handoff \
  4812 9911 "$MODEL_DIRECTORY" ""
expect_failure \
  "requires only the verified first-launch PID" \
  distribution_runtime_validate_handoff \
  4812 $'4812\n9911' "$MODEL_DIRECTORY" ""
expect_failure \
  "must not use an external model cache" \
  distribution_runtime_validate_handoff \
  4812 4812 "$MODEL_DIRECTORY" "$TEMP_ROOT/cache"

rmdir "$MODEL_DIRECTORY"
expect_failure \
  "did not create the live model directory" \
  distribution_runtime_validate_handoff \
  4812 4812 "$MODEL_DIRECTORY" ""

ln -s "$TEMP_ROOT/cache" "$MODEL_DIRECTORY"
mkdir -p "$TEMP_ROOT/cache"
expect_failure \
  "did not create the live model directory" \
  distribution_runtime_validate_handoff \
  4812 4812 "$MODEL_DIRECTORY" ""

rm "$MODEL_DIRECTORY"
rmdir "$TEMP_ROOT/cache" "$TEMP_ROOT/Models"
mkdir -p "$TEMP_ROOT/cache/parakeet-tdt-0.6b-v2"
ln -s "$TEMP_ROOT/cache" "$TEMP_ROOT/Models"
expect_failure \
  "did not create the live model directory" \
  distribution_runtime_validate_handoff \
  4812 4812 "$MODEL_DIRECTORY" ""

echo "macOS distribution runtime handoff checks passed"
