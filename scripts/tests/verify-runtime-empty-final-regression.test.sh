#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/verify-runtime-empty-final-regression.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-empty-final-regression.XXXXXX")"
OUTPUT="$TEMP_ROOT/output.txt"
trap 'rm -rf "$TEMP_ROOT"' EXIT

expect_failure() {
  local expected_message="$1"
  shift

  if "$@" >"$OUTPUT" 2>&1; then
    echo "expected command to fail: $*" >&2
    exit 1
  fi
  if ! grep -Fq "$expected_message" "$OUTPUT"; then
    echo "failure did not contain: $expected_message" >&2
    cat "$OUTPUT" >&2
    exit 1
  fi
}

cat > "$TEMP_ROOT/known-bad.json" <<'JSON'
{
  "summary": {"passed": false},
  "fatalError": null,
  "restoredOriginalState": true,
  "cases": [
    {
      "id": "known-bad-empty-final",
      "assessment": {"status": "emptyTranscript", "passed": false},
      "latencyTrace": {
        "events": [
          {"name": "streaming_event.first_partial", "details": "chars=18"},
          {"name": "fluid_streaming.final_asr.end", "details": "durationMs=146.8 chars=0"},
          {"name": "streaming_event.first_commit", "details": "chars=0"}
        ]
      }
    }
  ]
}
JSON

cat > "$TEMP_ROOT/fixed-fallback.json" <<'JSON'
{
  "summary": {"passed": true},
  "fatalError": null,
  "restoredOriginalState": true,
  "cases": [
    {
      "id": "fixed-live-hypothesis-fallback",
      "assessment": {"status": "passed", "passed": true},
      "visibleText": {"text": "this seems to be a good idea"},
      "latencyTrace": {
        "events": [
          {"name": "streaming_event.first_partial", "details": "chars=18"},
          {"name": "fluid_streaming.final_asr.end", "details": "durationMs=146.8 chars=0"},
          {"name": "fluid_streaming.commit.fallback_to_hypothesis", "details": "pendingSamples=15810 chars=18"},
          {"name": "streaming_event.first_commit", "details": "chars=18"}
        ]
      }
    }
  ]
}
JSON

cat > "$TEMP_ROOT/ordinary-pass.json" <<'JSON'
{
  "summary": {"passed": true},
  "fatalError": null,
  "restoredOriginalState": true,
  "cases": [
    {
      "id": "ordinary-nonempty-final",
      "assessment": {"status": "passed", "passed": true},
      "visibleText": {"text": "this seems to be a good idea"},
      "latencyTrace": {
        "events": [
          {"name": "streaming_event.first_partial", "details": "chars=10"},
          {"name": "fluid_streaming.final_asr.end", "details": "durationMs=146.5 chars=29"},
          {"name": "streaming_event.first_commit", "details": "chars=29"}
        ]
      }
    }
  ]
}
JSON

cat > "$TEMP_ROOT/generic-empty.json" <<'JSON'
{
  "summary": {"passed": false},
  "fatalError": null,
  "restoredOriginalState": true,
  "cases": [
    {
      "id": "empty-without-live-recognition",
      "assessment": {"status": "emptyTranscript", "passed": false},
      "latencyTrace": {
        "events": [
          {"name": "fluid_streaming.final_asr.end", "details": "durationMs=100 chars=0"},
          {"name": "streaming_event.first_commit", "details": "chars=0"}
        ]
      }
    }
  ]
}
JSON

cat > "$TEMP_ROOT/mixed-failure.json" <<'JSON'
{
  "summary": {"passed": false},
  "fatalError": null,
  "restoredOriginalState": true,
  "cases": [
    {
      "id": "known-bad-empty-final",
      "assessment": {"status": "emptyTranscript", "passed": false},
      "latencyTrace": {
        "events": [
          {"name": "streaming_event.first_partial", "details": "chars=18"},
          {"name": "fluid_streaming.final_asr.end", "details": "chars=0"},
          {"name": "streaming_event.first_commit", "details": "chars=0"}
        ]
      }
    },
    {
      "id": "unrelated-target-failure",
      "assessment": {"status": "targetUnavailable", "passed": false},
      "latencyTrace": {"events": []}
    }
  ]
}
JSON

jq '.fatalError = "cleanup crashed"' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-fatal.json"
jq '.restoredOriginalState = false' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-unrestored.json"

bash "$VERIFIER" known-bad "$TEMP_ROOT/known-bad.json"
bash "$VERIFIER" fixed "$TEMP_ROOT/fixed-fallback.json"

expect_failure \
  "no case proved the fixed empty-final fallback" \
  bash "$VERIFIER" fixed "$TEMP_ROOT/ordinary-pass.json"
expect_failure \
  "no case reproduced the live-partial to empty-final bug" \
  bash "$VERIFIER" known-bad "$TEMP_ROOT/generic-empty.json"
expect_failure \
  "known-bad report contains a different failed case" \
  bash "$VERIFIER" known-bad "$TEMP_ROOT/mixed-failure.json"
expect_failure \
  "runtime E2E report contains a fatal error" \
  bash "$VERIFIER" known-bad "$TEMP_ROOT/known-bad-fatal.json"
expect_failure \
  "runtime E2E report did not restore original state" \
  bash "$VERIFIER" known-bad "$TEMP_ROOT/known-bad-unrestored.json"
expect_failure \
  "usage:" \
  bash "$VERIFIER" unsupported "$TEMP_ROOT/known-bad.json"

echo "runtime empty-final regression evidence checks passed"
