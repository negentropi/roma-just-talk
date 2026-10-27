#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != true || "$(uname -s)" != Darwin ]]; then
  echo "Run writing-feature verification only on a disposable macOS Actions runner." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The writing-feature runner must own the logged-in desktop session." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mode="${1:-}"
candidate_sha="$(git rev-parse HEAD)"
debug_dir="$repo_root/.local-build"
debug_app="$debug_dir/Build/Products/Debug/roma just talk.app"
test_names=(
  spokenSnippetPipelineInsertsExactWholeTriggerContentAndSavesIt
  spokenSnippetPipelinePreservesInlineCapitalsPunctuationAndParagraphs
  spokenSnippetPipelineLeavesUnmatchedDictationOnItsExistingFormattingPath
)

test_arguments() {
  local checkout="$1" derived="$2"
  arguments=(
    -project "$checkout/VoiceInk.xcodeproj" -scheme VoiceInk -configuration Debug
    -destination 'platform=macOS' -parallel-testing-enabled NO
    -derivedDataPath "$derived" -xcconfig "$checkout/LocalBuild.xcconfig"
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
    DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$checkout/VoiceInk/VoiceInk.local.entitlements"
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
  )
}

select_tests() {
  selectors=()
  local name
  for name in "$@"; do
    selectors+=("-only-testing:VoiceInkTests/VoiceInkTests/$name")
  done
}

verify_observations() {
  python3 - "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path, expectation, exit_code, output, *names = sys.argv[1:]
text = Path(log_path).read_text(errors="replace")
observations = {}
for name in names:
    started = re.findall(r"Test " + re.escape(name) + r"\(\) started\.", text)
    finished = re.findall(r"Test " + re.escape(name) + r"\(\) (passed|failed) after ", text)
    if len(started) != 1 or len(finished) != 1:
        raise SystemExit(f"Invalid evidence: {name} must start and finish exactly once")
    observations[name] = finished[0]

summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
if len(summaries) != 1 or int(summaries[0][0]) != len(names):
    raise SystemExit("Invalid evidence: filtered Swift Testing count does not match the test contract")
expected = {name: "passed" for name in names}
if expectation == "known-bad":
    expected[names[0]] = expected[names[1]] = "failed"
    if int(exit_code) != 65 or summaries[0][1] != "failed":
        raise SystemExit("Invalid baseline: expected assertion failures, not build/launch failure or green")
elif int(exit_code) != 0 or summaries[0][1] != "passed":
    raise SystemExit("Candidate tests did not all pass")
if observations != expected:
    raise SystemExit(f"Invalid evidence: expected {expected}, got {observations}")
Path(output).write_text(json.dumps({"expectation": expectation, "exit_code": int(exit_code), "tests": observations}, indent=2) + "\n")
PY
}

test -d "$debug_dir/onboarding-test-evidence/Debug.xcresult"
codesign --verify --deep --strict "$debug_app"

case "$mode" in
  live)
    out="$debug_dir/onboarding-test-evidence/writing-target-live"
    mkdir -p "$out"
    live_names=(
      liveWritingTargetTextEditPreservesUnicodeOutsideSelection
      liveWritingTargetTextEditRefusesRangeTextAndFocusDrift
      liveWritingTargetSafariTextareaReplacesOnlySelection
    )
    test_arguments "$repo_root" "$debug_dir"
    select_tests "${live_names[@]}"
    shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" > "$out/identity-before.txt"
    test_exit=0
    RJT_LIVE_WRITING_TARGET_CHECKS=1 TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS=1 \
      RJT_LIVE_WRITING_TARGET_EVIDENCE="$out" TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE="$out" \
      xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" \
        -resultBundlePath "$out/Live.xcresult" > "$out/tests.log" 2>&1 || test_exit=$?
    shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" > "$out/identity-after.txt"
    cmp "$out/identity-before.txt" "$out/identity-after.txt"
    codesign --verify --deep --strict "$debug_app"
    if ! verify_observations "$out/tests.log" fixed "$test_exit" "$out/result.json" "${live_names[@]}"; then
      tail -n 120 "$out/tests.log" >&2
      exit 1
    fi
    ;;
  regression)
    baseline_ref="${2:-}"
    if [[ ! "$baseline_ref" =~ ^[0-9a-f]{40}$ || "$baseline_ref" == "$candidate_sha" ]]; then
      echo "Pass an immutable known-bad commit distinct from the candidate." >&2
      exit 2
    fi
    out="$RUNNER_TEMP/writing-feature-regression"
    baseline="$RUNNER_TEMP/writing-feature-baseline"
    test ! -e "$out"
    test ! -e "$baseline"
    mkdir -p "$out"
    phase=baseline-checkout
    trap 'code=$?; if [[ "$code" != 0 ]]; then printf "{\"classification\":\"invalid\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi' EXIT
    git fetch --no-tags origin "$baseline_ref"
    git worktree add --detach "$baseline" "$baseline_ref"
    test "$(git -C "$baseline" rev-parse HEAD)" = "$baseline_ref"
    oracle=VoiceInkTests/SpokenSnippetPipelineTests.swift
    test -f "$repo_root/$oracle"
    test ! -e "$baseline/$oracle"
    cp "$repo_root/$oracle" "$baseline/$oracle"
    cmp "$repo_root/$oracle" "$baseline/$oracle"
    resolved=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    cmp "$repo_root/$resolved" "$baseline/$resolved"
    {
      printf 'candidate=%s\nbaseline=%s\n' "$candidate_sha" "$baseline_ref"
      xcodebuild -version
      sw_vers
      uname -m
      shasum -a 256 "$repo_root/$oracle" "$baseline/$oracle" "$repo_root/$resolved" "$baseline/$resolved"
      shasum -a 256 "$repo_root/VoiceInk/Transcription/Engine/TranscriptionPipeline.swift" "$baseline/VoiceInk/Transcription/Engine/TranscriptionPipeline.swift"
    } > "$out/contract.txt"
    test_arguments "$baseline" "$baseline/.local-build"
    select_tests "${test_names[@]}"
    phase=baseline-build
    if ! xcodebuild build-for-testing "${arguments[@]}" "${selectors[@]}" \
      -clonedSourcePackagesDirPath "$debug_dir/SourcePackages" \
      -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile > "$out/baseline-build.log" 2>&1; then
      tail -n 120 "$out/baseline-build.log" >&2
      exit 1
    fi
    phase=baseline-tests
    baseline_exit=0
    xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" \
      -resultBundlePath "$out/Baseline.xcresult" > "$out/baseline-tests.log" 2>&1 || baseline_exit=$?
    if ! verify_observations "$out/baseline-tests.log" known-bad "$baseline_exit" "$out/baseline-result.json" "${test_names[@]}"; then
      tail -n 120 "$out/baseline-tests.log" >&2
      exit 1
    fi
    phase=candidate-tests
    test_arguments "$repo_root" "$debug_dir"
    candidate_exit=0
    xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" \
      -resultBundlePath "$out/Candidate.xcresult" > "$out/candidate-tests.log" 2>&1 || candidate_exit=$?
    if ! verify_observations "$out/candidate-tests.log" fixed "$candidate_exit" "$out/candidate-result.json" "${test_names[@]}"; then
      tail -n 120 "$out/candidate-tests.log" >&2
      exit 1
    fi
    cmp "$repo_root/$oracle" "$baseline/$oracle"
    printf '{"classification":"matched-red-green","candidate":"%s","baseline":"%s"}\n' \
      "$candidate_sha" "$baseline_ref" > "$out/result.json"
    ;;
  ui)
    out="$debug_dir/onboarding-test-evidence/writing-ui"
    mkdir -p "$out"
    phase=ui-build
    trap 'code=$?; if [[ "$code" != 0 ]]; then printf "{\"classification\":\"invalid-or-failed\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi' EXIT
    test_arguments "$repo_root" "$debug_dir"
    ui_selector='-only-testing:VoiceInkUITests/WritingFeaturesUITests'
    if ! xcodebuild build-for-testing "${arguments[@]}" "$ui_selector" > "$out/build.log" 2>&1; then
      printf '{"classification":"invalid","boundary":"ui-build"}\n' > "$out/result.json"
      tail -n 120 "$out/build.log" >&2
      exit 1
    fi
    codesign --verify --deep --strict "$debug_app"
    codesign -dr - "$debug_app" 2>&1 | sed -n \
      -e 's/^# designated => //p' -e 's/^designated => //p' > "$out/host-requirement.txt"
    test -s "$out/host-requirement.txt"
    csreq -r "$out/host-requirement.txt" -b "$out/host.csreq"
    requirement_hex="$(xxd -p "$out/host.csreq" | tr -d '\n')"
    test -n "$requirement_hex"
    phase=ui-permissions
    grant_sql() {
      printf '%s\n' "INSERT OR REPLACE INTO access(
service,client,client_type,auth_value,auth_reason,auth_version,csreq,
indirect_object_identifier_type,indirect_object_identifier,flags
) VALUES('$1','com.negentropi.RomaJustTalk',0,2,4,1,X'$requirement_hex',0,'UNUSED',0);"
    }
    grant_sql kTCCServiceAccessibility | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'
    grant_sql kTCCServiceMicrophone | sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    killall tccd 2>/dev/null || true
    sudo killall tccd 2>/dev/null || true
    sleep 2
    shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" > "$out/identity-before.txt"
    phase=ui-tests
    test_exit=0
    RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_RJT_WRITING_UI_CHECKS=1 \
      xcodebuild test-without-building "${arguments[@]}" "$ui_selector" \
        -resultBundlePath "$out/UI.xcresult" > "$out/tests.log" 2>&1 || test_exit=$?
    shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" > "$out/identity-after.txt"
    cmp "$out/identity-before.txt" "$out/identity-after.txt"
    codesign --verify --deep --strict "$debug_app"
    if ! python3 - "$out/tests.log" "$test_exit" "$out/result.json" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path, exit_code, output = sys.argv[1:]
text = Path(log_path).read_text(errors="replace")
names = [
    "testSnippetLibraryPreservesLiteralContentAcrossEditAndRelaunch",
    "testCSVImportPreviewsMultilineContentBeforeReplacing",
    "testTranslationTargetsReorderSelectAndPersist",
]
observations = {}
for name in names:
    prefix = r"Test Case '[^'\n]*WritingFeaturesUITests[ ./]" + re.escape(name) + r"(?:\(\))?\]?' "
    started = re.findall(prefix + r"started\.", text)
    finished = re.findall(prefix + r"(passed|failed|skipped)", text)
    observations[name] = {"starts": len(started), "results": finished}
counts = re.findall(r"Executed (\d+) tests?,[^\n]*?with (\d+) failures?", text)
valid = int(exit_code) == 0 and bool(counts) and all(
    int(count) == 3 and int(failures) == 0 for count, failures in counts
) and all(value == {"starts": 1, "results": ["passed"]} for value in observations.values())
Path(output).write_text(json.dumps({"classification": "passed" if valid else "invalid-or-failed", "exit_code": int(exit_code), "tests": observations}, indent=2) + "\n")
if not valid:
    raise SystemExit("UI verification requires exactly three started, passed tests and no skips")
PY
    then
      tail -n 120 "$out/tests.log" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 live | regression <known-bad-full-sha> | ui" >&2
    exit 2
    ;;
esac
