#!/usr/bin/env bash
set -euo pipefail

proof() {
  python3 - "$@" <<'PY'
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

OLD = '830d45210816a36c2db70b09d1329a0ef8b7ddf6'
OLD_HASH = 'b1e0f3bdc693210177e700197d170ff4a803b3b5978109df51fc755ac371dd96'
METHOD = 'testExternalAccessibilityWaitsForOneDelayedNativeButtonAction'
MARKER = 'The single delayed native action was not acknowledged within the helper action budget.'
ORACLE = 'VoiceInkTests/OnboardingRegionViewTests.swift'
HELPER = 'Tools/OnboardingAccessibilityProbe.swift'
PRODUCT = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'iOS', ORACLE, HELPER, 'Makefile', 'LocalBuild.xcconfig', 'scripts/run-onboarding-ax-action-regression.sh', 'scripts/run-writing-feature-regression.sh', '.github/workflows/voiceink-onboarding-ax-action-check.yml']
LOCK = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
LOCK_HASH = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
digest = lambda data: hashlib.sha256(data).hexdigest()
def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def manifest(root):
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', '--', *PRODUCT]).split(b'\0')
    return {name.decode(): digest((root / name.decode()).read_bytes()) for name in names if name}
def marker_line(source):
    lines = source.splitlines()
    found = [i for i, line in enumerate(lines) if MARKER in line]
    if len(found) != 1: raise ValueError('Expected exactly one delayed-action acknowledgement assertion')
    for index in range(found[0], max(-1, found[0] - 6), -1):
        if 'XCTAssertEqual(' in lines[index]: return index + 1
    raise ValueError('The acknowledgement marker is not attached to XCTAssertEqual')
def classify(lane, text, code, source, receipts, processes, expected_executable):
    expected = 'failed' if lane == 'baseline' else 'passed'
    prefix = r"Test Case '[^'\n]*OnboardingRegionViewTests[ ./]" + METHOD + r"(?:\(\))?\]?' "
    starts = re.findall(prefix + r'started\.', text)
    results = re.findall(prefix + r'(passed|failed|skipped)', text)
    all_starts = re.findall(r"Test Case '[^'\n]+' started\.", text)
    all_results = re.findall(r"Test Case '[^'\n]+' (passed|failed|skipped)", text)
    totals = re.findall(r'Executed (\d+) tests?,([^\n]+)', text)
    failure_count = 1 if lane == 'baseline' else 0
    valid = code == (65 if lane == 'baseline' else 0) and len(starts) == len(all_starts) == 1 and results == all_results == [expected] and bool(totals)
    valid = valid and all(count == '1' and re.search(r'(?:with|and)\s+' + str(failure_count) + r'\s+failures?\b', summary) and '(0 unexpected)' in summary and not re.search(r'\b[1-9]\d*\s+(?:tests?\s+)?skipped\b', summary) for count, summary in totals)
    errors = [line for line in text.splitlines() if ': error:' in line]
    line = marker_line(source)
    if lane == 'baseline':
        valid = valid and len(errors) == 1 and bool(re.search(r'OnboardingRegionViewTests\.swift:' + str(line) + r'(?::\d+)?: error:', errors[0])) and METHOD in errors[0] and 'XCTAssertEqual failed' in errors[0] and MARKER in errors[0]
    else: valid = valid and not errors
    valid = valid and not re.search(r'Testing failed:|Failed to (?:launch|build)|TEST (?:BUILD|LAUNCH) FAILED|test runner.*(?:crash|failed)', text, re.I)
    receipt = receipts[0] if len(receipts) == 1 else {}
    report = receipt.get('helperReport', {})
    host = receipt.get('hostPID')
    process_valid = processes.get('observer_completed') is True and not processes.get('sampling_errors') and processes.get('expected_executable') == expected_executable and bool(processes.get('processes')) and all(value.get('executable') == expected_executable for value in processes.get('processes', [])) and any(value.get('pid') == host for value in processes.get('processes', []))
    boundary = len(receipts) == 1 and receipt.get('version') == 1 and receipt.get('configuredCallbackDelaySeconds') == 0.55 and receipt.get('pressCount') == 1 and isinstance(receipt.get('callbackElapsedSeconds'), (int, float)) and 0.45 <= receipt['callbackElapsedSeconds'] < 2
    boundary = boundary and receipt.get('targetIdentifier') == 'onboarding-delayed-native-action' and report.get('mode') == 'press-id' and report.get('matchValue') == receipt.get('targetIdentifier') and report.get('windowTitle') == receipt.get('windowTitle') and isinstance(host, int) and host > 0 and isinstance(report.get('helperPID'), int) and report['helperPID'] > 0 and report['helperPID'] != host and report.get('hostPID') == report.get('parentPID') == host
    boundary = boundary and report.get('trusted') is True and report.get('bundleIdentifier') == 'com.negentropi.RomaJustTalk' and report.get('fixtureWindowCount') == report.get('actionMatchCount') == report.get('matchedCount') == 1 and all(report.get(key) is True for key in ['activeBeforeAction', 'enabledBeforeAction', 'sameWindowBeforeAction']) and all(report.get(key) is False for key in ['queryIncomplete', 'traversalBounded', 'deadlineExceeded']) and 'actionSkipped' not in report
    boundary = boundary and receipt.get('helperExitCode') == (74 if lane == 'baseline' else 0) and report.get('actionError') == (-25204 if lane == 'baseline' else 0)
    if lane == 'candidate':
        budget, elapsed = report.get('actionTimeoutSeconds'), report.get('actionElapsedSeconds')
        boundary = boundary and report.get('actionTimeoutSetupError') == 0 and type(budget) in [int, float] and math.isfinite(budget) and 0 < budget <= 2 and type(elapsed) in [int, float] and math.isfinite(elapsed) and 0.45 <= elapsed <= budget + 0.01
    return {'valid': bool(valid and boundary and process_valid), 'classification': ('intended-acknowledgement-timeout' if lane == 'baseline' else 'acknowledged-single-native-action') if valid and boundary and process_valid else 'invalid-or-unrelated-failure', 'lane': lane, 'exit_code': code, 'assertion_line': line, 'starts': len(starts), 'results': results, 'totals': totals, 'errors': errors, 'boundary_valid': bool(boundary), 'process_valid': bool(process_valid), 'receipts': receipts, 'processes': processes}
def self_test():
    source = 'XCTAssertEqual(code, 0, "' + MARKER + '")\n'
    prefix = "Test Case '-[VoiceInkTests.OnboardingRegionViewTests " + METHOD + "]' "
    error = '/tmp/OnboardingRegionViewTests.swift:1: error: -[VoiceInkTests.OnboardingRegionViewTests ' + METHOD + '] : XCTAssertEqual failed: ("74") is not equal to ("0") - ' + MARKER + '\n'
    old = prefix + 'started.\n' + error + prefix + 'failed (1 second).\nExecuted 1 test, with 1 failure (0 unexpected) in 1 second\n'
    new = old.replace(error, '').replace('failed (', 'passed (').replace('1 failure', '0 failures')
    report = {'mode': 'press-id', 'matchValue': 'onboarding-delayed-native-action', 'windowTitle': 'fixture', 'hostPID': 10, 'parentPID': 10, 'helperPID': 11, 'trusted': True, 'bundleIdentifier': 'com.negentropi.RomaJustTalk', 'fixtureWindowCount': 1, 'actionMatchCount': 1, 'matchedCount': 1, 'activeBeforeAction': True, 'enabledBeforeAction': True, 'sameWindowBeforeAction': True, 'queryIncomplete': False, 'traversalBounded': False, 'deadlineExceeded': False, 'actionError': -25204}
    receipt = {'version': 1, 'configuredCallbackDelaySeconds': 0.55, 'pressCount': 1, 'callbackElapsedSeconds': 0.55, 'helperExitCode': 74, 'helperReport': report, 'hostPID': 10, 'windowTitle': 'fixture', 'targetIdentifier': 'onboarding-delayed-native-action'}
    process = {'expected_executable': '/tmp/app', 'processes': [{'pid': 10, 'executable': '/tmp/app'}], 'observer_completed': True, 'sampling_errors': []}
    candidate = json.loads(json.dumps(receipt)); candidate['helperExitCode'] = 0
    candidate['helperReport'].update({'actionError': 0, 'actionTimeoutSetupError': 0, 'actionTimeoutSeconds': 2, 'actionElapsedSeconds': 0.55})
    fixtures = {'baseline-red': ('baseline', old, 65, [receipt], process, True), 'candidate-green': ('candidate', new, 0, [candidate], process, True), 'baseline-green': ('baseline', new, 0, [candidate], process, False), 'candidate-red': ('candidate', old, 65, [receipt], process, False), 'unrelated': ('baseline', old.replace(MARKER, 'other'), 65, [receipt], process, False), 'mixed': ('baseline', old + '/tmp/Other.swift:1: error: other\n', 65, [receipt], process, False), 'skip': ('baseline', old.replace('failed (', 'skipped ('), 65, [receipt], process, False), 'wrong-line': ('baseline', old.replace('.swift:1:', '.swift:2:'), 65, [receipt], process, False), 'wrong-method': ('baseline', old.replace(METHOD, 'other'), 65, [receipt], process, False), 'missing-receipt': ('baseline', old, 65, [], process, False), 'duplicate-receipt': ('baseline', old, 65, [receipt, receipt], process, False), 'wrong-counter': ('baseline', old, 65, [{**receipt, 'pressCount': 2}], process, False), 'wrong-delay': ('baseline', old, 65, [{**receipt, 'configuredCallbackDelaySeconds': 0.1}], process, False), 'launch': ('baseline', old + 'Failed to launch application\n', 65, [receipt], process, False), 'foreign-host': ('baseline', old, 65, [receipt], {**process, 'processes': [{'pid': 10, 'executable': '/tmp/foreign'}]}, False), 'incomplete-observer': ('baseline', old, 65, [receipt], {**process, 'observer_completed': False}, False)}
    fixtures['poisoned-expected-path'] = ('baseline', old, 65, [receipt], {**process, 'expected_executable': '/tmp/foreign', 'processes': [{'pid': 10, 'executable': '/tmp/foreign'}]}, False)
    for name, field, value in [('missing-action-budget', 'actionTimeoutSeconds', None), ('action-budget-setup-failed', 'actionTimeoutSetupError', -25202), ('action-ack-too-short', 'actionElapsedSeconds', 0.1), ('action-ack-over-budget', 'actionElapsedSeconds', 2.02), ('nonfinite-action-budget', 'actionTimeoutSeconds', float('inf')), ('nonfinite-action-elapsed', 'actionElapsedSeconds', float('nan')), ('action-budget-too-large', 'actionTimeoutSeconds', 2.1)]:
        changed = json.loads(json.dumps(candidate))
        if value is None: changed['helperReport'].pop(field)
        else: changed['helperReport'][field] = value
        fixtures[name] = ('candidate', new, 0, [changed], process, False)
    observed = {name: classify(lane, log, code, source, receipts, processes, '/tmp/app')['valid'] for name, (lane, log, code, receipts, processes, expected) in fixtures.items()}
    assert all(observed[name] == fixture[-1] for name, fixture in fixtures.items()), observed
    print(json.dumps({'valid': True, 'fixtures': observed}, indent=2))

command, *args = sys.argv[1:]
if command == 'self-test': self_test()
elif command == 'sources':
    root, output = map(Path, args)
    if digest((root / LOCK).read_bytes()) != LOCK_HASH: raise SystemExit('Package lock is not canonical')
    if digest((output / 'baseline.swift').read_bytes()) != OLD_HASH: raise SystemExit('Old helper blob differs from the pinned known-bad source')
    if (output / 'candidate.swift').read_bytes() != (root / HELPER).read_bytes(): raise SystemExit('Candidate helper differs from checkout')
    if digest((root / HELPER).read_bytes()) == OLD_HASH: raise SystemExit('Candidate helper is unchanged from known bad')
    source = manifest(root)
    write(output / 'source-before.json', source)
    write(output / 'contract.json', {'source_sha': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(), 'old_helper_commit': OLD, 'old_helper_sha256': OLD_HASH, 'candidate_helper_sha256': source[HELPER], 'oracle_sha256': source[ORACLE], 'assertion_line': marker_line((root / ORACLE).read_text()), 'method': METHOD, 'canonical_lock_sha256': LOCK_HASH, 'expected_app_executable': str(root / '.local-build/Build/Products/Debug/roma just talk.app/Contents/MacOS/roma just talk'), 'scope': 'One candidate app and test bundle; only external AX helper executable differs'})
elif command == 'verify-sources':
    root, output = map(Path, args)
    current = manifest(root); write(output / 'source-after.json', current)
    if current != json.loads((output / 'source-before.json').read_text()): raise SystemExit('Sources changed during matched helper comparison')
    if digest((output / 'baseline.swift').read_bytes()) != OLD_HASH or digest((output / 'candidate.swift').read_bytes()) != current[HELPER]: raise SystemExit('Compiled helper source snapshots changed')
elif command == 'selection':
    source, output = map(Path, args)
    value = json.loads(source.read_text())
    expected = 'VoiceInkTests/OnboardingRegionViewTests/' + METHOD
    enabled = [test['identifier'] for plan in value.get('values', []) for test in plan.get('enabledTests', [])]
    disabled = [test.get('identifier') for plan in value.get('values', []) for test in plan.get('disabledTests', [])]
    valid = not value.get('errors') and [name.removesuffix('()') for name in enabled] == [expected] and expected not in [name.removesuffix('()') for name in disabled]
    write(output, {'valid': valid, 'enabled': enabled, 'disabled': disabled, 'expected': expected})
    if not valid: raise SystemExit('Exact delayed-action test did not resolve')
elif command == 'idle':
    import os
    import time
    probe, app, *receipt_paths = args
    pids = []
    if receipt_paths and Path(receipt_paths[0]).is_file():
        receipts = json.loads(Path(receipt_paths[0]).read_text()).get('receipts', [])
        if len(receipts) == 1:
            pids = [receipts[0].get('hostPID'), receipts[0].get('helperReport', {}).get('helperPID')]
            if any(not isinstance(pid, int) or pid <= 0 for pid in pids): raise SystemExit('The owned process receipt contains invalid PIDs')
    deadline = time.monotonic() + 5
    while True:
        processes = subprocess.check_output(['ps', '-ww', '-axo', 'pid=,comm='], text=True)
        busy = [line for line in processes.splitlines() if line.strip().split(None, 1)[-1] in [probe, app]]
        for pid in pids:
            try: os.kill(pid, 0)
            except ProcessLookupError: continue
            busy.append('reported PID ' + str(pid) + ' still exists')
        if not busy: break
        if time.monotonic() >= deadline: raise SystemExit('Refusing helper replacement while a previous owned app or helper still runs: ' + repr(busy))
        time.sleep(0.1)
elif command == 'tcc':
    folder = Path(args[0]); requirement = (folder / 'host.csreq').read_bytes().hex().upper()
    for filename, service in [('system-tcc.json', 'kTCCServiceAccessibility'), ('microphone-tcc.json', 'kTCCServiceMicrophone')]:
        if json.loads((folder / filename).read_text()) != [{'service': service, 'client': 'com.negentropi.RomaJustTalk', 'client_type': 0, 'auth_value': 2, 'csreq': requirement}]: raise SystemExit('Fresh TCC database row does not match signed host: ' + filename)
    write(folder / 'tcc-verification.json', {'valid': True, 'scope': 'Exact signed host TCC database row readback; actual helper trust is asserted separately'})
elif command == 'classify':
    lane, folder, oracle = args; folder = Path(folder)
    receipts = []
    for file in (folder / 'attachments').rglob('*'):
        if not file.is_file() or file.stat().st_size > 1000000: continue
        try: value = json.loads(file.read_text())
        except (UnicodeError, json.JSONDecodeError): continue
        if isinstance(value, dict) and value.get('version') == 1 and 'configuredCallbackDelaySeconds' in value and 'helperReport' in value: receipts.append(value)
    expected_executable = json.loads((folder.parent / 'contract.json').read_text())['expected_app_executable']
    result = classify(lane, (folder / 'tests.log').read_text(errors='replace'), int((folder / 'exit-code.txt').read_text()), Path(oracle).read_text(), receipts, json.loads((folder / 'application-processes.json').read_text()), expected_executable)
    write(folder / 'result.json', result)
    if not result['valid']: raise SystemExit(lane + ' did not satisfy the matched acknowledgement contract')
elif command == 'combine':
    folder = Path(args[0]); results = {lane: json.loads((folder / lane / 'result.json').read_text()) for lane in ['baseline', 'candidate']}
    valid = all(value.get('valid') is True for value in results.values())
    contract = json.loads((folder / 'contract.json').read_text())
    write(folder / 'result.json', {'classification': 'matched-red-green' if valid else 'invalid-or-failed', 'contract': contract, 'lanes': results})
    if not valid: raise SystemExit('Old helper must fail precisely and candidate must acknowledge exactly one native action')
else: raise SystemExit('Unknown proof operation')
PY
}

if [[ "${1:-}" == --self-test ]]; then proof self-test; exit 0; fi
if [[ -n "${1:-}" || "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo "Run only on a disposable GitHub-hosted Mac, or use --self-test." >&2; exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then echo "The runner must own the logged-in desktop." >&2; exit 2; fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
out="$RUNNER_TEMP/onboarding-ax-action-regression"
probe=/tmp/roma-onboarding-diagnostic/ExternalAXProbe
old_sha=830d45210816a36c2db70b09d1329a0ef8b7ddf6
oracle=VoiceInkTests/OnboardingRegionViewTests.swift
selector='-only-testing:VoiceInkTests/OnboardingRegionViewTests/testExternalAccessibilityWaitsForOneDelayedNativeButtonAction'
derived="$repo/.local-build"
app="$derived/Build/Products/Debug/roma just talk.app"
bundle="$app/Contents/PlugIns/VoiceInkTests.xctest"
test ! -e "$out"
test ! -e "$probe"
mkdir -p "$out" "$(dirname "$probe")"
phase=sources
stop_observer() {
  touch "$observer_folder/process-stop"
  wait "$observer_pid"
  observer_pid=
}
trap 'code=$?; if [[ -n "${observer_pid:-}" ]]; then stop_observer || true; fi; if [[ "$code" != 0 ]]; then printf "{\"classification\":\"invalid-or-failed\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi; exit "$code"' EXIT
git ls-files --error-unmatch scripts/run-onboarding-ax-action-regression.sh .github/workflows/voiceink-onboarding-ax-action-check.yml > /dev/null
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
git diff --quiet HEAD -- VoiceInk VoiceInkCore VoiceInkNVIDIA VoiceInkQwen VoiceInk.xcodeproj iOS "$oracle" Tools/OnboardingAccessibilityProbe.swift scripts/run-onboarding-ax-action-regression.sh scripts/run-writing-feature-regression.sh .github/workflows/voiceink-onboarding-ax-action-check.yml Makefile LocalBuild.xcconfig
test -z "$(git ls-files --others --exclude-standard -- VoiceInk VoiceInkCore VoiceInkNVIDIA VoiceInkQwen VoiceInk.xcodeproj iOS "$oracle" Tools/OnboardingAccessibilityProbe.swift)"
git fetch --no-tags origin "$old_sha"
git show "$old_sha:Tools/OnboardingAccessibilityProbe.swift" > "$out/baseline.swift"
cp Tools/OnboardingAccessibilityProbe.swift "$out/candidate.swift"
proof sources "$repo" "$out"
{ xcodebuild -version; swift --version; sw_vers; uname -m; } > "$out/environment.txt"
for lane in baseline candidate; do
  xcrun swiftc "$out/$lane.swift" -o "$out/$lane-helper" > "$out/$lane-helper-build.log" 2>&1
  codesign --force --sign - --identifier com.negentropi.RomaJustTalk.AXProbe "$out/$lane-helper"
  codesign --verify --strict "$out/$lane-helper"
done
shasum -a 256 "$out/baseline-helper" "$out/candidate-helper" > "$out/helpers-identity.sha256"
test "$(awk 'NR == 1 {print $1}' "$out/helpers-identity.sha256")" != "$(awk 'NR == 2 {print $1}' "$out/helpers-identity.sha256")"
arguments=(
  -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug
  -destination 'platform=macOS' -parallel-testing-enabled NO
  -derivedDataPath "$derived" -xcconfig LocalBuild.xcconfig
  -clonedSourcePackagesDirPath "$derived/SourcePackages"
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
  DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$repo/VoiceInk/VoiceInk.local.entitlements"
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
)
phase=single-app-build
xcodebuild build-for-testing "${arguments[@]}" "$selector" > "$out/build.log" 2>&1
test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = com.negentropi.RomaJustTalk
test_name="$(plutil -extract CFBundleExecutable raw -o - "$bundle/Contents/Info.plist")"
host_identity() {
  shasum -a 256 "$app/Contents/MacOS/roma just talk" "$bundle/Contents/MacOS/$test_name"
}
host_identity > "$out/compiled-identity.txt"
codesign --verify --deep --strict "$app"
codesign -d --verbose=4 "$app" 2> "$out/compiled-app-signature.txt"
codesign -d --verbose=4 "$bundle" 2> "$out/compiled-test-signature.txt"

for lane in baseline candidate; do
  phase="$lane-install"
  folder="$out/$lane"
  mkdir -p "$folder"
  shasum -a 256 -c "$out/helpers-identity.sha256" > "$folder/helper-staging-before.txt"
  proof idle "$probe" "$app/Contents/MacOS/roma just talk"
  if [[ -e "$probe" ]]; then cmp "$probe" "$out/baseline-helper"; fi
  test ! -e "$probe.stage.$$"
  install -m 755 "$out/$lane-helper" "$probe.stage.$$"
  cmp "$probe.stage.$$" "$out/$lane-helper"
  mv "$probe.stage.$$" "$probe"
  cmp "$probe" "$out/$lane-helper"
  codesign --verify --strict "$probe"
  host_identity > "$folder/host-identity-before.txt"
  cmp "$out/compiled-identity.txt" "$folder/host-identity-before.txt"
  shasum -a 256 "$probe" > "$folder/helper-identity-before.txt"
  codesign -d --verbose=4 "$probe" 2> "$folder/helper-signature-before.txt"
  codesign -dr - "$app" 2>&1 | sed -n -e 's/^# designated => //p' -e 's/^designated => //p' > "$folder/host-requirement.txt"
  test -s "$folder/host-requirement.txt"
  csreq -r "$folder/host-requirement.txt" -b "$folder/host.csreq"
  requirement_hex="$(xxd -p "$folder/host.csreq" | tr -d '\n')"
  test -n "$requirement_hex"
  phase="$lane-permissions"
  for service in kTCCServiceAccessibility kTCCServiceMicrophone; do
    sql="INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('$service','com.negentropi.RomaJustTalk',0,2,4,1,X'$requirement_hex',0,'UNUSED',0);"
    if [[ "$service" == kTCCServiceAccessibility ]]; then printf '%s\n' "$sql" | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'; else printf '%s\n' "$sql" | sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db"; fi
  done
  killall tccd 2>/dev/null || true
  sudo killall tccd 2>/dev/null || true
  sleep 2
  sudo sqlite3 -json '/Library/Application Support/com.apple.TCC/TCC.db' "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceAccessibility';" > "$folder/system-tcc.json"
  sqlite3 -json "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceMicrophone';" > "$folder/microphone-tcc.json"
  proof tcc "$folder"
  if [[ "$lane" == baseline ]]; then
    xcodebuild test-without-building "${arguments[@]}" "$selector" -enumerate-tests -test-enumeration-style flat -test-enumeration-format json -test-enumeration-output-path "$out/selected-tests.json" > "$out/enumeration.log" 2>&1
    proof selection "$out/selected-tests.json" "$out/selection-receipt.json"
    proof idle "$probe" "$app/Contents/MacOS/roma just talk"
  fi
  phase="$lane-test"
  observer_folder="$folder"
  python3 - "$folder" "$app/Contents/MacOS/roma just talk" <<'PY' &
import json
import subprocess
import sys
import time
from pathlib import Path
folder, expected = Path(sys.argv[1]), sys.argv[2]
seen, errors = set(), []
started = time.monotonic()
while not (folder / 'process-stop').exists() and time.monotonic() - started < 900:
    try:
        for line in subprocess.check_output(['ps', '-ww', '-axo', 'pid=,comm='], text=True).splitlines():
            values = line.strip().split(None, 1)
            if len(values) == 2 and values[1].endswith('/roma just talk.app/Contents/MacOS/roma just talk'): seen.add((int(values[0]), values[1]))
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        errors.append(str(error)); break
    time.sleep(0.1)
(folder / 'application-processes.json').write_text(json.dumps({'expected_executable': expected, 'processes': [{'pid': pid, 'executable': executable} for pid, executable in sorted(seen)], 'observer_completed': (folder / 'process-stop').exists(), 'sampling_errors': errors}, indent=2) + '\n')
PY
  observer_pid=$!
  test_exit=0
  xcodebuild test-without-building "${arguments[@]}" "$selector" -resultBundlePath "$folder/Test.xcresult" > "$folder/tests.log" 2>&1 || test_exit=$?
  stop_observer
  printf '%s\n' "$test_exit" > "$folder/exit-code.txt"
  proof idle "$probe" "$app/Contents/MacOS/roma just talk"
  host_identity > "$folder/host-identity-after.txt"
  shasum -a 256 "$probe" > "$folder/helper-identity-after.txt"
  cmp "$folder/host-identity-before.txt" "$folder/host-identity-after.txt"
  cmp "$folder/helper-identity-before.txt" "$folder/helper-identity-after.txt"
  shasum -a 256 -c "$out/helpers-identity.sha256" > "$folder/helper-staging-after.txt"
  codesign --verify --deep --strict "$app"
  codesign --verify --strict "$probe"
  codesign -d --verbose=4 "$app" 2> "$folder/app-signature-after.txt"
  codesign -d --verbose=4 "$bundle" 2> "$folder/test-signature-after.txt"
  codesign -d --verbose=4 "$probe" 2> "$folder/helper-signature-after.txt"
  cmp "$out/compiled-app-signature.txt" "$folder/app-signature-after.txt"
  cmp "$out/compiled-test-signature.txt" "$folder/test-signature-after.txt"
  cmp "$folder/helper-signature-before.txt" "$folder/helper-signature-after.txt"
  xcrun xcresulttool export attachments --path "$folder/Test.xcresult" --output-path "$folder/attachments" > "$folder/export.log" 2>&1
  classify_exit=0
  proof classify "$lane" "$folder" "$repo/$oracle" > "$folder/classifier.log" 2>&1 || classify_exit=$?
  printf '%s\n' "$classify_exit" > "$folder/classifier-exit.txt"
  proof idle "$probe" "$app/Contents/MacOS/roma just talk" "$folder/result.json"
done
phase=source-verification
proof verify-sources "$repo" "$out"
phase=verdict
proof combine "$out"
