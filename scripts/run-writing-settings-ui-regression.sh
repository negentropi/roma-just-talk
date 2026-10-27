#!/usr/bin/env bash
set -euo pipefail

proof() {
  python3 - "$@" <<'PY'
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

BASELINE = 'bdd608cf6111e8d7e88c12678f530318713acf67'
ORACLE = 'VoiceInkUITests/WritingFeaturesUITests.swift'
METHOD = 'testDictationProfilePreservesCustomSettingsAndPersists'
MARKER = 'Opening model settings disabled the panel or blocked a visible panel control.'
PRODUCT = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'iOS']
LOCK = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
LOCK_HASH = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
CASES = ['testSnippetLibraryPreservesLiteralContentAcrossEditAndRelaunch', 'testCSVImportPreviewsMultilineContentBeforeReplacing', 'testTranslationTargetsReorderSelectAndPersist', METHOD]
digest = lambda data: hashlib.sha256(data).hexdigest()
def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def tracked(root, paths):
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', '--', *paths]).split(b'\0')
    return {name.decode(): digest((root / name.decode()).read_bytes()) for name in names if name}
def marker_line(source):
    lines = source.splitlines()
    found = [i for i, line in enumerate(lines) if MARKER in line]
    if len(found) != 1:
        raise ValueError('The current oracle must contain exactly one intended assertion marker')
    for index in range(found[0], max(-1, found[0] - 6), -1):
        if 'XCTAssertTrue(' in lines[index]:
            return index + 1
    raise ValueError('The intended marker is not attached to an XCTAssertTrue boundary')
def classify(text, exit_code, source, observations):
    line = marker_line(source)
    prefix = r"Test Case '[^'\n]*WritingFeaturesUITests[ ./]" + METHOD + r"(?:\(\))?\]?' "
    starts = re.findall(prefix + r'started\.', text)
    finishes = re.findall(prefix + r'(passed|failed|skipped)', text)
    all_starts = re.findall(r"Test Case '[^'\n]+' started\.", text)
    all_finishes = re.findall(r"Test Case '[^'\n]+' (passed|failed|skipped)", text)
    totals = re.findall(r'Executed (\d+) tests?,([^\n]+)', text)
    errors = [value for value in text.splitlines() if ': error:' in value]
    expected_error = len(errors) == 1 and bool(re.search(r'WritingFeaturesUITests\.swift:' + str(line) + r'(?::\d+)?: error:', errors[0])) and METHOD in errors[0] and 'XCTAssertTrue failed' in errors[0] and MARKER in errors[0]
    valid_totals = bool(totals) and all(count == '1' and re.search(r'(?:with|and)\s+1\s+failure\b', summary) and '(0 unexpected)' in summary and not re.search(r'\b[1-9]\d*\s+(?:tests?\s+)?skipped\b', summary) for count, summary in totals)
    before = observations.get('before-opening', [])
    after = observations.get('after-opening', [])
    observed_boundary = len(before) == len(after) == 1 and not observations.get('after-closing')
    if observed_boundary:
        before, after = before[0], after[0]
        gear = before.get('actors', {}).get('settings-open', {})
        controls = [after.get('actors', {}).get(name, {}) for name in ['custom', 'none', 'settings-close']]
        observed_boundary = before.get('version') == after.get('version') == 1 and before.get('mainWindowCount') == after.get('mainWindowCount') == 1 and before.get('nativeSheetCount') == after.get('nativeSheetCount') == 0 and gear.get('exists') is True and gear.get('enabled') is True and gear.get('hittable') is True and all(control.get('exists') is True for control in controls) and bool(after.get('boundaryFailures')) and any(control.get('enabled') is False or control.get('hittable') is False for control in controls)
    valid = observed_boundary and exit_code == 65 and len(starts) == len(all_starts) == 1 and finishes == all_finishes == ['failed'] and valid_totals and expected_error and not re.search(r'Testing failed:|Failed to (?:launch|build)|TEST (?:BUILD|LAUNCH) FAILED|test runner.*(?:crash|failed)', text, re.I)
    return {'classification': 'intended-disabled-panel-failure' if valid else 'invalid-or-unrelated-failure', 'valid': bool(valid), 'exit_code': exit_code, 'expected_assertion_line': line, 'expected_assertion_message': MARKER, 'starts': len(starts), 'results': finishes, 'xctest_totals': totals, 'errors': errors, 'observations': observations, 'observed_boundary_valid': bool(observed_boundary)}

def process_valid(payload, expected):
    values = payload.get('processes', [])
    return payload.get('observer_completed') is True and not payload.get('sampling_errors') and payload.get('expected_executable') == expected and bool(values) and all(isinstance(value.get('pid'), int) and value['pid'] > 0 and value.get('executable') == expected for value in values)

def self_test():
    source = 'func boundary() {\n XCTAssertTrue(ready,\n "' + MARKER + '")\n}\n'
    prefix = "Test Case '-[VoiceInkUITests.WritingFeaturesUITests " + METHOD + "]' "
    error = '/tmp/WritingFeaturesUITests.swift:2: error: -[VoiceInkUITests.WritingFeaturesUITests ' + METHOD + '] : XCTAssertTrue failed - ' + MARKER + '\n'
    good = prefix + 'started.\n' + error + prefix + 'failed (2.0 seconds).\nExecuted 1 test, with 1 failure (0 unexpected) in 2.0 seconds\n'
    observations = {'before-opening': [{'version': 1, 'mainWindowCount': 1, 'nativeSheetCount': 0, 'actors': {'settings-open': {'exists': True, 'enabled': True, 'hittable': True}}}], 'after-opening': [{'version': 1, 'mainWindowCount': 1, 'nativeSheetCount': 0, 'actors': {name: {'exists': True, 'enabled': True, 'hittable': False} for name in ['custom', 'none', 'settings-close']}, 'boundaryFailures': ['visible panel controls are not hittable']}] }
    cases = {
        'intended': (good, 65, True),
        'green': (good.replace(error, '').replace('failed (', 'passed (').replace('1 failure', '0 failures'), 0, False),
        'wrong-line': (good.replace('.swift:2:', '.swift:3:'), 65, False),
        'wrong-message': (good.replace(MARKER, 'Different failure.'), 65, False),
        'mixed-failure': (good + '/tmp/Other.swift:5: error: unrelated failure\n', 65, False),
        'skip': (good.replace('failed (', 'skipped ('), 65, False),
        'unexpected': (good.replace('(0 unexpected)', '(1 unexpected)'), 65, False),
        'wrong-count': (good.replace('Executed 1 test', 'Executed 2 tests'), 65, False),
        'duplicate': (good + good, 65, False),
        'launch-failure': (good + 'Failed to launch application\n', 65, False),
        'setup-failure': (good.replace(error, '/tmp/WritingFeaturesUITests.swift:10: error: setup failed\n'), 65, False),
        'wrong-exit': (good, 1, False),
    }
    observed = {name: classify(text, code, source, observations)['valid'] for name, (text, code, expected) in cases.items()}
    observed['missing-observation'] = classify(good, 65, source, {})['valid']
    visible = json.loads(json.dumps(observations))
    for control in visible['after-opening'][0]['actors'].values(): control['hittable'] = True
    observed['interactive-after-opening'] = classify(good, 65, source, visible)['valid']
    duplicate = json.loads(json.dumps(observations))
    duplicate['after-opening'] *= 2
    observed['duplicate-observation'] = classify(good, 65, source, duplicate)['valid']
    foreign_sheet = json.loads(json.dumps(observations))
    foreign_sheet['after-opening'][0]['nativeSheetCount'] = 1
    observed['foreign-sheet'] = classify(good, 65, source, foreign_sheet)['valid']
    assert all(observed[name] == expected for name, (_, _, expected) in cases.items()) and not any(observed[name] for name in ['missing-observation', 'interactive-after-opening', 'duplicate-observation', 'foreign-sheet']), observed
    executable = '/tmp/baseline/roma just talk.app/Contents/MacOS/roma just talk'
    process = {'expected_executable': executable, 'processes': [{'pid': 123, 'executable': executable}], 'observer_completed': True, 'sampling_errors': []}
    process_cases = {'expected': (process, True), 'missing': ({}, False), 'empty': ({**process, 'processes': []}, False), 'incomplete': ({**process, 'observer_completed': False}, False), 'sampling-error': ({**process, 'sampling_errors': ['ps failed']}, False), 'candidate-launched-as-baseline': ({**process, 'processes': [{'pid': 123, 'executable': executable.replace('/baseline/', '/candidate/')}]}, False), 'mixed-foreign': ({**process, 'processes': [*process['processes'], {'pid': 456, 'executable': executable.replace('/baseline/', '/candidate/')}]}, False)}
    process_observed = {name: process_valid(payload, executable) for name, (payload, expected) in process_cases.items()}
    assert all(process_observed[name] == expected for name, (_, expected) in process_cases.items()), process_observed
    print(json.dumps({'classifier_fixtures': observed, 'process_fixtures': process_observed, 'valid': True}, indent=2))

command, *args = sys.argv[1:]
if command == 'self-test':
    self_test()
elif command == 'sources':
    candidate, baseline, output = map(Path, args)
    manifests = {label: tracked(root, PRODUCT) for label, root in [('candidate', candidate), ('baseline', baseline)]}
    for label, manifest in manifests.items(): write(output / (label + '-production-before.json'), manifest)
    def declarations(root):
        names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', '--', 'Package.swift', *PRODUCT]).split(b'\0')
        return {name.decode(): digest((root / name.decode()).read_bytes()) for name in names if name and (name == b'Package.swift' or name.endswith((b'/Package.swift', b'/project.pbxproj')))}
    if declarations(candidate) != declarations(baseline): raise SystemExit('Baseline dependency declarations differ')
    build_inputs = ['Makefile', 'LocalBuild.xcconfig', 'scripts/verify-static-whisper-xcframework.sh']
    for name in build_inputs:
        if (candidate / name).read_bytes() != (baseline / name).read_bytes(): raise SystemExit('Build input differs between UI lanes: ' + name)
    if digest((candidate / LOCK).read_bytes()) != LOCK_HASH or (candidate / LOCK).read_bytes() != (baseline / LOCK).read_bytes(): raise SystemExit('Both lanes must use the unchanged canonical package lock')
    oracle = (candidate / ORACLE).read_bytes()
    if oracle != (baseline / ORACLE).read_bytes(): raise SystemExit('UI oracle differs between lanes')
    contract = {'baseline_sha': BASELINE, 'candidate_sha': subprocess.check_output(['git', '-C', str(candidate), 'rev-parse', 'HEAD'], text=True).strip(), 'driver_sha': subprocess.check_output(['git', '-C', str(candidate), 'rev-parse', 'HEAD'], text=True).strip(), 'driver_sha256': digest((candidate / 'scripts/run-writing-settings-ui-regression.sh').read_bytes()), 'oracle_sha256': digest(oracle), 'baseline_original_oracle_sha256': digest((output / 'baseline-original-oracle.swift').read_bytes()), 'canonical_lock_sha256': LOCK_HASH, 'build_inputs_sha256': {name: digest((candidate / name).read_bytes()) for name in build_inputs}, 'bundle_identifier': 'com.negentropi.RomaJustTalk', 'baseline_method': METHOD, 'intended_assertion_line': marker_line(oracle.decode()), 'intended_assertion_message': MARKER, 'changed_production_paths': sorted(name for name in manifests['candidate'].keys() | manifests['baseline'].keys() if manifests['candidate'].get(name) != manifests['baseline'].get(name))}
    write(output / 'contract.json', contract)
elif command == 'verify-sources':
    candidate, baseline, output = map(Path, args)
    contract = json.loads((output / 'contract.json').read_text())
    for label, root in [('candidate', candidate), ('baseline', baseline)]:
        manifest = tracked(root, PRODUCT)
        write(output / (label + '-production-after.json'), manifest)
        if manifest != json.loads((output / (label + '-production-before.json')).read_text()): raise SystemExit(label + ' production source changed')
        if digest((root / ORACLE).read_bytes()) != contract['oracle_sha256']: raise SystemExit(label + ' UI oracle changed')
    if digest((candidate / 'scripts/run-writing-settings-ui-regression.sh').read_bytes()) != contract['driver_sha256']: raise SystemExit('UI comparison driver changed')
    for name, expected in contract['build_inputs_sha256'].items():
        if any(digest((root / name).read_bytes()) != expected for root in [candidate, baseline]): raise SystemExit('UI build input changed: ' + name)
    write(output / 'source-verification.json', {'valid': True, 'candidate_sha': contract['candidate_sha'], 'baseline_sha': BASELINE, 'oracle_sha256': contract['oracle_sha256']})
elif command == 'selection':
    source, output = map(Path, args)
    payload = json.loads(source.read_text())
    expected = 'VoiceInkUITests/WritingFeaturesUITests/' + METHOD
    enabled = [test['identifier'] for plan in payload.get('values', []) for test in plan.get('enabledTests', [])]
    disabled = [test.get('identifier') for plan in payload.get('values', []) for test in plan.get('disabledTests', [])]
    normalize = lambda value: value.removesuffix('()')
    valid = not payload.get('errors') and [normalize(value) for value in enabled] == [expected] and expected not in [normalize(value) for value in disabled]
    write(output, {'valid': valid, 'expected': expected, 'enabled': enabled, 'disabled': disabled})
    if not valid: raise SystemExit('Baseline must enumerate exactly the one current UI case')
elif command == 'tcc':
    folder = Path(args[0])
    rows = json.loads((folder / 'system-tcc.json').read_text()) + json.loads((folder / 'microphone-tcc.json').read_text())
    expected = {'kTCCServiceAccessibility', 'kTCCServiceMicrophone'}
    requirement = (folder / 'host.csreq').read_bytes().hex().upper()
    valid = len(rows) == 2 and {row['service'] for row in rows} == expected and all(row.get('client') == 'com.negentropi.RomaJustTalk' and row.get('client_type') == 0 and row.get('auth_value') == 2 and row.get('csreq', '').upper() == requirement for row in rows)
    write(folder / 'tcc-verification.json', {'valid': valid, 'scope': 'Fresh permission database row readback only; native control interaction supplies separate accessibility evidence', 'expected_services': sorted(expected), 'host_requirement_sha256': digest((folder / 'host.csreq').read_bytes())})
    if not valid: raise SystemExit('Fresh TCC readback does not match the just-built app')
elif command == 'processes':
    folder, expected = Path(args[0]), args[1]
    source = folder / 'application-processes.json'
    payload = json.loads(source.read_text()) if source.is_file() else {}
    valid = process_valid(payload, expected)
    write(folder / 'process-verification.json', {'valid': valid, 'observation': payload})
    if not valid: raise SystemExit('Runtime processes did not identify only the expected built app')
elif command == 'identity':
    folder = Path(args[0])
    before, after = [(folder / ('identity-' + suffix + '.txt')).read_text() for suffix in ['before', 'after']]
    records = []
    for line in before.splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if match: records.append({'sha256': match[1], 'path': match[2]})
    signatures = {}
    for bundle in ['app', 'runner', 'test-bundle']:
        first = (folder / (bundle + '-signature-before.txt')).read_bytes()
        last = (folder / (bundle + '-signature-after.txt')).read_bytes()
        if first != last: raise SystemExit('Signed ' + bundle + ' changed during UI execution')
        values = dict(re.findall(r'^(Identifier|CDHash)=(.+)$', first.decode(), re.M))
        if not values.get('CDHash'): raise SystemExit('Missing CDHash for ' + bundle)
        signatures[bundle] = {'bundle_identifier': values.get('Identifier'), 'cdhash': values['CDHash'], 'signature_sha256': digest(first)}
    valid = before == after and len(records) == 3 and len({record['path'] for record in records}) == 3 and all(digest(Path(record['path']).read_bytes()) == record['sha256'] for record in records) and signatures['app']['bundle_identifier'] == 'com.negentropi.RomaJustTalk'
    write(folder / 'identity-verification.json', {'valid': valid, 'binaries': records, 'signatures': signatures})
    if not valid: raise SystemExit('UI app, runner or test-bundle identity changed or is incomplete')
elif command == 'classify':
    log, code, oracle, output = args
    observations = {}
    for file in (Path(output).parent / 'screenshots').rglob('*'):
        if not file.is_file() or file.stat().st_size > 1_000_000: continue
        try: value = json.loads(file.read_text())
        except (UnicodeError, json.JSONDecodeError): continue
        if isinstance(value, dict) and value.get('version') == 1 and value.get('phase') in ['before-opening', 'after-opening', 'after-closing'] and 'actors' in value and 'boundaryFailures' in value:
            observations.setdefault(value['phase'], []).append(value)
    result = classify(Path(log).read_text(errors='replace'), int(code), Path(oracle).read_text(), observations)
    write(output, result)
    if not result['valid']: raise SystemExit('Baseline did not fail only at the intended panel boundary')
elif command == 'combine':
    folder, candidate_result, candidate_code = args
    folder = Path(folder)
    baseline = json.loads((folder / 'baseline/result.json').read_text())
    path = Path(candidate_result)
    candidate = json.loads(path.read_text()) if path.is_file() else {'classification': 'missing-driver-result'}
    expected = {name: {'starts': 1, 'results': ['passed']} for name in CASES}
    candidate_evidence = {kind: json.loads((path.parent / (kind + '-verification.json')).read_text()) if (path.parent / (kind + '-verification.json')).is_file() else {'valid': False} for kind in ['identity', 'tcc', 'process']}
    baseline_evidence = {kind: json.loads((folder / 'baseline' / (kind + '-verification.json')).read_text()) if (folder / 'baseline' / (kind + '-verification.json')).is_file() else {'valid': False} for kind in ['identity', 'tcc', 'process']}
    visual = path.parent / 'screenshot-export.json'
    visual_available = visual.is_file() and json.loads(visual.read_text()).get('visual_proof') == 'available'
    candidate_valid = int(candidate_code) == 0 and candidate.get('classification') == 'passed' and candidate.get('exit_code') == 0 and candidate.get('tests') == expected and all(value.get('valid') is True for value in candidate_evidence.values()) and visual_available
    valid = baseline.get('valid') is True and all(value.get('valid') is True for value in baseline_evidence.values()) and candidate_valid
    contract = json.loads((folder / 'contract.json').read_text())
    result = {'classification': 'matched-red-green' if valid else 'invalid-or-failed', 'scope': 'Debug native settings UI comparison; not Release validation', 'driver_sha': contract['driver_sha'], 'baseline_sha': BASELINE, 'candidate_sha': contract['candidate_sha'], 'oracle_sha256': contract['oracle_sha256'], 'baseline': baseline, 'candidate': candidate, 'candidate_driver_exit_code': int(candidate_code), 'candidate_valid': candidate_valid, 'candidate_identity_and_tcc': candidate_evidence, 'baseline_identity_and_tcc': baseline_evidence, 'candidate_visual_available': visual_available}
    write(folder / 'result.json', result)
    if not valid: raise SystemExit('Matched UI comparison requires intended baseline red and four candidate cases green')
else:
    raise SystemExit('Unknown proof operation')
PY
}

if [[ "${1:-}" == --self-test ]]; then
  proof self-test
  exit 0
fi
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
baseline_sha=bdd608cf6111e8d7e88c12678f530318713acf67
out="$RUNNER_TEMP/writing-settings-ui-regression"
baseline="$RUNNER_TEMP/writing-settings-ui-baseline"
oracle=VoiceInkUITests/WritingFeaturesUITests.swift
resolved=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
selector='-only-testing:VoiceInkUITests/WritingFeaturesUITests/testDictationProfilePreservesCustomSettingsAndPersists'

ui_identity() {
  local app="$1" products runner test_bundle runner_name test_name
  products="$(dirname "$app")"
  runner="$products/VoiceInkUITests-Runner.app"
  test_bundle="$runner/Contents/PlugIns/VoiceInkUITests.xctest"
  runner_name="$(plutil -extract CFBundleExecutable raw -o - "$runner/Contents/Info.plist")"
  test_name="$(plutil -extract CFBundleExecutable raw -o - "$test_bundle/Contents/Info.plist")"
  shasum -a 256 "$app/Contents/MacOS/roma just talk" "$runner/Contents/MacOS/$runner_name" "$test_bundle/Contents/MacOS/$test_name"
}

ui_signatures() {
  local app="$1" lane="$2" suffix="$3" runner test_bundle
  runner="$(dirname "$app")/VoiceInkUITests-Runner.app"
  test_bundle="$runner/Contents/PlugIns/VoiceInkUITests.xctest"
  codesign -d --verbose=4 "$app" 2> "$lane/app-signature-$suffix.txt"
  codesign -d --verbose=4 "$runner" 2> "$lane/runner-signature-$suffix.txt"
  codesign -d --verbose=4 "$test_bundle" 2> "$lane/test-bundle-signature-$suffix.txt"
}

start_observer() {
  local folder="$1" executable="$2"
  observer_folder="$folder"
  mkdir -p "$folder"
  python3 - "$folder" "$executable" <<'PY' &
import json
import subprocess
import sys
import time
from pathlib import Path

folder, expected = Path(sys.argv[1]), sys.argv[2]
seen = set()
errors = []
started = time.monotonic()
while not (folder / 'process-stop').exists() and time.monotonic() - started < 3600:
    try:
        output = subprocess.check_output(['ps', '-ww', '-axo', 'pid=,comm='], text=True)
        for line in output.splitlines():
            values = line.strip().split(None, 1)
            if len(values) == 2 and values[1].endswith('/roma just talk.app/Contents/MacOS/roma just talk'):
                seen.add((int(values[0]), values[1]))
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        errors.append(str(error))
        break
    time.sleep(0.2)
(folder / 'application-processes.json').write_text(json.dumps({
    'expected_executable': expected,
    'processes': [{'pid': pid, 'executable': executable} for pid, executable in sorted(seen)],
    'observer_completed': (folder / 'process-stop').exists(),
    'sampling_errors': errors,
}, indent=2) + '\n')
PY
  observer_pid=$!
}

stop_observer() {
  local folder="$1" observer_exit=0
  touch "$folder/process-stop" || observer_exit=$?
  wait "$observer_pid" || observer_exit=$?
  observer_pid=
  observer_folder=
  return "$observer_exit"
}

if [[ "${1:-}" == --baseline ]]; then
  test "$(git -C "$baseline" rev-parse HEAD)" = "$baseline_sha"
  lane="$out/baseline"
  mkdir -p "$lane"
  phase=build
  trap 'code=$?; if [[ -n "${observer_pid:-}" ]]; then stop_observer "$observer_folder" || true; fi; if [[ "$code" != 0 ]]; then printf "{\"classification\":\"invalid-or-unrelated-failure\",\"valid\":false,\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$code" > "$lane/failure.json"; fi; exit "$code"' EXIT
  derived="$baseline/.writing-ui-regression-build"
  app="$derived/Build/Products/Debug/roma just talk.app"
  arguments=(
    -project "$baseline/VoiceInk.xcodeproj" -scheme VoiceInk -configuration Debug
    -destination 'platform=macOS' -parallel-testing-enabled NO
    -derivedDataPath "$derived" -xcconfig "$baseline/LocalBuild.xcconfig"
    -clonedSourcePackagesDirPath "$repo/.local-build/SourcePackages"
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
    DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$baseline/VoiceInk/VoiceInk.local.entitlements"
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD'
  )
  xcodebuild build-for-testing "${arguments[@]}" "$selector" > "$lane/build.log" 2>&1
  cmp "$repo/$resolved" "$baseline/$resolved"
  test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = com.negentropi.RomaJustTalk
  codesign --verify --deep --strict "$app"
  codesign --verify --deep --strict "$(dirname "$app")/VoiceInkUITests-Runner.app"
  ui_identity "$app" > "$lane/identity-before.txt"
  ui_signatures "$app" "$lane" before
  codesign -dr - "$app" 2>&1 | sed -n -e 's/^# designated => //p' -e 's/^designated => //p' > "$lane/host-requirement.txt"
  test -s "$lane/host-requirement.txt"
  csreq -r "$lane/host-requirement.txt" -b "$lane/host.csreq"
  requirement_hex="$(xxd -p "$lane/host.csreq" | tr -d '\n')"
  test -n "$requirement_hex"
  phase=permissions
  for service in kTCCServiceAccessibility kTCCServiceMicrophone; do
    sql="INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('$service','com.negentropi.RomaJustTalk',0,2,4,1,X'$requirement_hex',0,'UNUSED',0);"
    if [[ "$service" == kTCCServiceAccessibility ]]; then
      printf '%s\n' "$sql" | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'
    else
      printf '%s\n' "$sql" | sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    fi
  done
  killall tccd 2>/dev/null || true
  sudo killall tccd 2>/dev/null || true
  sleep 2
  sudo sqlite3 -json '/Library/Application Support/com.apple.TCC/TCC.db' "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceAccessibility';" > "$lane/system-tcc.json"
  sqlite3 -json "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "SELECT service,client,client_type,auth_value,hex(csreq) AS csreq FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='kTCCServiceMicrophone';" > "$lane/microphone-tcc.json"
  proof tcc "$lane"
  phase=selection
  RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_GITHUB_ACTIONS=true \
    xcodebuild test-without-building "${arguments[@]}" "$selector" -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
      -test-enumeration-output-path "$lane/selected-tests.json" > "$lane/enumeration.log" 2>&1
  proof selection "$lane/selected-tests.json" "$lane/selection-receipt.json"
  phase=tests
  test_exit=0
  start_observer "$lane" "$app/Contents/MacOS/roma just talk"
  RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_RJT_WRITING_UI_CHECKS=1 TEST_RUNNER_GITHUB_ACTIONS=true \
    xcodebuild test-without-building "${arguments[@]}" "$selector" -resultBundlePath "$lane/UI.xcresult" > "$lane/tests.log" 2>&1 || test_exit=$?
  stop_observer "$lane"
  proof processes "$lane" "$app/Contents/MacOS/roma just talk"
  printf '%s\n' "$test_exit" > "$lane/test-exit.txt"
  ui_identity "$app" > "$lane/identity-after.txt"
  ui_signatures "$app" "$lane" after
  proof identity "$lane"
  codesign --verify --deep --strict "$app"
  codesign --verify --deep --strict "$(dirname "$app")/VoiceInkUITests-Runner.app"
  phase=attachments
  xcrun xcresulttool export attachments --path "$lane/UI.xcresult" --output-path "$lane/screenshots" > "$lane/export.log" 2>&1
  phase=assertion-classification
  proof classify "$lane/tests.log" "$test_exit" "$repo/$oracle" "$lane/result.json"
  exit 0
fi
if [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--self-test]" >&2
  exit 2
fi

test ! -e "$out"
test ! -e "$baseline"
test ! -e "$repo/.local-build/onboarding-test-evidence/writing-ui"
mkdir -p "$out"
phase=source-contract
trap 'code=$?; if [[ -n "${observer_pid:-}" ]]; then stop_observer "$observer_folder" || true; fi; if [[ "$code" != 0 ]]; then printf "{\"classification\":\"invalid-or-failed\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi; exit "$code"' EXIT
git ls-files --error-unmatch scripts/run-writing-settings-ui-regression.sh > /dev/null
git diff --quiet HEAD -- VoiceInk VoiceInkCore VoiceInkNVIDIA VoiceInkQwen VoiceInk.xcodeproj iOS "$oracle" scripts/run-writing-feature-regression.sh scripts/run-writing-settings-ui-regression.sh
test -z "$(git ls-files --others --exclude-standard -- VoiceInk VoiceInkCore VoiceInkNVIDIA VoiceInkQwen VoiceInk.xcodeproj iOS "$oracle")"
candidate_sha="$(git rev-parse HEAD)"
test "$candidate_sha" != "$baseline_sha"
git fetch --no-tags origin "$baseline_sha"
git worktree add --detach "$baseline" "$baseline_sha"
cp "$baseline/$oracle" "$out/baseline-original-oracle.swift"
cp "$repo/$oracle" "$baseline/$oracle"
git -C "$baseline" diff -- "$oracle" > "$out/baseline-oracle.patch"
cmp "$repo/$oracle" "$baseline/$oracle"
proof sources "$repo" "$baseline" "$out"
{
  xcodebuild -version
  swift --version
  sw_vers
  uname -m
} > "$out/environment.txt"
phase=canonical-packages
bash "$repo/scripts/run-writing-feature-regression.sh" packages "$out/candidate-packages"
bash "$baseline/scripts/run-writing-feature-regression.sh" packages "$out/baseline-packages" '' '' "$repo/.local-build/SourcePackages"
cmp "$repo/$resolved" "$baseline/$resolved"
phase=baseline
baseline_exit=0
bash "$repo/scripts/run-writing-settings-ui-regression.sh" --baseline > "$out/baseline-driver.log" 2>&1 || baseline_exit=$?
if [[ ! -f "$out/baseline/result.json" ]]; then
  python3 - "$out/baseline/result.json" "$baseline_exit" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({'classification':'invalid-or-unrelated-failure','valid':False,'driver_exit_code':int(sys.argv[2])}, indent=2) + '\n')
PY
fi
phase=candidate
candidate_exit=0
candidate_out="$repo/.local-build/onboarding-test-evidence/writing-ui"
start_observer "$candidate_out" "$repo/.local-build/Build/Products/Debug/roma just talk.app/Contents/MacOS/roma just talk"
bash "$repo/scripts/run-writing-feature-regression.sh" ui > "$out/candidate-driver.log" 2>&1 || candidate_exit=$?
stop_observer "$candidate_out"
candidate_process_exit=0
proof processes "$candidate_out" "$repo/.local-build/Build/Products/Debug/roma just talk.app/Contents/MacOS/roma just talk" > "$out/candidate-process.log" 2>&1 || candidate_process_exit=$?
phase=candidate-identity
candidate_identity_exit=0
proof identity "$candidate_out" > "$out/candidate-identity.log" 2>&1 || candidate_identity_exit=$?
candidate_tcc_exit=0
proof tcc "$candidate_out" > "$out/candidate-tcc.log" 2>&1 || candidate_tcc_exit=$?
printf '{"identity_exit":%s,"tcc_exit":%s,"process_exit":%s}\n' "$candidate_identity_exit" "$candidate_tcc_exit" "$candidate_process_exit" > "$out/candidate-evidence-checks.json"
phase=source-verification
proof verify-sources "$repo" "$baseline" "$out"
phase=verdict
proof combine "$out" "$candidate_out/result.json" "$candidate_exit"
