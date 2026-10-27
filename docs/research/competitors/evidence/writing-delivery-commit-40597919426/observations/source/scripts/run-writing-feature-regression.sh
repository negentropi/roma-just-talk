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
    roots = ["Package.swift", "VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS"]
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "--", *roots]).split(b"\0")
    return {value.decode(): (root / value.decode()).read_bytes() for value in tracked if value and (value == b"Package.swift" or value.endswith((b"/Package.swift", b"/project.pbxproj")))}

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
expected = [value.removesuffix("()") for value in expected]
enabled = [test["identifier"].removesuffix("()") for plan in payload.get("values", []) for test in plan.get("enabledTests", [])]
disabled = [test.get("identifier", "").removesuffix("()") for plan in payload.get("values", []) for test in plan.get("disabledTests", [])]
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

if [[ "$mode" == live || "$mode" == regression ]]; then
  test -d "$debug_dir/onboarding-test-evidence/Debug.xcresult"
  codesign --verify --deep --strict "$debug_app"
fi

run_history_ui_phase() {
  local seed_phase="$1" seed_root="$RUNNER_TEMP/writing-ui-proof/history-seed" seed_dir native_bundle native_name phase_exit=0
  seed_dir="$seed_root/$seed_phase"
  test ! -e "$seed_dir"
  mkdir -p "$seed_dir" "$out/history-seed/$seed_phase"
  native_bundle="$(python3 - "$debug_dir/Build/Products/Debug" <<'PY'
import sys
from pathlib import Path
values = sorted(Path(sys.argv[1]).rglob('VoiceInkTests.xctest'))
if len(values) != 1: raise SystemExit('Exactly one native test bundle is required for History seeding')
print(values[0])
PY
)"
  native_name="$(plutil -extract CFBundleExecutable raw -o - "$native_bundle/Contents/Info.plist")"
  codesign --verify --deep --strict "$native_bundle"
  shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" "$native_bundle/Contents/MacOS/$native_name" > "$seed_dir/identity-before.txt"
  codesign -d --verbose=4 "$debug_app" 2> "$seed_dir/app-signature-before.txt"
  codesign -d --verbose=4 "$native_bundle" 2> "$seed_dir/test-bundle-signature-before.txt"
  sudo sqlite3 -json '/Library/Application Support/com.apple.TCC/TCC.db' \
    "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceAccessibility';" > "$seed_dir/system-tcc.json"
  sqlite3 -json "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceMicrophone';" > "$seed_dir/microphone-tcc.json"
  cmp "$out/system-tcc.json" "$seed_dir/system-tcc.json"
  cmp "$out/microphone-tcc.json" "$seed_dir/microphone-tcc.json"
  if [[ "$seed_phase" == verify ]]; then
    test "$(shasum -a 256 "$seed_root/seed/expected-inputs.sha256.json" | awk '{print $1}')" = "$history_expectations_sha256"
    test "$(shasum -a 256 "$seed_root/correction-inputs.sha256.json" | awk '{print $1}')" = "$history_corrections_sha256"
  fi
  select_tests liveDictationHistoryUISeed
  if ! RJT_HISTORY_UI_SEED_CHECKS=1 TEST_RUNNER_RJT_HISTORY_UI_SEED_CHECKS=1 TEST_RUNNER_GITHUB_ACTIONS=true \
    preflight_selected_tests "$seed_dir"; then
    local receipt
    for receipt in "$seed_dir"/*.json "$seed_dir"/*.txt "$seed_dir/enumeration.log"; do
      if [[ -f "$receipt" ]]; then cp "$receipt" "$out/history-seed/$seed_phase/"; fi
    done
    return 1
  fi
  python3 - "$seed_dir" "$seed_root/seed" "$seed_phase" "$candidate_sha" "$debug_app/Contents/MacOS/roma just talk" "$repo_root" \
    xcodebuild test-without-building "${arguments[@]}" "${selectors[@]}" -resultBundlePath "$seed_dir/Native.xcresult" <<'PY' || phase_exit=$?
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

directory, seed = map(Path, sys.argv[1:3])
phase, source, executable, repo = sys.argv[3:7]
command = sys.argv[7:]
expected_support = Path.home() / 'Library/Application Support/com.negentropi.RomaJustTalk'
store_paths = [str(expected_support / name) for name in ['default.store', 'dictionary.store', 'stats.store']]
source_paths = ['VoiceInkTests/DictationHistoryUISeedLiveTests.swift', 'VoiceInk/VoiceInk.swift', 'VoiceInk/Models/Transcription.swift',
                'VoiceInk/Models/VocabularyWord.swift', 'VoiceInk/Models/WordReplacement.swift', 'VoiceInk/Models/SessionMetric.swift',
                'VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift', 'VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift',
                'VoiceInkCore/Sources/VoiceInkCore/WordReplacementLibrary.swift', 'VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift',
                'VoiceInk/Services/HistoryCorrectionApprovalService.swift', 'VoiceInk/Services/DictionaryService.swift',
                'VoiceInk/Views/History/SaveCorrectionSheet.swift', 'VoiceInk/Views/History/HistoryProcessingViews.swift',
                'VoiceInk/Views/History/InlineHistoryView.swift', 'VoiceInk/Views/History/TranscriptionDetailView.swift',
                'VoiceInk/Views/Dictionary/WordReplacementView.swift', 'VoiceInk/Views/Dictionary/EditReplacementSheet.swift',
                'VoiceInk/Views/Dictionary/WordReplacementReviewViews.swift']
source_hashes = {name: hashlib.sha256((Path(repo) / name).read_bytes()).hexdigest() for name in source_paths}
def require(value, message):
    if not value: raise RuntimeError(message)
def write(name, value):
    temporary = directory / ('.' + name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(directory / name)
def load(path):
    return json.loads(path.read_text())
def identity(pid):
    run = subprocess.run(['ps', '-p', str(pid), '-ww', '-o', 'lstart=,comm='], text=True, capture_output=True)
    if run.returncode or not run.stdout.strip(): return None
    values = run.stdout.strip().split(None, 5)
    require(len(values) == 6, 'Unable to read the native host executable and launch identity')
    return (values[5], ' '.join(values[:5]))
def open_stores():
    files = [Path(path + suffix) for path in store_paths for suffix in ['', '-wal', '-shm'] if Path(path + suffix).exists()]
    require(files, 'Normal store files were not created by app startup')
    result = subprocess.run(['lsof', '-n', '-P', '-Fpn', '--', *map(str, files)], text=True, capture_output=True)
    require(result.returncode in (0, 1), 'Normal-store lsof inspection failed')
    require(not result.stderr.strip(), 'Normal-store lsof inspection emitted an error')
    pid = None
    holders = []
    for line in result.stdout.splitlines():
        if line.startswith('p'): pid = int(line[1:])
        elif line.startswith('n'): holders.append({'pid': pid, 'path': line[1:]})
    return holders
def close_host(seen):
    current = identity(seen['hostPID'])
    if current is not None:
        require(current == (executable, seen['startedAt']), 'Refuse to terminate a reused or unrelated test-host PID')
        try: os.kill(seen['hostPID'], signal.SIGTERM)
        except ProcessLookupError: pass
        deadline = time.monotonic() + 15
        while identity(seen['hostPID']) is not None and time.monotonic() < deadline: time.sleep(0.1)
    require(identity(seen['hostPID']) is None, 'The owned native host did not exit')
    require(all(Path(path).is_file() and not Path(path).is_symlink() for path in store_paths), 'All three normal main stores must remain regular files after host exit')
    require(not open_stores(), 'Normal stores still have open descriptors after host exit')
    files = [Path(path + suffix) for path in store_paths for suffix in ['', '-wal', '-shm'] if Path(path + suffix).exists()]
    require(all(path.is_file() and not path.is_symlink() for path in files), 'Normal store hashes require regular closed files')
    write('closed-write.json', {'valid': True, 'hostPID': seen['hostPID'], 'executablePath': executable,
                              'hostExited': True, 'normalStoresHaveNoOpenDescriptors': True,
                              'checkedBeforeNextAppLaunch': True, 'files': {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}})
require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Native History seed requires the disposable hosted runner')
write('source-inputs.json', {'sourceSHA': source, 'sha256': source_hashes})
settings = {'RJT_HISTORY_UI_SEED_CHECKS': '1', 'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
            'RJT_HISTORY_UI_PHASE': phase, 'RJT_HISTORY_UI_SOURCE_SHA': source,
            'RJT_HISTORY_UI_EXPECTED_EXE': executable, 'RJT_HISTORY_UI_EVIDENCE': str(directory),
            'RJT_HISTORY_UI_SEED_EVIDENCE': str(seed), 'RUNNER_TEMP': os.environ['RUNNER_TEMP']}
corrections = directory.parent / 'corrections'
if phase == 'verify': settings['RJT_HISTORY_UI_CORRECTION_RECEIPTS'] = str(corrections)
environment = dict(os.environ, **settings, **{'TEST_RUNNER_' + key: value for key, value in settings.items()})
expected_files = ['expected-rows.json', 'expected-libraries.json', 'expected-stats.json']
if phase == 'verify':
    frozen = load(seed / 'expected-inputs.sha256.json')
    require(all(hashlib.sha256((seed / name).read_bytes()).hexdigest() == frozen[name] for name in expected_files), 'The seed expectation receipts changed during UI checks')
    correction_hashes = load(directory.parent / 'correction-inputs.sha256.json')
    require(set(correction_hashes) == {'managed.json', 'retained.json'}, 'Both actual UI correction receipts are required')
    require(all(hashlib.sha256((corrections / name).read_bytes()).hexdigest() == expected for name, expected in correction_hashes.items()), 'The actual UI correction receipts changed before native verification')
seen = None
deadline = time.monotonic() + 600
with (directory / 'tests.log').open('xb') as log:
    process = subprocess.Popen(command, cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        while process.poll() is None:
            observation_path = directory / 'observation.json'
            if seen is None and observation_path.is_file():
                observed = load(observation_path)
                pid = observed.get('hostPID')
                require(type(pid) is int and pid > 0 and pid != process.pid, 'Native seed must identify the actual hosted app PID')
                current = identity(pid)
                require(current is not None and current[0] == executable == observed.get('executablePath'), 'Native seed host executable differs from the signed app')
                require(observed.get('sourceSHA') == source and observed.get('appSupportDirectory') == str(expected_support), 'Native seed source or normal Support path differs')
                require(observed.get('storePaths') == store_paths, 'Native seed normal-store filenames differ')
                holders = open_stores()
                require(all(value['pid'] == pid for value in holders), 'Another process has a normal store open during the native seed')
                opened = {value['path'] for value in holders}
                if set(store_paths).issubset(opened):
                    seen = {'hostPID': pid, 'executablePath': executable, 'startedAt': current[1], 'openedStorePaths': store_paths, 'observedLive': True, 'openDescriptors': holders}
                    write('host-live.json', seen)
                    write('host-observed.json', {'hostPID': pid, 'executablePath': executable, 'openedStorePaths': store_paths})
            require(time.monotonic() < deadline, 'Native History seed exceeded its bounded deadline')
            time.sleep(0.05)
    except BaseException:
        try: os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try: os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            process.wait()
        if seen is not None: close_host(seen)
        raise
require(seen is not None, 'The actual normal-store app host was not observed')
close_host(seen)
text = (directory / 'tests.log').read_text(errors='replace')
name = 'liveDictationHistoryUISeed'
starts = re.findall(r'\bTest ' + name + r'\(\) started\.', text)
finishes = re.findall(r'\bTest ' + name + r'\(\) (passed|failed|skipped) after ', text)
totals = re.findall(r'Test run with (\d+) tests? in \d+ suites? (passed|failed)', text)
require(process.returncode == 0 and len(starts) == 1 and finishes == ['passed'] and totals == [('1', 'passed')], 'Native History seed requires one executed pass and zero skips')
require('recorded an issue' not in text and ': error:' not in text, 'Native History seed recorded an issue')
observed = load(directory / 'observation.json')
require(observed.get('classification') == 'passed' and observed.get('phase') == phase, 'Native History seed did not finish its real normal-store phase')
require(observed.get('explicitSaveCompleted') is (phase == 'seed') and observed.get('verificationReadOnly') is (phase == 'verify'), 'Native History seed save/read-only boundary differs')
provenance = load(directory / 'store-provenance.json')
require(provenance.get('sourceSHA') == source and provenance.get('hostPID') == seen['hostPID'], 'Native store provenance identity differs')
require(provenance.get('factorySourceSHA256') == hashlib.sha256((Path(repo) / 'VoiceInk/VoiceInk.swift').read_bytes()).hexdigest(), 'Native store factory source changed')
factory_source = (Path(repo) / 'VoiceInk/VoiceInk.swift').read_text()
factory_start = 'static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {'
factory_end = '    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {'
require(factory_source.count(factory_start) == factory_source.count(factory_end) == 1, 'Persistent factory source anchors changed')
factory = factory_source[factory_source.index(factory_start):factory_source.index(factory_end)]
require(provenance.get('factoryBodySHA256') == hashlib.sha256(factory.encode()).hexdigest(), 'Native seed factory body hash differs')
require(provenance.get('schemaSHA256') == hashlib.sha256((directory / 'schema-raw.json').read_bytes()).hexdigest(), 'Native schema receipt hash differs')
require(provenance.get('modelTypes') == ['VoiceInk.Transcription', 'VoiceInk.VocabularyWord', 'VoiceInk.WordReplacement', 'VoiceInk.SessionMetric'], 'Native seed model namespace differs from production')
configurations = provenance.get('configurations', [])
require(len(configurations) == 3 and {value.get('url') for value in configurations} == set(store_paths), 'Native History seed did not use all three normal stores')
require(all(value.get('isStoredInMemoryOnly') is False and value.get('cloudKitContainerIdentifier') is None and value.get('groupAppContainerIdentifier') is None for value in configurations), 'Native History seed used a memory, shared-group or CloudKit store')
counts = provenance.get('savedCounts', {})
stats_count = counts.get('SessionMetric')
require(type(stats_count) is int and stats_count >= 0 and counts == {'Transcription': 6 if phase == 'seed' else 5, 'VocabularyWord': 1, 'WordReplacement': 1 if phase == 'seed' else 2, 'SessionMetric': stats_count}, 'Native History phase row counts differ')
require(load(directory / 'rows.json') == load(directory / 'expected-rows.json'), 'Native History rows differ from the independently expected phase state')
require(load(directory / 'libraries.json') == load(directory / 'expected-libraries.json'), 'Native libraries differ from the independently expected phase state')
require(load(directory / 'stats.json') == load(seed / 'expected-stats.json'), 'Native stats changed during writing UI checks')
correction_verification = None
if phase == 'verify':
    require(all(hashlib.sha256((seed / name).read_bytes()).hexdigest() == frozen[name] for name in expected_files), 'Frozen seed expectations changed during native verification')
    require(load(directory.parent / 'correction-inputs.sha256.json') == correction_hashes, 'The frozen UI correction manifest changed during native verification')
    require(all(hashlib.sha256((corrections / name).read_bytes()).hexdigest() == expected for name, expected in correction_hashes.items()), 'The actual UI correction receipts changed during native verification')
    correction_verification = load(directory / 'correction-verification.json')
    require(correction_verification.get('receiptSHA256') == correction_hashes, 'Native verification used different UI correction receipts')
require(all(hashlib.sha256((Path(repo) / name).read_bytes()).hexdigest() == expected for name, expected in source_hashes.items()), 'Native History seed source bytes changed')
if phase == 'seed':
    (seed / 'expected-inputs.sha256.json').write_text(json.dumps({name: hashlib.sha256((seed / name).read_bytes()).hexdigest() for name in expected_files}, indent=2) + '\n')
write('result.json', {'valid': True, 'phase': phase, 'testName': name, 'sourceSHA': source, 'exit_code': process.returncode,
                      'hostPID': seen['hostPID'], 'closedBeforeUI': phase == 'seed', 'closedAfterUI': phase == 'verify', 'normalStorePaths': store_paths,
                      'normalFactoryReused': True, 'saveCompleted': phase == 'seed', 'verificationReadOnly': phase == 'verify',
                      'savedCounts': counts, 'statsUnchanged': phase == 'verify', 'correctionReceiptsUnchanged': phase == 'verify', 'corrections': correction_verification})
PY
  mkdir -p "$out/history-seed/$seed_phase"
  cp "$seed_dir"/*.json "$seed_dir"/*.txt "$out/history-seed/$seed_phase/"
  if [[ -f "$seed_dir/tests.log" ]]; then
    sed -n '/Test liveDictationHistoryUISeed()/p;/Test run with /p;/recorded an issue/p;/: error:/p' "$seed_dir/tests.log" > "$out/history-seed/$seed_phase/tests-excerpt.txt"
  fi
  if [[ "$phase_exit" != 0 ]]; then
    printf '{"valid":false,"phase":"%s","driver_exit_code":%s}\n' "$seed_phase" "$phase_exit" > "$out/history-seed/$seed_phase/failure.json"
    if [[ -f "$seed_dir/tests.log" ]]; then tail -n 100 "$seed_dir/tests.log" >&2; fi
    return "$phase_exit"
  fi
  shasum -a 256 "$debug_app/Contents/MacOS/roma just talk" "$native_bundle/Contents/MacOS/$native_name" > "$seed_dir/identity-after.txt"
  codesign -d --verbose=4 "$debug_app" 2> "$seed_dir/app-signature-after.txt"
  codesign -d --verbose=4 "$native_bundle" 2> "$seed_dir/test-bundle-signature-after.txt"
  cmp "$seed_dir/identity-before.txt" "$seed_dir/identity-after.txt"
  cmp "$seed_dir/app-signature-before.txt" "$seed_dir/app-signature-after.txt"
  cmp "$seed_dir/test-bundle-signature-before.txt" "$seed_dir/test-bundle-signature-after.txt"
  verify_lock "$repo_root"
  cp "$seed_dir"/*.json "$seed_dir"/*.txt "$out/history-seed/$seed_phase/"
  if [[ "$seed_phase" == seed ]]; then
    history_expectations_sha256="$(shasum -a 256 "$seed_dir/expected-inputs.sha256.json" | awk '{print $1}')"
  fi
  if [[ "$seed_phase" == verify ]]; then
    test "$(shasum -a 256 "$seed_root/seed/expected-inputs.sha256.json" | awk '{print $1}')" = "$history_expectations_sha256"
    test "$(shasum -a 256 "$seed_root/correction-inputs.sha256.json" | awk '{print $1}')" = "$history_corrections_sha256"
    cmp "$out/history-seed/seed/identity-before.txt" "$seed_dir/identity-after.txt"
    cmp "$out/history-seed/seed/app-signature-before.txt" "$seed_dir/app-signature-after.txt"
    cmp "$out/history-seed/seed/test-bundle-signature-before.txt" "$seed_dir/test-bundle-signature-after.txt"
    cmp "$out/history-seed/seed/source-inputs.json" "$seed_dir/source-inputs.json"
    python3 - "$out/history-seed" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
seed, verified = [json.loads((root / phase / 'result.json').read_text()) for phase in ['seed', 'verify']]
if not (seed['valid'] and verified['valid'] and seed['sourceSHA'] == verified['sourceSHA'] and seed['hostPID'] != verified['hostPID'] and seed['closedBeforeUI'] and verified['closedAfterUI']):
    raise SystemExit('History requires distinct native hosts with closed stores before and after the eight UI cases')
closed = json.loads((root / 'closed-after-ui.json').read_text())
frozen = json.loads((root / 'correction-inputs.sha256.json').read_text())
if closed.get('valid') is not True or closed.get('ownedAppExited') is not True or closed.get('normalStoresHaveNoOpenDescriptors') is not True or closed.get('checkedBeforeCorrectionFreeze') is not True or closed.get('normalStorePaths') != seed['normalStorePaths']:
    raise SystemExit('The UI app must close the normal stores before correction receipt freeze and native verification')
(root / 'result.json').write_text(json.dumps({'valid': True, 'testName': 'liveDictationHistoryUISeed', 'sourceSHA': seed['sourceSHA'], 'closedBeforeUI': True, 'verifiedAfterUI': True, 'uiClosedBeforeVerify': True, 'correctionsVerified': True, 'correction_receipts_sha256': frozen, 'seed': seed, 'verify': verified, 'scope': 'Synthetic normal-store History input plus approved correction and read-only native verification; no ASR or migration proof'}, indent=2) + '\n')
PY
    bash scripts/run-writing-settings-ui-regression.sh --validate-history "$out/history-seed/result.json" "$candidate_sha"
  fi
}

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
      liveDictationProfileKeepsContextEligibilityAcrossPreferenceChanges
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
    ui_selectors=()
    while IFS= read -r selector; do ui_selectors+=("$selector"); done < <(bash scripts/run-writing-settings-ui-regression.sh --candidate-selectors)
    test "${#ui_selectors[@]}" = 8
    seed_selector='-only-testing:VoiceInkTests/VoiceInkTests/liveDictationHistoryUISeed()'
    if ! xcodebuild build-for-testing "${arguments[@]}" "${ui_selectors[@]}" "$seed_selector" > "$out/build.log" 2>&1; then
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
    ui_runner="$debug_dir/Build/Products/Debug/VoiceInkUITests-Runner.app"
    ui_bundle="$ui_runner/Contents/PlugIns/VoiceInkUITests.xctest"
    codesign --verify --deep --strict "$ui_runner"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$debug_app/Contents/Info.plist")" = com.negentropi.RomaJustTalk
    ui_signatures() {
      local suffix="$1"
      codesign -d --verbose=4 "$debug_app" 2> "$out/app-signature-$suffix.txt"
      codesign -d --verbose=4 "$ui_runner" 2> "$out/runner-signature-$suffix.txt"
      codesign -d --verbose=4 "$ui_bundle" 2> "$out/test-bundle-signature-$suffix.txt"
    }
    ui_identity() {
      local bundle executable
      shasum -a 256 "$debug_app/Contents/MacOS/roma just talk"
      for bundle in "$ui_runner" "$ui_bundle"; do
        executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")"
        test -n "$executable"
        shasum -a 256 "$bundle/Contents/MacOS/$executable"
      done
    }
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
    sudo sqlite3 -json '/Library/Application Support/com.apple.TCC/TCC.db' \
      "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceAccessibility';" > "$out/system-tcc.json"
    sqlite3 -json "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
      "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceMicrophone';" > "$out/microphone-tcc.json"
    python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
requirement = (directory / "host.csreq").read_bytes().hex().upper()
for name, service in [("system-tcc.json", "kTCCServiceAccessibility"), ("microphone-tcc.json", "kTCCServiceMicrophone")]:
    rows = json.loads((directory / name).read_text())
    if rows != [{"service": service, "client": "com.negentropi.RomaJustTalk", "client_type": 0, "auth_value": 2, "csreq": requirement}]:
        raise SystemExit(f"UI permission readback does not match the signed host: {name}")
PY
    ui_identity > "$out/identity-before.txt"
    ui_signatures before
    phase=history-seed
    run_history_ui_phase seed
    history_corrections_dir="$RUNNER_TEMP/writing-ui-proof/history-seed/corrections"
    test ! -e "$history_corrections_dir"
    mkdir "$history_corrections_dir"
    export RJT_HISTORY_UI_CORRECTION_RECEIPTS="$history_corrections_dir"
    export TEST_RUNNER_RJT_HISTORY_UI_CORRECTION_RECEIPTS="$history_corrections_dir"
    export RJT_HISTORY_UI_SOURCE_SHA="$candidate_sha" TEST_RUNNER_RJT_HISTORY_UI_SOURCE_SHA="$candidate_sha"
    export TEST_RUNNER_RUNNER_TEMP="$RUNNER_TEMP"
    export RUNNER_ENVIRONMENT=github-hosted TEST_RUNNER_RUNNER_ENVIRONMENT=github-hosted
    phase=ui-selection
    selectors=("${ui_selectors[@]}")
    RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_GITHUB_ACTIONS=true \
      preflight_selected_tests "$out/selection"
    phase=ui-tests
    test_exit=0
    RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_RJT_WRITING_UI_CHECKS=1 \
      TEST_RUNNER_GITHUB_ACTIONS=true \
      xcodebuild test-without-building "${arguments[@]}" "${ui_selectors[@]}" \
        -resultBundlePath "$out/UI.xcresult" > "$out/tests.log" 2>&1 || test_exit=$?
    if ! bash scripts/run-writing-settings-ui-regression.sh --classify-candidate "$out/tests.log" "$test_exit" "$out/result.json"; then
      tail -n 120 "$out/tests.log" >&2
      return_exit="$test_exit"
      [[ "$return_exit" != 0 ]] || return_exit=1
      exit "$return_exit"
    fi
    phase=ui-correction-receipts
    python3 - "$history_corrections_dir" "$candidate_sha" "$debug_app/Contents/MacOS/roma just talk" <<'PY'
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

directory, source, executable = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
support = Path.home() / 'Library/Application Support/com.negentropi.RomaJustTalk'
stores = [support / name for name in ['default.store', 'dictionary.store', 'stats.store']]
if not all(path.is_file() and not path.is_symlink() for path in stores):
    raise SystemExit('All three normal stores must remain regular files after UI app exit')
deadline = time.monotonic() + 15
while True:
    files = [Path(str(path) + suffix) for path in stores for suffix in ['', '-wal', '-shm'] if Path(str(path) + suffix).exists()]
    result = subprocess.run(['lsof', '-n', '-P', '-Fpn', '--', *map(str, files)], text=True, capture_output=True)
    if result.returncode not in (0, 1) or result.stderr.strip():
        raise SystemExit('Normal-store inspection failed after UI app exit')
    process_list = subprocess.run(['ps', '-ax', '-ww', '-o', 'pid=,comm='], text=True, capture_output=True, check=True)
    matching = [line.strip().split(None, 1) for line in process_list.stdout.splitlines() if line.strip()]
    app_pids = [int(pid) for pid, command in matching if command == executable]
    if not result.stdout.strip() and not app_pids: break
    if time.monotonic() >= deadline:
        raise SystemExit('The owned UI app or normal-store descriptors remain after UI app teardown')
    time.sleep(0.1)
(directory.parent / 'closed-after-ui.json').write_text(json.dumps({'valid': True, 'appExecutable': executable, 'ownedAppExited': True, 'ownedAppPIDs': app_pids, 'normalStorePaths': list(map(str, stores)), 'normalStoresHaveNoOpenDescriptors': True, 'checkedBeforeCorrectionFreeze': True}, indent=2) + '\n')
names = {'managed.json', 'retained.json'}
if directory.is_symlink() or {path.name for path in directory.iterdir()} != names:
    raise SystemExit('Exactly two actual UI correction receipts are required')
hashes = {}
for name in sorted(names):
    path = directory / name
    if not path.is_file() or path.is_symlink():
        raise SystemExit('UI correction receipts must be regular files')
    raw = path.read_bytes()
    value = json.loads(raw)
    if value.get('version') != 1 or value.get('sourceSHA') != source or value.get('caseName') != path.stem:
        raise SystemExit('UI correction receipt source or case differs')
    hashes[name] = hashlib.sha256(raw).hexdigest()
(directory.parent / 'correction-inputs.sha256.json').write_text(json.dumps(hashes, indent=2, sort_keys=True) + '\n')
PY
    history_corrections_sha256="$(shasum -a 256 "$history_corrections_dir/../correction-inputs.sha256.json" | awk '{print $1}')"
    mkdir "$out/history-seed/corrections"
    cp "$history_corrections_dir"/*.json "$out/history-seed/corrections/"
    cp "$history_corrections_dir/../correction-inputs.sha256.json" "$out/history-seed/"
    cp "$history_corrections_dir/../closed-after-ui.json" "$out/history-seed/"
    phase=history-verify
    run_history_ui_phase verify
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
    ui_identity > "$out/identity-after.txt"
    ui_signatures after
    cmp "$out/identity-before.txt" "$out/identity-after.txt"
    for signed_bundle in app runner test-bundle; do
      cmp "$out/$signed_bundle-signature-before.txt" "$out/$signed_bundle-signature-after.txt"
    done
    codesign --verify --deep --strict "$debug_app"
    codesign --verify --deep --strict "$ui_runner"
    ;;
  *)
    echo "usage: $0 live | regression <known-bad-full-sha> | ui | packages <evidence-dir> [historical-checkout] [verified-sha]" >&2
    exit 2
    ;;
esac
verify_lock "$repo_root"
