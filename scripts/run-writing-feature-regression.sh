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
resolved=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
canonical_sha256=bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f

verify_lock() {
  local checkout="$1"
  test "$(shasum -a 256 "$checkout/$resolved" | awk '{print $1}')" = "$canonical_sha256"
}

# Historical lanes receive only the reviewed lock, after their declarations match.
if [[ "$mode" == packages ]]; then
  package_out="${2:?Pass an evidence directory}"
  baseline="${3:-}"
  verified_sha="${4:-}"
  package_checkouts="${5:-$debug_dir/SourcePackages}"
  mkdir -p "$package_out"
  python3 - "$repo_root" "$package_out" "$baseline" "$verified_sha" "$resolved" "$canonical_sha256" <<'PY'
import difflib
import hashlib
import json
import subprocess
import sys
from pathlib import Path

candidate, output = map(Path, sys.argv[1:3])
baseline_arg, verified, lock_path, expected_hash = sys.argv[3:]
digest = lambda data: hashlib.sha256(data).hexdigest()
canonical = (candidate / lock_path).read_bytes()
if digest(canonical) != expected_hash:
    raise SystemExit("Candidate lock differs from the reviewed canonical resolution")

def pins(data):
    values = json.loads(data)["pins"]
    result = {pin["identity"]: pin for pin in values}
    if len(result) != len(values):
        raise SystemExit("Duplicate package identities in lock")
    return result

canonical_pins = pins(canonical)
if len(canonical_pins) != 41:
    raise SystemExit("Canonical graph must contain the reviewed 41 pins")

def declarations(root):
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"]).split(b"\0")
    return {value.decode(): (root / value.decode()).read_bytes() for value in tracked if value and (value.endswith(b"/Package.swift") or value in (b"Package.swift", b"VoiceInk.xcodeproj/project.pbxproj"))}

inputs = declarations(candidate)
receipt = {"canonical_sha256": expected_hash, "canonical_pin_count": 41, "declaration_sha256": {path: digest(data) for path, data in inputs.items()}, "source": "reviewed Xcode resolution run 40482229518", "scope": "package metadata only; existing pins and all dependency declarations unchanged"}
(output / "canonical.Package.resolved").write_bytes(canonical)

def validate_previous(original, label):
    if digest(original) != "2cdda5176a184329f2ca828316bfdefd9578d94bfed96a2b48b34b42b851e84c":
        raise SystemExit(f"{label}: original lock is not the reviewed 24-pin lock")
    previous = pins(original)
    retained = all(canonical_pins.get(key) == value for key, value in previous.items())
    if not retained or len(previous) != 24 or len(canonical_pins.keys() - previous.keys()) != 17:
        raise SystemExit(f"{label}: canonical lock must preserve all 24 original pins and add exactly 17")
    (output / f"{label}-original.Package.resolved").write_bytes(original)
    (output / f"{label}-lock.patch").write_text("".join(difflib.unified_diff(original.decode().splitlines(keepends=True), canonical.decode().splitlines(keepends=True), fromfile="a/" + lock_path, tofile="b/" + lock_path)))
    return {"original_sha256": digest(original), "retained_pin_count": len(previous), "added_pin_identities": sorted(canonical_pins.keys() - previous.keys()), "changed_pins": [], "removed_pins": []}

if baseline_arg:
    baseline = Path(baseline_arg)
    if declarations(baseline) != inputs:
        raise SystemExit("Historical dependency declaration paths or bytes differ from candidate")
    receipt["baseline"] = validate_previous((baseline / lock_path).read_bytes(), "baseline")
    receipt["baseline"]["declarations_identical"] = True
    (baseline / lock_path).write_bytes(canonical)

if verified:
    production = ["VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS"]
    subprocess.run(["git", "-C", str(candidate), "diff", "--quiet", "HEAD", "--", *production], check=True)
    changed = subprocess.check_output(["git", "-C", str(candidate), "diff", "--name-only", verified, "HEAD", "--", *production], text=True).splitlines()
    if changed != [lock_path]:
        raise SystemExit(f"Candidate differs from verified production outside the reviewed lock: {changed}")
    for path, data in inputs.items():
        original = subprocess.check_output(["git", "-C", str(candidate), "show", f"{verified}:{path}"])
        if original != data:
            raise SystemExit(f"Verified production dependency declaration differs: {path}")
    original = subprocess.check_output(["git", "-C", str(candidate), "show", f"{verified}:{lock_path}"])
    receipt["verified_production"] = validate_previous(original, "verified")
    receipt["verified_production"].update({"sha": verified, "only_changed_production_path": lock_path, "declarations_identical": True})

(output / "canonical-graph-contract.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
PY
  for lane in candidate baseline; do
    checkout="$repo_root"
    [[ "$lane" != baseline ]] || checkout="$baseline"
    [[ -n "$checkout" ]] || continue
    verify_lock "$checkout"
    resolve_exit=0
    xcodebuild -resolvePackageDependencies -project "$checkout/VoiceInk.xcodeproj" -scheme VoiceInk \
      -derivedDataPath "$RUNNER_TEMP/writing-package-derived-$lane" -clonedSourcePackagesDirPath "$package_checkouts" \
      -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
      > "$package_out/$lane-strict-resolve.log" 2>&1 || resolve_exit=$?
    verify_lock "$checkout"
    printf '{"exit_code":%s,"canonical_lock_unchanged":true}\n' "$resolve_exit" > "$package_out/$lane-strict-resolve.json"
    if [[ "$resolve_exit" != 0 ]]; then
      tail -n 100 "$package_out/$lane-strict-resolve.log" >&2
      exit "$resolve_exit"
    fi
  done
  exit 0
fi

verify_lock "$repo_root"
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
    -clonedSourcePackagesDirPath "$debug_dir/SourcePackages"
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
    DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$checkout/VoiceInk/VoiceInk.local.entitlements"
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
  )
}

select_tests() {
  selectors=()
  local name
  for name in "$@"; do
    selectors+=("-only-testing:VoiceInkTests/VoiceInkTests/$name()")
  done
}

preflight_selected_tests() {
  local directory="$1" flag
  mkdir -p "$directory"
  xcodebuild -help > "$directory/xcodebuild-help.txt" 2>&1 || true
  for flag in -enumerate-tests -test-enumeration-style -test-enumeration-format -test-enumeration-output-path; do
    if ! grep -Fq -- "$flag" "$directory/xcodebuild-help.txt"; then
      echo "The current Xcode does not advertise $flag; selection proof is unavailable." >&2
      return 1
    fi
  done
  if ! xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" \
    -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
    -test-enumeration-output-path "$directory/selected-tests.json" > "$directory/enumeration.log" 2>&1; then
    tail -n 80 "$directory/enumeration.log" >&2
    return 1
  fi
  python3 - "$directory" "${selectors[@]}" <<'PY'
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
expected = [value.removeprefix("-only-testing:") for value in sys.argv[2:]]
payload = json.loads((directory / "selected-tests.json").read_text())
if payload.get("errors"):
    raise SystemExit("Xcode reported test-enumeration errors")
enabled = [test["identifier"] for plan in payload.get("values", []) for test in plan.get("enabledTests", [])]
disabled = [test.get("identifier") for plan in payload.get("values", []) for test in plan.get("disabledTests", [])]
valid = len(enabled) == len(expected) and sorted(enabled) == sorted(expected) and not set(disabled).intersection(expected)
(directory / "selection-receipt.json").write_text(json.dumps({"requested_identifiers": expected, "enabled_identifiers": enabled, "disabled_identifiers": disabled, "valid": valid}, indent=2) + "\n")
if not valid:
    raise SystemExit(f"Exact selected tests did not resolve: expected {expected}, got enabled={enabled}, disabled={disabled}")
PY
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

verify_permission_observations() {
  python3 - "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path, expectation, exit_code, output = sys.argv[1:]
text = Path(log_path).read_text(errors="replace")
name = "permissionWaitReservesOneRecordingStart"
started = re.findall(r"Test " + name + r"\(\) started\.", text)
finished = re.findall(r"Test " + name + r"\(\) (passed|failed) after ", text)
summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
expected_result = "failed" if expectation == "known-bad" else "passed"
valid = len(started) == 1 and finished == [expected_result] and summaries == [("1", expected_result)]
diagnostics = {}
if expectation == "known-bad":
    diagnostics = {
        "permission_wait_left_state_idle": bool(re.search(r"Expectation failed:[^\n]*recordingState[^\n]*\bidle\b[^\n]*\bstarting\b", text)),
        "duplicate_permission_calls": bool(re.search(r"Expectation failed:[^\n]*gate\.calls[^\n]*→\s*2\)?\s*==\s*1", text)),
    }
    valid = valid and int(exit_code) == 65 and all(diagnostics.values())
else:
    valid = valid and int(exit_code) == 0
Path(output).write_text(json.dumps({"expectation": expectation, "classification": "deferred-permission-callback" if valid else "invalid-or-failed", "exit_code": int(exit_code), "test": {name: finished}, "diagnostics": diagnostics}, indent=2) + "\n")
if not valid:
    raise SystemExit("Permission proof requires one executed test and the exact expected ownership assertions")
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
      liveWritingActionPipelineUsesLocalCLIAndRetainsFailure
      liveWritingStartupContextRespectsOwnerAfterCancellation
    )
    test_arguments "$repo_root" "$debug_dir"
    select_tests "${live_names[@]}"
    RJT_LIVE_WRITING_TARGET_CHECKS=1 TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS=1 \
      TEST_RUNNER_GITHUB_ACTIONS=true TEST_RUNNER_RUNNER_ENVIRONMENT="$RUNNER_ENVIRONMENT" \
      preflight_selected_tests "$out/selection"
    shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" > "$out/identity-before.txt"
    test_exit=0
    RJT_LIVE_WRITING_TARGET_CHECKS=1 TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS=1 \
      TEST_RUNNER_GITHUB_ACTIONS=true TEST_RUNNER_RUNNER_ENVIRONMENT="$RUNNER_ENVIRONMENT" \
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
    permission_oracle=VoiceInkTests/WritingActionEngineTests.swift
    test -f "$repo_root/$oracle"
    test ! -e "$baseline/$oracle"
    cp "$repo_root/$oracle" "$baseline/$oracle"
    cmp "$repo_root/$oracle" "$baseline/$oracle"
    test -f "$repo_root/$permission_oracle"
    test ! -e "$baseline/$permission_oracle"
    cp "$repo_root/$permission_oracle" "$baseline/$permission_oracle"
    cmp "$repo_root/$permission_oracle" "$baseline/$permission_oracle"
    python3 - "$baseline" "$out" <<'PY'
import difflib
import hashlib
import json
import sys
from pathlib import Path

baseline, output = map(Path, sys.argv[1:])
relative = "VoiceInk/Transcription/Engine/VoiceInkEngine.swift"
file = baseline / relative
original = file.read_text()
property_anchor = "    private var qwenStartupWarmup: Task<Void, Never>?\n"
permission_anchor = "    private func requestRecordPermission(\n        latencyTraceToken: VoiceInkLatencyTrace.Token?\n    ) async -> Bool {\n"
if original.count(property_anchor) != 1 or original.count(permission_anchor) != 1:
    raise SystemExit("Known-bad permission boundary did not match the instrumentation contract")
properties = "    var recordPermissionRequestForTesting: (() async -> Bool)?\n    var recordingStartupPreparationForTesting: (() async throws -> Void)?\n"
hook = "        if let recordPermissionRequestForTesting { return await recordPermissionRequestForTesting() }\n"
instrumented = original.replace(property_anchor, properties + property_anchor).replace(permission_anchor, permission_anchor + hook)
patch = "".join(difflib.unified_diff(original.splitlines(keepends=True), instrumented.splitlines(keepends=True), fromfile="a/" + relative, tofile="b/" + relative))
additions = [line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++")]
if additions != properties.splitlines() + hook.splitlines():
    raise SystemExit("Instrumentation changed more than the two optional hooks and existing permission boundary")
file.write_text(instrumented)
(output / "baseline-permission-instrumentation.patch").write_text(patch)
digest = lambda value: hashlib.sha256(value.encode()).hexdigest()
(output / "baseline-permission-instrumentation.json").write_text(json.dumps({"path": relative, "original_sha256": digest(original), "instrumented_sha256": digest(instrumented), "patch_sha256": digest(patch), "added_lines": additions, "scope": "optional hook at existing permission callback; no startup-preparation await or ownership fix"}, indent=2) + "\n")
PY
    phase=canonical-package-contract
    bash "$repo_root/scripts/run-writing-feature-regression.sh" packages "$out/packages" "$baseline"
    cmp "$repo_root/$resolved" "$baseline/$resolved"
    {
      printf 'candidate=%s\nbaseline=%s\n' "$candidate_sha" "$baseline_ref"
      xcodebuild -version
      sw_vers
      uname -m
      shasum -a 256 "$repo_root/$oracle" "$baseline/$oracle" "$repo_root/$resolved" "$baseline/$resolved"
      shasum -a 256 "$repo_root/$permission_oracle" "$baseline/$permission_oracle" "$out/baseline-permission-instrumentation.patch"
      shasum -a 256 "$repo_root/VoiceInk/Transcription/Engine/TranscriptionPipeline.swift" "$baseline/VoiceInk/Transcription/Engine/TranscriptionPipeline.swift"
    } > "$out/contract.txt"
    test_arguments "$baseline" "$baseline/.local-build"
    select_tests "${test_names[@]}"
    build_selectors=("${selectors[@]}" '-only-testing:VoiceInkTests/WritingActionEngineTests/permissionWaitReservesOneRecordingStart()')
    phase=baseline-build
    if ! xcodebuild build-for-testing "${arguments[@]}" "${build_selectors[@]}" > "$out/baseline-build.log" 2>&1; then
      tail -n 120 "$out/baseline-build.log" >&2
      exit 1
    fi
    verify_lock "$baseline"
    phase=baseline-tests
    preflight_selected_tests "$out/baseline-selection"
    baseline_exit=0
    xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" \
      -resultBundlePath "$out/Baseline.xcresult" > "$out/baseline-tests.log" 2>&1 || baseline_exit=$?
    if ! verify_observations "$out/baseline-tests.log" known-bad "$baseline_exit" "$out/baseline-result.json" "${test_names[@]}"; then
      tail -n 120 "$out/baseline-tests.log" >&2
      exit 1
    fi
    phase=baseline-permission-test
    selectors=('-only-testing:VoiceInkTests/WritingActionEngineTests/permissionWaitReservesOneRecordingStart()')
    preflight_selected_tests "$out/baseline-permission-selection"
    baseline_permission_exit=0
    xcodebuild test-without-building "${arguments[@]}" \
      '-only-testing:VoiceInkTests/WritingActionEngineTests/permissionWaitReservesOneRecordingStart()' \
      -resultBundlePath "$out/BaselinePermission.xcresult" > "$out/baseline-permission.log" 2>&1 || baseline_permission_exit=$?
    if ! verify_permission_observations "$out/baseline-permission.log" known-bad "$baseline_permission_exit" "$out/baseline-permission-result.json"; then
      tail -n 120 "$out/baseline-permission.log" >&2
      exit 1
    fi
    phase=candidate-tests
    test_arguments "$repo_root" "$debug_dir"
    select_tests "${test_names[@]}"
    preflight_selected_tests "$out/candidate-selection"
    candidate_exit=0
    xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" \
      -resultBundlePath "$out/Candidate.xcresult" > "$out/candidate-tests.log" 2>&1 || candidate_exit=$?
    if ! verify_observations "$out/candidate-tests.log" fixed "$candidate_exit" "$out/candidate-result.json" "${test_names[@]}"; then
      tail -n 120 "$out/candidate-tests.log" >&2
      exit 1
    fi
    phase=candidate-permission-test
    selectors=('-only-testing:VoiceInkTests/WritingActionEngineTests/permissionWaitReservesOneRecordingStart()')
    preflight_selected_tests "$out/candidate-permission-selection"
    candidate_permission_exit=0
    xcodebuild test-without-building "${arguments[@]}" \
      '-only-testing:VoiceInkTests/WritingActionEngineTests/permissionWaitReservesOneRecordingStart()' \
      -resultBundlePath "$out/CandidatePermission.xcresult" > "$out/candidate-permission.log" 2>&1 || candidate_permission_exit=$?
    if ! verify_permission_observations "$out/candidate-permission.log" fixed "$candidate_permission_exit" "$out/candidate-permission-result.json"; then
      tail -n 120 "$out/candidate-permission.log" >&2
      exit 1
    fi
    cmp "$repo_root/$oracle" "$baseline/$oracle"
    cmp "$repo_root/$permission_oracle" "$baseline/$permission_oracle"
    verify_lock "$baseline"
    printf '{"classification":"matched-red-green","scope":["literal-snippets","deferred-permission-callback"],"stale_startup_catch":"candidate-only coverage","candidate":"%s","baseline":"%s"}\n' \
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
    verify_lock "$repo_root"
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
      TEST_RUNNER_GITHUB_ACTIONS=true \
      xcodebuild test-without-building "${arguments[@]}" "$ui_selector" \
        -resultBundlePath "$out/UI.xcresult" > "$out/tests.log" 2>&1 || test_exit=$?
    export_exit=0
    xcrun xcresulttool export attachments --path "$out/UI.xcresult" \
      --output-path "$out/screenshots" > "$out/screenshot-export.log" 2>&1 || export_exit=$?
    python3 - "$out/screenshots" "$export_exit" "$candidate_sha" "$out/screenshot-export.json" <<'PY'
import json
import sys
from pathlib import Path

directory, exit_code, source_sha, output = sys.argv[1:]
images = [str(path.relative_to(directory)) for path in Path(directory).rglob("*") if path.suffix.lower() in {".png", ".jpg", ".jpeg"}]
available = int(exit_code) == 0 and bool(images)
Path(output).write_text(json.dumps({"source_sha": source_sha, "export_exit_code": int(exit_code), "visual_proof": "available" if available else "missing", "images": images}, indent=2) + "\n")
if not available:
    print("::warning::Writing settings screenshots were not exported; inspect screenshot-export.log and retained UI.xcresult.")
PY
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
    echo "usage: $0 live | regression <known-bad-full-sha> | ui | packages <evidence-dir> [historical-checkout] [verified-sha]" >&2
    exit 2
    ;;
esac
verify_lock "$repo_root"
