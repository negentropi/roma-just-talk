#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/verify-runtime-empty-final-regression.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-empty-final-regression.XXXXXX")"
OUTPUT="$TEMP_ROOT/output.txt"
LAUNCH_EVENTS="$TEMP_ROOT/empty-final-launch-events.tsv"
TERMINATION_EVENTS="$TEMP_ROOT/empty-final-termination-events.tsv"
APP_PATH="/Applications/roma just talk.app"
APP_SHA="9999999999999999999999999999999999999999999999999999999999999999"
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
  "configuration": {
    "voiceInkAppPath": "/Applications/roma just talk.app",
    "voiceInkBundleIdentifier": "com.negentropi.RomaJustTalk",
    "repetitions": 5,
    "voiceInkLifecycle": "relaunchPerCase",
    "targets": [
      {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      {"id":"safari","displayName":"Safari","bundleIdentifier":"com.apple.Safari","kind":"browser"}
    ]
  },
  "summary": {"passed": false},
  "fatalError": null,
  "restoredOriginalState": true,
  "preflight": {
    "voiceInk": {"runningPaths": []},
    "targets": [
      {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","bundlePath":"/System/Applications/TextEdit.app","installed":true,"runningPaths":[],"version":"1"},
      {"id":"safari","displayName":"Safari","bundleIdentifier":"com.apple.Safari","bundlePath":"/System/Applications/Safari.app","installed":true,"runningPaths":[],"version":"1"}
    ]
  },
  "voiceInkSession": {"originallyRunningPaths": []},
  "cases": [
    {
      "id": "known-bad-empty-final",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 1,
      "assessment": {"status": "emptyTranscript", "passed": false},
      "latencyTrace": {
        "events": [
          {"name": "streaming_event.first_partial", "details": "chars=18"},
          {"name": "fluid_streaming.final_asr.end", "details": "durationMs=146.8 chars=0"},
          {"name": "streaming_event.first_commit", "details": "chars=0"}
        ]
      }
    },
    {
      "id": "known-bad-ordinary-pass-r2",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 2,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    },
    {
      "id": "known-bad-ordinary-pass-r3",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 3,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    },
    {
      "id": "known-bad-ordinary-pass-r4",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 4,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    },
    {
      "id": "known-bad-ordinary-pass-r5",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 5,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    }
  ]
}
JSON

cat > "$TEMP_ROOT/fixed-fallback.json" <<'JSON'
{
  "configuration": {
    "voiceInkAppPath": "/Applications/roma just talk.app",
    "voiceInkBundleIdentifier": "com.negentropi.RomaJustTalk",
    "repetitions": 5,
    "voiceInkLifecycle": "relaunchPerCase",
    "targets": [
      {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      {"id":"safari","displayName":"Safari","bundleIdentifier":"com.apple.Safari","kind":"browser"}
    ]
  },
  "summary": {"passed": true},
  "fatalError": null,
  "restoredOriginalState": true,
  "preflight": {
    "voiceInk": {"runningPaths": []},
    "targets": [
      {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","bundlePath":"/System/Applications/TextEdit.app","installed":true,"runningPaths":[],"version":"1"},
      {"id":"safari","displayName":"Safari","bundleIdentifier":"com.apple.Safari","bundlePath":"/System/Applications/Safari.app","installed":true,"runningPaths":[],"version":"1"}
    ]
  },
  "voiceInkSession": {"originallyRunningPaths": []},
  "cases": [
    {
      "id": "fixed-live-hypothesis-fallback",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 1,
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
    },
    {
      "id": "fixed-ordinary-pass-r2",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 2,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    },
    {
      "id": "fixed-ordinary-pass-r3",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 3,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    },
    {
      "id": "fixed-ordinary-pass-r4",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 4,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    },
    {
      "id": "fixed-ordinary-pass-r5",
      "target": {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      "textScenario": "empty",
      "repetition": 5,
      "assessment": {"status": "passed", "passed": true},
      "latencyTrace": {"events": []}
    }
  ]
}
JSON

complete_smoke_matrix() {
  local report="$1"
  local completed="$report.completed"
  jq '
    .cases += (
      [range(1; 6) as $repetition | {
        id: ("textedit-existing-r" + ($repetition | tostring)),
        target: {
          id: "textedit",
          displayName: "TextEdit",
          bundleIdentifier: "com.apple.TextEdit",
          kind: "document"
        },
        textScenario: "existingText",
        repetition: $repetition,
        assessment: {status: "passed", passed: true},
        latencyTrace: {events: []}
      }]
      + [range(1; 6) as $repetition | {
        id: ("safari-empty-r" + ($repetition | tostring)),
        target: {
          id: "safari",
          displayName: "Safari",
          bundleIdentifier: "com.apple.Safari",
          kind: "browser"
        },
        textScenario: "empty",
        repetition: $repetition,
        assessment: {status: "passed", passed: true},
        latencyTrace: {events: []}
      }]
      + [range(1; 6) as $repetition | {
        id: ("safari-existing-r" + ($repetition | tostring)),
        target: {
          id: "safari",
          displayName: "Safari",
          bundleIdentifier: "com.apple.Safari",
          kind: "browser"
        },
        textScenario: "existingText",
        repetition: $repetition,
        assessment: {status: "passed", passed: true},
        latencyTrace: {events: []}
      }]
    )
  ' "$report" > "$completed"
  mv "$completed" "$report"
}

complete_smoke_matrix "$TEMP_ROOT/known-bad.json"
complete_smoke_matrix "$TEMP_ROOT/fixed-fallback.json"

for ((index = 1; index <= 20; index += 1)); do
  process_id=$((1000 + index))
  printf '2026-09-04T10:%02d:00Z\t%s\t%s\t%s\t%s\t%s\n' \
    "$index" \
    "$process_id" \
    "$APP_SHA" \
    "$APP_SHA" \
    "$APP_PATH" \
    "$APP_PATH" \
    >> "$LAUNCH_EVENTS"
  printf '2026-09-04T10:%02d:30Z\t%s\n' \
    "$index" \
    "$process_id" \
    >> "$TERMINATION_EVENTS"
done

jq '
  .cases[0].id = "ordinary-nonempty-final"
  | .cases[0].latencyTrace.events = [
      {"name": "streaming_event.first_partial", "details": "chars=10"},
      {"name": "fluid_streaming.final_asr.end", "details": "durationMs=146.5 chars=29"},
      {"name": "streaming_event.first_commit", "details": "chars=29"}
    ]
' "$TEMP_ROOT/fixed-fallback.json" > "$TEMP_ROOT/ordinary-pass.json"

jq '
  .cases[0].id = "empty-without-live-recognition"
  | del(.cases[0].latencyTrace.events[0])
' "$TEMP_ROOT/known-bad.json" > "$TEMP_ROOT/generic-empty.json"

jq '
  .cases[5].id = "unrelated-target-failure"
  | .cases[5].assessment = {"status": "targetUnavailable", "passed": false}
' "$TEMP_ROOT/known-bad.json" > "$TEMP_ROOT/mixed-failure.json"

jq '
  .cases[0].assessment = {"status": "passed", "passed": true}
  | .cases[5].id = "wrong-textedit-bundle-empty-final"
  | .cases[5].textScenario = "empty"
  | .cases[5].target.bundleIdentifier = "com.apple.Safari"
  | .cases[5].assessment = {"status": "emptyTranscript", "passed": false}
  | .cases[5].latencyTrace.events = .cases[0].latencyTrace.events
' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/wrong-textedit-bundle.json"
jq '
  .cases[0].assessment = {"status": "passed", "passed": true}
  | .cases[5].id = "wrong-textedit-kind-empty-final"
  | .cases[5].textScenario = "empty"
  | .cases[5].target.kind = "browser"
  | .cases[5].assessment = {"status": "emptyTranscript", "passed": false}
  | .cases[5].latencyTrace.events = .cases[0].latencyTrace.events
' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/wrong-textedit-kind.json"

jq '.fatalError = "cleanup crashed"' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-fatal.json"
jq '.restoredOriginalState = false' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-unrestored.json"
jq '.preflight.voiceInk.runningPaths = ["/Applications/roma just talk.app"]
    | .voiceInkSession.originallyRunningPaths = ["/Applications/roma just talk.app"]' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-warm-start.json"
jq '.configuration.voiceInkLifecycle = "reuse"' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-reused-process.json"
jq '.configuration.repetitions = 3' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-three-repetitions.json"
jq 'del(.cases[4])' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-missing-trial.json"
jq '.configuration.audioLeadSeconds = 1.2' \
  "$TEMP_ROOT/known-bad.json" \
  > "$TEMP_ROOT/known-bad-contract-mismatch.json"

cat > "$TEMP_ROOT/evidence-contract.json" <<'JSON'
{
  "schemaVersion": 1,
  "toolingSha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "runtimeMode": "smoke",
  "requireAppTranslocation": false,
  "platform": {
    "productVersion": "26.3.1",
    "buildVersion": "25D2128",
    "architecture": "arm64"
  },
  "audio": {
    "sourceKind": "public",
    "fixtureName": "public quick release.wav",
    "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "durationSeconds": 5.64
  },
  "model": {
    "revision": "cccccccccccccccccccccccccccccccccccccccc",
    "manifestSha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    "storage": "normal-application-support",
    "prewarmOnWake": true
  },
  "helperExecutableSha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  "configuration": {
    "voiceInkBundleIdentifier": "com.negentropi.RomaJustTalk",
    "repetitions": 5,
    "voiceInkLifecycle": "relaunchPerCase",
    "targets": [
      {"id":"textedit","displayName":"TextEdit","bundleIdentifier":"com.apple.TextEdit","kind":"document"},
      {"id":"safari","displayName":"Safari","bundleIdentifier":"com.apple.Safari","kind":"browser"}
    ]
  }
}
JSON
jq '.audio.sha256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  "$TEMP_ROOT/evidence-contract.json" \
  > "$TEMP_ROOT/different-evidence-contract.json"
jq '.configuration.voiceInkLifecycle = "reuse"' \
  "$TEMP_ROOT/evidence-contract.json" \
  > "$TEMP_ROOT/baseline-reused-process-contract.json"
jq '.configuration.repetitions = 3' \
  "$TEMP_ROOT/evidence-contract.json" \
  > "$TEMP_ROOT/baseline-three-repetitions-contract.json"

verify_known_bad() {
  bash "$VERIFIER" \
    known-bad \
    "$1" \
    "$TEMP_ROOT/evidence-contract.json" \
    "${2:-$LAUNCH_EVENTS}" \
    "${3:-$TERMINATION_EVENTS}"
}

verify_fixed() {
  bash "$VERIFIER" \
    fixed \
    "$1" \
    "$TEMP_ROOT/evidence-contract.json" \
    "${2:-$LAUNCH_EVENTS}" \
    "${3:-$TERMINATION_EVENTS}" \
    "${4:-$TEMP_ROOT/known-bad.json}" \
    "$TEMP_ROOT/evidence-contract.json"
}

verify_fixed_with_baseline_contract() {
  bash "$VERIFIER" \
    fixed \
    "$1" \
    "$TEMP_ROOT/evidence-contract.json" \
    "${2:-$LAUNCH_EVENTS}" \
    "${3:-$TERMINATION_EVENTS}" \
    "$4" \
    "$5"
}

# A second, live-shape baseline proves that the verifier derives the affected
# target/scenario profile from the known-bad report instead of hard-coding
# TextEdit empty. Safari fails in both supported text scenarios here.
jq '
  .cases[0].assessment = {status: "passed", passed: true}
  | .cases[0].latencyTrace.events = []
  | .cases[10].assessment = {status: "emptyTranscript", passed: false}
  | .cases[10].latencyTrace.events = [
      {name: "streaming_event.first_partial", details: "chars=18"},
      {name: "fluid_streaming.final_asr.end", details: "chars=0"},
      {name: "streaming_event.first_commit", details: "chars=0"}
    ]
  | .cases[15].assessment = {status: "emptyTranscript", passed: false}
  | .cases[15].latencyTrace.events = [
      {name: "streaming_event.first_partial", details: "chars=18"},
      {name: "fluid_streaming.final_asr.end", details: "chars=0"},
      {name: "streaming_event.first_commit", details: "chars=0"}
    ]
' "$TEMP_ROOT/known-bad.json" > "$TEMP_ROOT/known-bad-safari.json"

jq '
  .cases[0].latencyTrace.events = []
  | .cases[0].visibleText = null
  | .cases[10].visibleText = {text: "safari empty fallback"}
  | .cases[10].latencyTrace.events = [
      {name: "streaming_event.first_partial", details: "chars=18"},
      {name: "fluid_streaming.final_asr.end", details: "chars=0"},
      {name: "fluid_streaming.commit.fallback_to_hypothesis", details: "chars=18"},
      {name: "streaming_event.first_commit", details: "chars=18"}
    ]
  | .cases[15].visibleText = {text: "safari existing fallback"}
  | .cases[15].latencyTrace.events = [
      {name: "streaming_event.first_partial", details: "chars=18"},
      {name: "fluid_streaming.final_asr.end", details: "chars=0"},
      {name: "fluid_streaming.commit.fallback_to_hypothesis", details: "chars=18"},
      {name: "streaming_event.first_commit", details: "chars=18"}
    ]
' "$TEMP_ROOT/fixed-fallback.json" > "$TEMP_ROOT/fixed-safari-fallback.json"

jq '.preflight.targets |= map(select(.id != "safari"))' \
  "$TEMP_ROOT/known-bad-safari.json" > "$TEMP_ROOT/safari-absent-preflight.json"
jq '(.preflight.targets[] | select(.id == "safari")).displayName = "Wrong Safari"' \
  "$TEMP_ROOT/known-bad-safari.json" > "$TEMP_ROOT/safari-target-tuple-mismatch.json"
jq '.configuration.targets[1] = {id:"notes",displayName:"Notes",bundleIdentifier:"com.apple.Notes",kind:"document"}' \
  "$TEMP_ROOT/known-bad-safari.json" > "$TEMP_ROOT/safari-absent-config.json"
jq '.configuration.targets[1] = {id:"notes",displayName:"Notes",bundleIdentifier:"com.apple.Notes",kind:"document"}' \
  "$TEMP_ROOT/evidence-contract.json" > "$TEMP_ROOT/safari-absent-config-contract.json"
jq '.cases[10].assessment = {status: "emptyTranscript", passed: false}
    | .cases[10].latencyTrace.events = .cases[0].latencyTrace.events' \
  "$TEMP_ROOT/known-bad.json" > "$TEMP_ROOT/failures-split-targets.json"
jq '.cases[10].visibleText = {text: "safari empty fallback"}
    | .cases[10].latencyTrace.events = [
        {name: "streaming_event.first_partial", details: "chars=18"},
        {name: "fluid_streaming.final_asr.end", details: "chars=0"},
        {name: "fluid_streaming.commit.fallback_to_hypothesis", details: "chars=18"},
        {name: "streaming_event.first_commit", details: "chars=18"}
      ]' "$TEMP_ROOT/fixed-fallback.json" > "$TEMP_ROOT/fixed-multi-target-fallback.json"
jq '.cases[0].visibleText = null | .cases[0].latencyTrace.events = []' \
  "$TEMP_ROOT/fixed-multi-target-fallback.json" > "$TEMP_ROOT/missing-textedit-affected-pair.json"
jq '.cases[10].visibleText = null | .cases[10].latencyTrace.events = []' \
  "$TEMP_ROOT/fixed-multi-target-fallback.json" > "$TEMP_ROOT/missing-safari-affected-pair.json"
jq '.cases[10].visibleText = null | .cases[10].latencyTrace.events = []
    | .cases[15].visibleText = {text: "wrong safari scenario fallback"}
    | .cases[15].latencyTrace.events = [
        {name: "streaming_event.first_partial", details: "chars=18"},
        {name: "fluid_streaming.final_asr.end", details: "chars=0"},
        {name: "fluid_streaming.commit.fallback_to_hypothesis", details: "chars=18"},
        {name: "streaming_event.first_commit", details: "chars=18"}
      ]' "$TEMP_ROOT/fixed-multi-target-fallback.json" > "$TEMP_ROOT/mismatched-target-scenario-fallback.json"
jq '.cases[15].visibleText = null | .cases[15].latencyTrace.events = []' \
  "$TEMP_ROOT/fixed-safari-fallback.json" > "$TEMP_ROOT/missing-safari-existing-fallback.json"
jq '.cases[10].latencyTrace.events = [
      {name: "streaming_event.first_partial", details: "chars=18"},
      {name: "fluid_streaming.final_asr.end", details: "chars=0"},
      {name: "streaming_event.first_commit", details: "chars=18"},
      {name: "fluid_streaming.commit.fallback_to_hypothesis", details: "chars=18"}
    ]' "$TEMP_ROOT/fixed-safari-fallback.json" > "$TEMP_ROOT/out-of-order-safari-fallback.json"
jq '.cases[0].latencyTrace.events = [
      {name: "streaming_event.first_commit", details: "chars=18"},
      {name: "streaming_event.first_partial", details: "chars=18"},
      {name: "fluid_streaming.final_asr.end", details: "chars=0"},
      {name: "streaming_event.first_commit", details: "chars=0"}
    ]' "$TEMP_ROOT/known-bad.json" > "$TEMP_ROOT/duplicate-known-bad-first-commit.json"
jq '.cases[0].latencyTrace.events += [
      {name: "streaming_event.first_commit", details: "chars=18"}
    ]' "$TEMP_ROOT/fixed-fallback.json" > "$TEMP_ROOT/duplicate-fixed-first-commit.json"
jq '.cases[0].latencyTrace.events += [
      {name: "fluid_streaming.final_asr.end", details: "chars=0"}
    ]' "$TEMP_ROOT/fixed-fallback.json" > "$TEMP_ROOT/duplicate-fixed-final.json"
jq '.cases[0].latencyTrace.events += [
      {name: "fluid_streaming.commit.fallback_to_hypothesis", details: "chars=18"}
    ]' "$TEMP_ROOT/fixed-fallback.json" > "$TEMP_ROOT/duplicate-fixed-fallback.json"

verify_known_bad "$TEMP_ROOT/known-bad.json"
verify_fixed "$TEMP_ROOT/fixed-fallback.json"
verify_known_bad "$TEMP_ROOT/known-bad-safari.json"
verify_fixed "$TEMP_ROOT/fixed-safari-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-safari.json"

expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/ordinary-pass.json"
expect_failure \
  "no case reproduced the live-partial to empty-final bug" \
  verify_known_bad "$TEMP_ROOT/generic-empty.json"
expect_failure \
  "no case reproduced the live-partial to empty-final bug" \
  verify_known_bad "$TEMP_ROOT/duplicate-known-bad-first-commit.json"
expect_failure \
  "runtime E2E report did not contain the complete 20-case smoke matrix" \
  verify_known_bad "$TEMP_ROOT/wrong-textedit-bundle.json"
expect_failure \
  "runtime E2E report did not contain the complete 20-case smoke matrix" \
  verify_known_bad "$TEMP_ROOT/wrong-textedit-kind.json"
expect_failure \
  "no case reproduced the live-partial to empty-final bug" \
  verify_known_bad "$TEMP_ROOT/mixed-failure.json"
expect_failure \
  "no case reproduced the live-partial to empty-final bug" \
  verify_known_bad "$TEMP_ROOT/safari-absent-preflight.json"
expect_failure \
  "no case reproduced the live-partial to empty-final bug" \
  verify_known_bad "$TEMP_ROOT/safari-target-tuple-mismatch.json"
expect_failure \
  "runtime E2E evidence contract is invalid" \
  bash "$VERIFIER" known-bad "$TEMP_ROOT/safari-absent-config.json" "$TEMP_ROOT/safari-absent-config-contract.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS"
verify_known_bad "$TEMP_ROOT/failures-split-targets.json"
verify_fixed "$TEMP_ROOT/fixed-multi-target-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/failures-split-targets.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/missing-textedit-affected-pair.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/failures-split-targets.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/missing-safari-affected-pair.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/failures-split-targets.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/mismatched-target-scenario-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/failures-split-targets.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/fixed-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-safari.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/missing-safari-existing-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-safari.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/out-of-order-safari-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-safari.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/duplicate-fixed-first-commit.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/duplicate-fixed-final.json"
expect_failure \
  "fixed report did not prove ordered fallback delivery for every affected baseline target/scenario pair" \
  verify_fixed "$TEMP_ROOT/duplicate-fixed-fallback.json"
expect_failure \
  "verified known-bad report contains a fatal error" \
  verify_fixed "$TEMP_ROOT/fixed-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-fatal.json"
expect_failure \
  "verified known-bad report did not restore original state" \
  verify_fixed "$TEMP_ROOT/fixed-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-unrestored.json"
expect_failure \
  "verified known-bad report did not begin from a stopped app" \
  verify_fixed "$TEMP_ROOT/fixed-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-warm-start.json"
expect_failure \
  "verified known-bad report did not use five relaunch-per-case trials" \
  verify_fixed_with_baseline_contract "$TEMP_ROOT/fixed-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-reused-process.json" "$TEMP_ROOT/baseline-reused-process-contract.json"
expect_failure \
  "verified known-bad report did not use five relaunch-per-case trials" \
  verify_fixed_with_baseline_contract "$TEMP_ROOT/fixed-fallback.json" "$LAUNCH_EVENTS" "$TERMINATION_EVENTS" "$TEMP_ROOT/known-bad-three-repetitions.json" "$TEMP_ROOT/baseline-three-repetitions-contract.json"
expect_failure \
  "runtime E2E report contains a fatal error" \
  verify_known_bad "$TEMP_ROOT/known-bad-fatal.json"
expect_failure \
  "runtime E2E report did not restore original state" \
  verify_known_bad "$TEMP_ROOT/known-bad-unrestored.json"
expect_failure \
  "runtime E2E report did not begin from a stopped app" \
  verify_known_bad "$TEMP_ROOT/known-bad-warm-start.json"
expect_failure \
  "runtime E2E report does not match its evidence contract" \
  verify_known_bad "$TEMP_ROOT/known-bad-reused-process.json"
expect_failure \
  "runtime E2E report does not match its evidence contract" \
  verify_known_bad "$TEMP_ROOT/known-bad-three-repetitions.json"
expect_failure \
  "runtime E2E report did not contain the complete 20-case smoke matrix" \
  verify_known_bad "$TEMP_ROOT/known-bad-missing-trial.json"
expect_failure \
  "runtime E2E report does not match its evidence contract" \
  verify_known_bad "$TEMP_ROOT/known-bad-contract-mismatch.json"

head -n 19 "$LAUNCH_EVENTS" > "$TEMP_ROOT/missing-launch.tsv"
expect_failure \
  "fresh-process lifecycle did not record one launch per runtime case" \
  verify_known_bad \
    "$TEMP_ROOT/known-bad.json" \
    "$TEMP_ROOT/missing-launch.tsv" \
    "$TERMINATION_EVENTS"
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 20 { $2 = 1001 } { print }' \
  "$LAUNCH_EVENTS" > "$TEMP_ROOT/duplicate-launch.tsv"
expect_failure \
  "fresh-process lifecycle reused a Roma process" \
  verify_known_bad \
    "$TEMP_ROOT/known-bad.json" \
    "$TEMP_ROOT/duplicate-launch.tsv" \
    "$TERMINATION_EVENTS"
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 20 { $2 = 9999 } { print }' \
  "$TERMINATION_EVENTS" > "$TEMP_ROOT/mismatched-termination.tsv"
expect_failure \
  "fresh-process launch and termination PIDs differ" \
  verify_known_bad \
    "$TEMP_ROOT/known-bad.json" \
    "$LAUNCH_EVENTS" \
    "$TEMP_ROOT/mismatched-termination.tsv"
expect_failure \
  "fixed proof requires a verified known-bad report and evidence contract" \
  bash "$VERIFIER" \
    fixed \
    "$TEMP_ROOT/fixed-fallback.json" \
    "$TEMP_ROOT/evidence-contract.json" \
    "$LAUNCH_EVENTS" \
    "$TERMINATION_EVENTS"
expect_failure \
  "fixed and known-bad evidence contracts differ" \
  bash "$VERIFIER" \
    fixed \
    "$TEMP_ROOT/fixed-fallback.json" \
    "$TEMP_ROOT/evidence-contract.json" \
    "$LAUNCH_EVENTS" \
    "$TERMINATION_EVENTS" \
    "$TEMP_ROOT/known-bad.json" \
    "$TEMP_ROOT/different-evidence-contract.json"
expect_failure \
  "usage:" \
  bash "$VERIFIER" \
    unsupported \
    "$TEMP_ROOT/known-bad.json" \
    "$TEMP_ROOT/evidence-contract.json" \
    "$LAUNCH_EVENTS" \
    "$TERMINATION_EVENTS"

echo "runtime empty-final regression evidence checks passed"
