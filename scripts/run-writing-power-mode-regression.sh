#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo "Run only on a disposable GitHub-hosted Mac." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The runner must own the logged-in desktop session." >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
candidate_sha="$(git rev-parse HEAD)"
baseline_sha=98df5fa57fa4b2a928c3b2e2f95b59726d391572
verified_sha=7459b97b0469832a55b38df7b82753b82e430fdb
out="$RUNNER_TEMP/writing-power-mode-proof"
baseline="$RUNNER_TEMP/writing-power-mode-baseline"
oracle=VoiceInkUITests/WritingPowerModeUITests.swift
scheme=VoiceInk.xcodeproj/xcshareddata/xcschemes/WritingPowerModeProof.xcscheme
test ! -e "$out"
test ! -e "$baseline"
mkdir -p "$out"
phase=source-contract
trap 'code=$?; if [[ "$code" != 0 ]]; then printf "{\"classification\":\"invalid-or-failed\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi' EXIT
git fetch --no-tags origin "$baseline_sha" "$verified_sha"
git worktree add --detach "$baseline" "$baseline_sha"
test -f "$repo/$oracle"
test ! -e "$baseline/$oracle"
cp "$repo/$oracle" "$baseline/$oracle"
cmp "$repo/$oracle" "$baseline/$oracle"
resolved=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
phase=canonical-package-contract
bash "$repo/scripts/run-writing-feature-regression.sh" packages "$out/packages" "$baseline" "$verified_sha" \
  "$RUNNER_TEMP/writing-power-mode-packages"
cmp "$repo/$resolved" "$baseline/$resolved"
cmp "$repo/VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInkUpdaterE2E.xcscheme" \
  "$baseline/VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInkUpdaterE2E.xcscheme"

python3 - "$repo" "$baseline" "$out" "$baseline_sha" "$candidate_sha" "$verified_sha" <<'PY'
import hashlib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

candidate, baseline, output = map(Path, sys.argv[1:4])
baseline_sha, candidate_sha, verified_sha = sys.argv[4:]
digest = lambda data: hashlib.sha256(data).hexdigest()
manifests = {}
for label, root in [("baseline", baseline), ("candidate", candidate)]:
    paths = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "--", "VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS"]).split(b"\0")
    manifests[label] = {path.decode(): digest((root / path.decode()).read_bytes()) for path in paths if path}
    (output / f"{label}-production.json").write_text(json.dumps(manifests[label], indent=2, sort_keys=True) + "\n")
    source = root / "VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInkUpdaterE2E.xcscheme"
    document = ET.parse(source)
    action = document.getroot().find("TestAction")
    action.set("buildConfiguration", "Debug")
    variables = action.find("EnvironmentVariables")
    if variables is not None:
        action.remove(variables)
    references = action.findall("Testables/TestableReference/BuildableReference")
    if len(references) != 1 or references[0].get("BlueprintName") != "VoiceInkUITests":
        raise SystemExit("UI-only scheme does not identify exactly one UI test target")
    destination = source.with_name("WritingPowerModeProof.xcscheme")
    if destination.exists():
        raise SystemExit("Temporary scheme already exists")
    document.write(destination, encoding="utf-8", xml_declaration=True)

oracle = candidate / "VoiceInkUITests/WritingPowerModeUITests.swift"
contract = {"candidate_sha": candidate_sha, "baseline_sha": baseline_sha, "verified_production_sha": verified_sha, "candidate_production_matches_verified_except_reviewed_lock": True, "canonical_graph_receipt": "packages/canonical-graph-contract.json", "oracle_sha256": digest(oracle.read_bytes()), "scheme_sha256": digest((candidate / "VoiceInk.xcodeproj/xcshareddata/xcschemes/WritingPowerModeProof.xcscheme").read_bytes())}
changed = sorted(path for path in set(manifests["baseline"]) | set(manifests["candidate"]) if manifests["baseline"].get(path) != manifests["candidate"].get(path))
contract["changed_production_paths"] = changed
(output / "contract.json").write_text(json.dumps(contract, indent=2) + "\n")
PY
cmp "$repo/$scheme" "$baseline/$scheme"
{
  xcodebuild -version
  swift --version
  sw_vers
  uname -m
  shasum -a 256 "$repo/$oracle" "$baseline/$oracle" "$repo/$resolved" "$baseline/$resolved"
} > "$out/environment.txt"

names=(testSnippetEditsPreservePowerModeRestoration testTargetChangesPreservePowerModeRestoration)
for lane in baseline candidate; do
  checkout="$repo"
  [[ "$lane" != baseline ]] || checkout="$baseline"
  lane_out="$out/$lane"
  derived="$checkout/.power-mode-proof-build"
  app="$derived/Build/Products/Debug/roma just talk.app"
  mkdir -p "$lane_out"
  arguments=(
    -project "$checkout/VoiceInk.xcodeproj" -scheme WritingPowerModeProof -configuration Debug
    -destination 'platform=macOS' -parallel-testing-enabled NO
    -derivedDataPath "$derived" -xcconfig "$checkout/LocalBuild.xcconfig"
    -clonedSourcePackagesDirPath "$RUNNER_TEMP/writing-power-mode-packages"
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
    DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$checkout/VoiceInk/VoiceInk.local.entitlements"
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
  )
  phase="$lane-build"
  cmp "$out/packages/canonical.Package.resolved" "$checkout/$resolved"
  if ! xcodebuild build-for-testing "${arguments[@]}" \
    '-only-testing:VoiceInkUITests/WritingPowerModeUITests' > "$lane_out/build.log" 2>&1; then
    cmp "$out/packages/canonical.Package.resolved" "$checkout/$resolved"
    printf '{"classification":"invalid","boundary":"build"}\n' > "$lane_out/result.json"
    tail -n 100 "$lane_out/build.log" >&2
    continue
  fi
  cmp "$out/packages/canonical.Package.resolved" "$checkout/$resolved"
  phase="$lane-permissions"
  test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = com.negentropi.RomaJustTalk
  codesign --verify --deep --strict "$app"
  codesign -dr - "$app" 2>&1 | sed -n \
    -e 's/^# designated => //p' -e 's/^designated => //p' > "$lane_out/host-requirement.txt"
  test -s "$lane_out/host-requirement.txt"
  csreq -r "$lane_out/host-requirement.txt" -b "$lane_out/host.csreq"
  requirement_hex="$(xxd -p "$lane_out/host.csreq" | tr -d '\n')"
  grant_sql() {
    printf '%s\n' "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('$1','com.negentropi.RomaJustTalk',0,2,4,1,X'$requirement_hex',0,'UNUSED',0);"
  }
  grant_sql kTCCServiceAccessibility | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'
  grant_sql kTCCServiceListenEvent | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'
  grant_sql kTCCServiceMicrophone | sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  sudo sqlite3 -json '/Library/Application Support/com.apple.TCC/TCC.db' \
    "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='com.negentropi.RomaJustTalk' AND service IN ('kTCCServiceAccessibility','kTCCServiceListenEvent');" > "$lane_out/system-tcc.json"
  sqlite3 -json "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceMicrophone';" > "$lane_out/microphone-tcc.json"
  python3 - "$lane_out" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows = json.loads((root / "system-tcc.json").read_text()) + json.loads((root / "microphone-tcc.json").read_text())
expected = {"kTCCServiceAccessibility", "kTCCServiceListenEvent", "kTCCServiceMicrophone"}
requirement = (root / "host.csreq").read_bytes().hex().upper()
if {row["service"] for row in rows} != expected or len(rows) != 3 or any(row["auth_value"] != 2 or row["requirement"] != requirement for row in rows):
    raise SystemExit("Fresh TCC rows do not authorize the exact just-built application")
PY
  killall tccd 2>/dev/null || true
  sudo killall tccd 2>/dev/null || true
  sleep 2
  for name in "${names[@]}"; do
    case_out="$lane_out/$name"
    mkdir -p "$case_out"
    phase="$lane-$name"
    shasum -a 256 "$app/Contents/MacOS/roma just talk" > "$case_out/identity-before.txt"
    python3 - "$case_out" "$app/Contents/MacOS/roma just talk" <<'PY' &
import json
import subprocess
import sys
import time
from pathlib import Path

root, expected = Path(sys.argv[1]), sys.argv[2]
seen = set()
started = time.monotonic()
while not (root / "process-stop").exists() and time.monotonic() - started < 900:
    output = subprocess.check_output(["ps", "-ww", "-axo", "pid=,comm="], text=True)
    for line in output.splitlines():
        values = line.strip().split(None, 1)
        if len(values) == 2 and values[1].endswith("/roma just talk.app/Contents/MacOS/roma just talk"):
            seen.add((int(values[0]), values[1]))
    time.sleep(0.2)
(root / "application-processes.json").write_text(json.dumps({"expected_executable": expected, "processes": [{"pid": pid, "executable": path} for pid, path in sorted(seen)], "observer_completed": (root / "process-stop").exists()}, indent=2) + "\n")
PY
    observer_pid=$!
    test_exit=0
    RJT_WRITING_POWER_MODE_UI_CHECKS=1 TEST_RUNNER_RJT_WRITING_POWER_MODE_UI_CHECKS=1 \
      TEST_RUNNER_GITHUB_ACTIONS=true \
      xcodebuild test-without-building "${arguments[@]}" "-only-testing:VoiceInkUITests/WritingPowerModeUITests/$name" \
        -resultBundlePath "$case_out/UI.xcresult" > "$case_out/tests.log" 2>&1 || test_exit=$?
    touch "$case_out/process-stop"
    wait "$observer_pid"
    cmp "$out/packages/canonical.Package.resolved" "$checkout/$resolved"
    printf '%s\n' "$test_exit" > "$case_out/test-exit.txt"
    shasum -a 256 "$app/Contents/MacOS/roma just talk" > "$case_out/identity-after.txt"
    cmp "$case_out/identity-before.txt" "$case_out/identity-after.txt"
    codesign --verify --deep --strict "$app"
    export_exit=0
    xcrun xcresulttool export attachments --path "$case_out/UI.xcresult" \
      --output-path "$case_out/attachments" > "$case_out/export.log" 2>&1 || export_exit=$?
    printf '%s\n' "$export_exit" > "$case_out/export-exit.txt"
  done
done

phase=verdict
cmp "$repo/$oracle" "$baseline/$oracle"
cmp "$out/packages/canonical.Package.resolved" "$repo/$resolved"
cmp "$out/packages/canonical.Package.resolved" "$baseline/$resolved"
python3 - "$out" "$repo/$oracle" <<'PY'
import json
import re
import sys
from pathlib import Path

root, oracle = map(Path, sys.argv[1:])
lines = oracle.read_text().splitlines()
snapshot_line = next(i + 1 for i, value in enumerate(lines) if "XCTAssertEqual(session.originalState.lowercaseTranscription, false" in value)
cancel_message = next(i for i, value in enumerate(lines) if "Cancel restored active-mode lowercase instead of the original false value." in value)
restoration_line = next(i + 1 for i in range(cancel_message, -1, -1) if "XCTAssertTrue(waitUntil" in lines[i])
restored_equal = next(i + 1 for i in range(cancel_message + 1, len(lines)) if "XCTAssertEqual(fixture.lowercase(), false)" in lines[i])
allowed_failures = {snapshot_line, restoration_line, restored_equal}
cases = {
    "testSnippetEditsPreservePowerModeRestoration": ["after snippet save", "after snippet toggle"],
    "testTargetChangesPreservePowerModeRestoration": ["after target add", "after target reorder"],
}
results = {}
for lane in ["baseline", "candidate"]:
    results[lane] = {}
    for name, phases in cases.items():
        folder = root / lane / name
        errors = []
        text = (folder / "tests.log").read_text(errors="replace") if (folder / "tests.log").is_file() else ""
        prefix = r"Test Case '[^'\n]*WritingPowerModeUITests[ ./]" + name + r"(?:\(\))?\]?' "
        starts = re.findall(prefix + r"started\.", text)
        finishes = re.findall(prefix + r"(passed|failed|skipped)", text)
        all_starts = re.findall(r"Test Case '[^'\n]+' started\.", text)
        all_finishes = re.findall(r"Test Case '[^'\n]+' (passed|failed|skipped)", text)
        totals = re.findall(r"Executed (\d+) tests?,([^\n]+)", text)
        expected = "failed" if lane == "baseline" else "passed"
        exit_code = int((folder / "test-exit.txt").read_text()) if (folder / "test-exit.txt").is_file() else None
        if len(starts) != 1 or finishes != [expected] or exit_code != (65 if lane == "baseline" else 0):
            errors.append("Expected exactly one executed test and its required exit/result")
        if len(all_starts) != 1 or all_finishes != [expected] or not totals:
            errors.append("Unexpected, skipped, or missing XCTest cases were reported")
        for count, summary in totals:
            failures = re.search(r"(?:with|and)\s+(\d+)\s+failures?", summary)
            if count != "1" or not failures or (int(failures[1]) == 0) != (lane == "candidate") or re.search(r"\b[1-9]\d*\s+(?:tests?\s+)?skipped\b", summary):
                errors.append("XCTest totals must contain exactly one test, zero skips, and the expected failure status")
        failures = [int(value) for value in re.findall(r"WritingPowerModeUITests\.swift:(\d+)(?::\d+)?: error:", text)]
        if lane == "baseline" and (not {snapshot_line, restoration_line}.issubset(failures) or set(failures) - allowed_failures):
            errors.append("Baseline failure did not exclusively identify the snapshot/restoration defect")
        if lane == "candidate" and failures:
            errors.append("Candidate recorded assertion failures")
        process_file = folder / "application-processes.json"
        processes = json.loads(process_file.read_text()) if process_file.is_file() else {}
        if not processes.get("observer_completed") or not processes.get("processes") or any(value.get("executable") != processes.get("expected_executable") for value in processes.get("processes", [])):
            errors.append("Runtime process observation did not identify only the exact built application")
        observations = {}
        for path in (folder / "attachments").rglob("*"):
            if not path.is_file() or path.stat().st_size > 1_000_000:
                continue
            try:
                value = json.loads(path.read_text())
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if isinstance(value, dict) and {"phase", "session", "currentLowercase", "expectedConfigurationID"}.issubset(value):
                observations.setdefault(value["phase"], []).append(value)
        required = ["before writing feature mutation", *phases, "after recording cancellation"]
        if any(len(observations.get(phase, [])) != 1 for phase in required):
            errors.append("Actual before/mutation/after state attachments are missing or duplicated")
        else:
            before = observations[required[0]][0]
            original_session = before.get("session") or {}
            session_id = original_session.get("id")
            config_id = before["expectedConfigurationID"]
            def active(value, expected_original):
                session = value.get("session") or {}
                return value.get("currentLowercase") is True and value.get("activeConfigurationID") == config_id and session.get("id") == session_id and session.get("originalState", {}).get("lowercaseTranscription") is expected_original
            if not session_id or not active(before, False):
                errors.append("Power Mode precondition was not reached before UI mutation")
            if any(not active(observations[phase][0], lane == "baseline") for phase in phases):
                errors.append("Actual post-mutation session did not match the expected product behavior")
            after = observations[required[-1]][0]
            if after.get("session") is not None or after.get("activeConfigurationID") is not None or after.get("currentLowercase") is not (lane == "baseline"):
                errors.append("Actual recording cancellation/restoration state was not reached")
        result = {"expected": expected, "exit_code": exit_code, "observed_results": finishes, "xctest_totals": totals, "assertion_lines": failures, "application_processes": processes, "observations": observations, "errors": errors, "valid": not errors}
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        results[lane][name] = result
valid = all(case["valid"] for lane in results.values() for case in lane.values())
(root / "result.json").write_text(json.dumps({"classification": "matched-red-green" if valid else "invalid-or-failed", "tests": results}, indent=2) + "\n")
if not valid:
    raise SystemExit("Power Mode UI regression did not satisfy the matched observation contract")
PY
