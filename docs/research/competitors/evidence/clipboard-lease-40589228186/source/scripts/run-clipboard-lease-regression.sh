#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run clipboard regression only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The regression must own the logged-in disposable desktop." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/clipboard-lease-proof" "${1:-}" "${RJT_CLIPBOARD_LEASE_LANE:-baseline}" <<'PY'
import base64
import collections
import hashlib
import json
import math
import os
import plistlib
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode, lane = sys.argv[3:5]
paster_path = 'VoiceInk/Paste/CursorPaster.swift'
oracle_path = 'VoiceInkTests/ClipboardRestorationLeaseTests.swift'
driver_path = 'scripts/run-clipboard-lease-regression.sh'
workflow_path = '.github/workflows/voiceink-clipboard-lease-check.yml'
lock_path = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
lock_sha = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
baseline_paster_sha = 'c704ce58da8110738596c84ac580ba552ab53e5169571f4f8bd6893249494ba0'
bundle_id = 'com.negentropi.RomaJustTalk'
scope = 'clipboard restoration only; controlled menu/document access'
cases = [
    'nestedWritingPastesRestoreOriginalAllFormatClipboard',
    'writingThenOrdinaryPasteRestoresOriginalAllFormatClipboard',
    'preparedOrdinaryPasteDoesNotRestoreRetiredWritingPayload',
    'singleWritingPasteHonorsDefaultRestorationDeadline',
    'newerClipboardCopySurvivesWritingRestorationDeadline',
]
derived = repo / '.local-build'
package_checkouts = derived / 'SourcePackages'
app = derived / 'Build/Products/Debug/roma just talk.app'
executable = app / 'Contents/MacOS/roma just talk'
roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'iOS',
    'VoiceInkTests', driver_path, workflow_path, 'Makefile', 'LocalBuild.xcconfig',
    'scripts/run-writing-feature-regression.sh', 'scripts/verify-static-whisper-xcframework.sh',
    'scripts/verify-static-whisper-app.sh', 'scripts/verify-adhoc-library-validation.sh']


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    data = json.dumps(value, indent=2, sort_keys=True) + '\n'
    if path.exists():
        require(path.read_text() == data, 'Immutable evidence changed: ' + str(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('x') as stream:
            stream.write(data)


def git(checkout, *args):
    return subprocess.check_output(['git', '-C', str(checkout), *args])


def source_manifest():
    paths = git(repo, 'ls-files', '-z', '--', *roots).split(b'\0')
    return {path.decode(): digest((repo / path.decode()).read_bytes()) for path in paths if path}


def contract():
    return json.loads((output / 'contract.json').read_text())


def verify_source():
    value = contract()
    require(lane == value['lane'], 'Lane changed after prepare')
    require(git(repo, 'rev-parse', 'HEAD').decode().strip() == value['source_sha'], 'Source revision changed')
    require(not git(repo, 'status', '--porcelain', '--untracked-files=all'), 'Committed source closure gained dirty or untracked inputs')
    require(source_manifest() == json.loads((output / 'source-before.json').read_text()), 'Source inputs changed')
    require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical package lock changed')
    require(digest((repo / oracle_path).read_bytes()) == value['oracle_sha256'], 'Native oracle changed')


def run(command, log, *, timeout=3600, allow_failure=False):
    print('Running ' + command[0] + '; log ' + str(log), flush=True)
    with log.open('xb') as stream:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise
    if code and not allow_failure:
        print('\n'.join(line[:1000] for line in log.read_text(errors='replace').splitlines()[-25:]), file=sys.stderr)
        raise RuntimeError('Command failed with exit ' + str(code) + '; inspect ' + str(log))
    return code


def failure_sites(source):
    result = {}
    for name in cases[:3]:
        marker = name + ': original all-format clipboard must survive overlapping owned pastes'
        matches = [index + 1 for index, line in enumerate(source.splitlines()) if '#expect(' in line and marker in line]
        require(len(matches) == 1, 'Expected exact source-bound failure marker: ' + name)
        result[matches[0]] = name
    require(len(result) == 3, 'Three distinct failure sites required')
    return result


def classify(text, code, expected_lane, sites):
    errors = []
    starts = re.findall(r'\bTest (\w+)\(\) started\.', text)
    require_starts = collections.Counter(starts) == collections.Counter(cases)
    if not require_starts:
        errors.append('Every selected method must start exactly once, with no other test starts')
    results = {}
    for index, name in enumerate(cases):
        expected = 'failed' if expected_lane == 'baseline' and index < 3 else 'passed'
        results[name] = re.findall(r'\bTest ' + name + r'\(\) (passed|failed|skipped) after ', text)
        if results[name] != [expected]:
            errors.append(name + ' did not finish exactly once with expected result')
    summary = re.findall(r'Test run with (\d+) tests?(?: in (\d+) suites?)? (passed|failed)', text)
    expected_summary = 'failed' if expected_lane == 'baseline' else 'passed'
    if len(summary) != 1 or summary[0][0] != '5' or summary[0][2] != expected_summary or code != (65 if expected_lane == 'baseline' else 0):
        errors.append('Exact five-test summary and expected exit required')
    issues = re.findall(r'^.*\brecorded an issue\b[^\n]*', text, re.M)
    observed_lines = []
    for issue in issues:
        match = re.search(r'\bTest (\w+)\(\) recorded an issue at (.+):(\d+):\d+:.*Expectation failed:', issue)
        if match and Path(match[2]).name == Path(oracle_path).name and sites.get(int(match[3])) == match[1]:
            observed_lines.append(int(match[3]))
    expected_lines = sorted(sites) if expected_lane == 'baseline' else []
    if len(issues) != len(expected_lines) or sorted(observed_lines) != expected_lines:
        errors.append('Only three exact clipboard postcondition assertions may fail')
    if re.search(r'\b(?:crashed|crash report|unexpected exit|Testing cancelled|Test session ended prematurely|failed to launch|fatal error:|skipped)|^.+\.swift:\d+:\d+:\s*error:|^error:', text, re.I | re.M):
        errors.append('Setup, compiler, skip, crash or launch failure cannot count as evidence')
    return {'valid': not errors, 'lane': expected_lane, 'exit_code': code, 'started_tests': starts,
        'test_results': results, 'summary': summary, 'issues': issues, 'failure_lines': observed_lines, 'errors': errors}


def package_identity():
    pins = json.loads((repo / lock_path).read_text())['pins']
    require(len(pins) == 41 and len({pin['identity'] for pin in pins}) == 41, 'Reviewed 41-pin graph required')
    expected = {pin['identity']: pin['state']['revision'] for pin in pins}
    workspace = json.loads((package_checkouts / 'workspace-state.json').read_text())
    actual, trees = {}, {}
    for dependency in workspace['object']['dependencies']:
        identity = dependency['packageRef']['identity']
        if identity not in expected:
            continue
        subpath = dependency['subpath']
        require(Path(subpath).name == subpath and subpath not in ('.', '..'), 'Unsafe package checkout path')
        checkout = package_checkouts / 'checkouts' / subpath
        revision = dependency['state']['checkoutState']['revision']
        head = git(checkout, 'rev-parse', 'HEAD').decode().strip()
        require(revision == head == expected[identity], 'Actual package revision differs: ' + identity)
        require(not git(checkout, 'status', '--porcelain', '--untracked-files=all'), 'Dirty dependency source: ' + identity)
        actual[identity] = head
        trees[identity] = git(checkout, 'rev-parse', 'HEAD^{tree}').decode().strip()
    require(actual == expected, 'Actual package checkouts do not close reviewed graph')
    return {'canonical_lock_sha256': lock_sha, 'revisions': actual, 'clean_tracked_source_trees': trees}


def static_identity():
    framework = Path.home() / 'VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework'
    require(framework.is_dir(), 'Static Whisper framework missing')
    return {str(path.relative_to(framework)): digest(path.read_bytes()) for path in sorted(framework.rglob('*')) if path.is_file()}


def build_arguments():
    return ['-project', str(repo / 'VoiceInk.xcodeproj'), '-scheme', 'VoiceInk', '-configuration', 'Debug',
        '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO', '-derivedDataPath', str(derived),
        '-xcconfig', str(repo / 'LocalBuild.xcconfig'), '-clonedSourcePackagesDirPath', str(package_checkouts),
        '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
        'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_ALLOWED=YES', 'DEVELOPMENT_TEAM=',
        'CODE_SIGN_ENTITLEMENTS=' + str(repo / 'VoiceInk/VoiceInk.local.entitlements'),
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD']


def identity():
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == bundle_id, 'Unexpected native host identity')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    signature = subprocess.run(['codesign', '-dr', '-', str(app)], check=True, text=True, capture_output=True)
    requirements = re.findall(r'^(?:# )?designated => (.+)$', signature.stdout + signature.stderr, re.M)
    require(len(requirements) == 1, 'Exact signed requirement unavailable')
    tests = sorted(derived.glob('Build/Products/Debug/**/VoiceInkTests.xctest'))
    require(len(tests) == 1, 'Exactly one unit test bundle required')
    test_info = plistlib.loads((tests[0] / 'Contents/Info.plist').read_bytes())
    return {'app_path': str(app), 'executable_path': str(executable), 'bundle_identifier': bundle_id,
        'designated_requirement': requirements[0], 'executable_sha256': digest(executable.read_bytes()),
        'app_files_sha256': {str(path.relative_to(app)): digest(path.read_bytes()) for path in sorted(app.rglob('*')) if path.is_file()},
        'test_bundle_sha256': digest((tests[0] / 'Contents/MacOS' / test_info['CFBundleExecutable']).read_bytes())}


def provision_startup_microphone():
    # The normal app starts pre-roll unconditionally. Bind its fresh grant to this exact test build.
    value = identity()
    requirement = output / 'host-requirement.txt'
    requirement.write_text(value['designated_requirement'] + '\n')
    blob = output / 'host.csreq'
    subprocess.run(['csreq', '-r', str(requirement), '-b', str(blob)], check=True)
    requirement_hex = blob.read_bytes().hex().upper()
    database = Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db'
    statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('kTCCServiceMicrophone','" + bundle_id + "',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
    subprocess.run(['sqlite3', str(database)], input=statement, text=True, check=True)
    query = "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='" + bundle_id + "' AND service='kTCCServiceMicrophone';"
    rows = json.loads(subprocess.check_output(['sqlite3', '-json', str(database), query]))
    require(len(rows) == 1 and rows[0]['auth_value'] == 2 and rows[0]['requirement'] == requirement_hex, 'Fresh microphone grant differs from exact signed host')
    write_json(output / 'startup-microphone.json', {'rows': rows, 'reason': 'Normal app startup may start microphone pre-roll; no microphone inactivity claim. Clipboard delivery uses the existing controlled menu seam; no AX grant.'})
    subprocess.run(['killall', 'tccd'], capture_output=True)
    time.sleep(2)


def isolated_configuration():
    candidates = sorted((derived / 'Build/Products').glob('*.xctestrun'))
    require(len(candidates) == 1, 'Exactly one generated native configuration required')
    original = candidates[0].read_bytes()
    value = plistlib.loads(original)
    if 'TestConfigurations' in value:
        targets = [target for config in value['TestConfigurations'] for target in config.get('TestTargets', []) if target.get('BlueprintName') == 'VoiceInkTests']
        for config in value['TestConfigurations']:
            config['TestTargets'] = [target for target in config.get('TestTargets', []) if target.get('BlueprintName') == 'VoiceInkTests']
    else:
        targets = [target for name, target in value.items() if name == 'VoiceInkTests' and isinstance(target, dict)]
        value = {name: target for name, target in value.items() if name == 'VoiceInkTests' or name.startswith('__')}
    require(len(targets) == 1, 'Native host configuration must resolve one unit target')
    target = targets[0]
    require('VoiceInkTests.xctest' in target.get('TestBundlePath', '') and 'roma just talk.app' in target.get('TestHostPath', ''), 'Wrong host or oracle bundle')
    isolated_home = output / 'isolated-user'
    preferences = isolated_home / 'Library/Preferences'
    preferences.mkdir(parents=True)
    seed = {'selectedAIProvider': 'Local CLI', 'CurrentTranscriptionModel': 'whisper-large-v3-turbo',
        'PrewarmModelOnWake': False, 'hasCompletedOnboarding': True, 'isAIEnhancementEnabled': False,
        'IsAudioCleanupEnabled': False, 'IsTranscriptionCleanupEnabled': False, 'enableAnnouncements': False}
    (preferences / (bundle_id + '.plist')).write_bytes(plistlib.dumps(seed))
    environment = target.setdefault('EnvironmentVariables', {})
    environment.update({'CFFIXED_USER_HOME': str(isolated_home), 'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted', 'RUNNER_TEMP': os.environ['RUNNER_TEMP'],
        'RJT_CLIPBOARD_LEASE_CHECKS': '1', 'RJT_CLIPBOARD_LEASE_EVIDENCE': str(output / 'observations')})
    target['CommandLineArguments'] = [item for key, value in seed.items() for item in ['-' + key, 'YES' if value is True else 'NO' if value is False else value]]
    target['ParallelizationEnabled'] = False
    def expand(node):
        if isinstance(node, str):
            return node.replace('__TESTROOT__', str(candidates[0].parent))
        if isinstance(node, list):
            return [expand(item) for item in node]
        if isinstance(node, dict):
            return {key: expand(item) for key, item in node.items()}
        return node
    path = output / 'isolated.xctestrun'
    path.write_bytes(plistlib.dumps(expand(value)))
    write_json(output / 'configuration.json', {'original_sha256': digest(original), 'isolated_sha256': digest(path.read_bytes()),
        'isolated_user_home': str(isolated_home), 'seed_preferences': seed,
        'credential_contract': 'Actual LOCAL_BUILD routes KeychainService to fresh lane UserDefaults; no saved Keychain query. Source/configuration assurance, not SecItem tracing.',
        'scope': 'Actual NSPasteboard with existing controlled menu/document seam; no external editor/AX authorization. Normal startup pre-roll receives one exact signed-host microphone grant.'})


def test_arguments():
    return ['-xctestrun', str(output / 'isolated.xctestrun'), '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO']


def enumerate_selection():
    directory = output / 'selection'
    directory.mkdir()
    selection = ['-only-testing:VoiceInkTests/ClipboardRestorationLeaseTests/' + name + '()' for name in cases]
    run(['xcodebuild', 'test-without-building', *test_arguments(), *selection, '-enumerate-tests',
        '-test-enumeration-style', 'flat', '-test-enumeration-format', 'json', '-test-enumeration-output-path', str(directory / 'selected-tests.json')], directory / 'enumeration.log', timeout=180)
    value = json.loads((directory / 'selected-tests.json').read_text())
    enabled = [test['identifier'] for plan in value.get('values', []) for test in plan.get('enabledTests', [])]
    disabled = [test.get('identifier') for plan in value.get('values', []) for test in plan.get('disabledTests', [])]
    requested = [item.removeprefix('-only-testing:') for item in selection]
    valid = not value.get('errors') and collections.Counter(enabled) == collections.Counter(requested) and not set(requested).intersection(disabled)
    write_json(directory / 'receipt.json', {'valid': valid, 'requested': requested, 'enabled': enabled, 'disabled': disabled})
    require(valid, 'Exact five enabled native methods did not resolve')
    return selection


def execute_native(selection):
    (output / 'observations').mkdir()
    seen = {}
    command = ['xcodebuild', 'test-without-building', *test_arguments(), *selection, '-resultBundlePath', str(output / 'Native.xcresult')]
    write_json(output / 'native-command.json', {'arguments': command})
    with (output / 'tests.log').open('xb') as stream:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 180
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, 'Native clipboard tests exceeded finite 180s boundary')
                for path in sorted((output / 'observations').glob('*.json')):
                    try:
                        value = json.loads(path.read_text())
                    except (OSError, json.JSONDecodeError):
                        continue
                    pid = value.get('processIdentifier')
                    if type(pid) is not int or pid <= 0 or pid in seen:
                        continue
                    live = subprocess.run(['ps', '-p', str(pid), '-o', 'comm=', '-o', 'lstart='], text=True, capture_output=True)
                    if live.returncode == 0 and str(executable) in live.stdout:
                        seen[pid] = {'process_identifier': pid, 'ps_comm_and_start': live.stdout.strip(), 'observed_completed': value.get('completed'), 'observation_file': path.name}
                time.sleep(0.05)
            code = process.wait()
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise
    write_json(output / 'live-hosts.json', {'observed': list(seen.values())})
    (output / 'test-exit.txt').write_text(str(code) + '\n')
    return code


def validate_observations():
    observed = {}
    pids = set()
    for index, name in enumerate(cases):
        path = output / 'observations' / (name + '.json')
        require(path.is_file(), 'Actual observation missing: ' + name)
        value = json.loads(path.read_text())
        require(value.get('version') == 1 and type(value.get('version')) is int and value.get('test') == name, 'Wrong observation version or name')
        require(value.get('completed') is True and 'error' in value and value['error'] is None and value.get('setupValid') is True, 'Native setup/operation failed: ' + name)
        pid = value.get('processIdentifier')
        require(type(pid) is int and pid > 0 and value.get('bundleIdentifier') == bundle_id and value.get('executablePath') == str(executable), 'Native observed host differs')
        pids.add(pid)
        require(value.get('scope') == scope and value.get('pasteboardKind') == ('general' if index in (1, 2) else 'unique'), 'Clipboard boundary differs')
        require(value.get('timerDelaySeconds') == 2.0 and value.get('minimumTimerDelaySeconds') == 0.25, 'Default/minimum restore timing changed')
        require(isinstance(value.get('elapsedSeconds'), (float, int)) and math.isfinite(value['elapsedSeconds']) and value['elapsedSeconds'] >= 2.35, 'Restore deadline was not observed')
        if index < 3:
            require(value.get('beganBeforeFirstDeadline') is True, 'Overlapping operation did not begin before first deadline')
        events = value.get('events')
        require(isinstance(events, list) and len(events) >= 3, 'Actual clipboard trace missing')
        names = [event.get('name') for event in events]
        require(len(names) == len(set(names)) and names[0] == 'original' and names[-1] == 'after-last-deadline', 'Clipboard trace order/identity invalid')
        expected_names = [
            ['original', 'forward-confirmed', 'second-requested', 'second-confirmed', 'after-last-deadline'],
            ['original', 'forward-confirmed', 'second-requested', 'second-confirmed', 'ordinary-requested', 'ordinary-posted', 'after-last-deadline'],
            ['original', 'forward-confirmed', 'second-requested', 'prepared-context-captured', 'ordinary-requested', 'ordinary-posted', 'after-last-deadline'],
            ['original', 'forward-confirmed', 'before-deadline', 'after-last-deadline'],
            ['original', 'forward-confirmed', 'newer-copy', 'after-last-deadline'],
        ][index]
        require(names == expected_names, 'Exact operation trace differs: ' + name)
        for event in events:
            require(type(event.get('changeCount')) is int and isinstance(event.get('elapsedSeconds'), (float, int)) and math.isfinite(event['elapsedSeconds']), 'Clipboard generation/timing missing')
            items = event.get('items')
            require(isinstance(items, list), 'Clipboard item snapshot missing')
            for item in items:
                require(isinstance(item, list) and all(isinstance(entry, dict) and set(entry) == {'type', 'dataBase64'} for entry in item), 'Clipboard format snapshot invalid')
                types = [entry['type'] for entry in item]
                require(all(isinstance(item_type, str) for item_type in types) and types == sorted(set(types)), 'Clipboard format order or identity invalid')
                for entry in item:
                    base64.b64decode(entry['dataBase64'], validate=True)
            text = event.get('plainText')
            if text is not None:
                require(event.get('plainTextUTF8') == list(text.encode('utf-8')) and event.get('plainTextUTF16') == [int.from_bytes(text.encode('utf-16-le')[i:i+2], 'little') for i in range(0, len(text.encode('utf-16-le')), 2)], 'Actual text/code-unit trace differs')
        by_name = {event['name']: event for event in events}
        require('forward-confirmed' in by_name, 'Forward confirmation observation missing')
        require([event['elapsedSeconds'] for event in events] == sorted(event['elapsedSeconds'] for event in events), 'Clipboard event time moved backwards')
        original, final = events[0], events[-1]
        require(len(original['items']) == 2 and original['items'] != by_name['forward-confirmed']['items'], 'Original all-format clipboard or temporary write missing')
        require(sorted(len(item) for item in original['items']) == [2, 3], 'Original multiple formats were not captured')
        expected_counts = [(2, 2, 0), (2, 2, 1), (1, 1, 1), (1, 1, 0), (1, 1, 0)][index]
        require(all(type(value.get(key)) is int for key in ['confirmedWritingPastes', 'menuAttempts', 'ordinaryAttempts']), 'Typed paste attempt counts required')
        require(tuple(value.get(key) for key in ['confirmedWritingPastes', 'menuAttempts', 'ordinaryAttempts']) == expected_counts, 'Confirmed/paste attempt counts differ')
        last_operation = by_name['ordinary-posted'] if 'ordinary-posted' in by_name else by_name['second-confirmed'] if 'second-confirmed' in by_name else by_name['forward-confirmed']
        require(final['elapsedSeconds'] - last_operation['elapsedSeconds'] >= 2.30, 'Actual last operation restoration deadline was not crossed')
        raw_restored = original['items'] == final['items']
        require(value.get('originalRestored') is raw_restored, 'Reported clipboard restoration differs from actual formats')
        expected = lane != 'baseline' or index >= 3
        require(value.get('postconditionPassed') is expected, 'Native postcondition does not match expected lane')
        if index < 3:
            require(raw_restored is expected, 'Actual all-format restore differs from lane')
            request = by_name['second-requested']
            require(0 <= request['elapsedSeconds'] - by_name['forward-confirmed']['elapsedSeconds'] < 2.0 and request['items'] == by_name['forward-confirmed']['items'], 'Second request did not overlap pending forward restoration')
            if lane == 'baseline':
                stranded = by_name['second-confirmed'] if index == 1 else by_name['forward-confirmed']
                require(final['items'] == stranded['items'], 'Known-bad result did not strand the exact earlier temporary payload')
        if index == 3:
            require(raw_restored and 'before-deadline' in by_name and by_name['before-deadline']['items'] == by_name['forward-confirmed']['items'], 'Single-write deadline control failed')
            require(1.5 <= by_name['before-deadline']['elapsedSeconds'] - by_name['forward-confirmed']['elapsedSeconds'] < 2.0, 'Single-write before-deadline observation missing')
        if index == 4:
            require('newer-copy' in by_name and final['items'] == by_name['newer-copy']['items'] and final['changeCount'] == by_name['newer-copy']['changeCount'], 'Newer clipboard generation was overwritten')
        observed[name] = value
    require(len(pids) == 1, 'Exact five cases must run in one disposable unit host')
    live = json.loads((output / 'live-hosts.json').read_text())['observed']
    require(len(live) == 1 and {item['process_identifier'] for item in live} == pids, 'Actual live exact executable observation missing')
    closure_deadline = time.monotonic() + 15
    while time.monotonic() < closure_deadline and any(subprocess.run(['ps', '-p', str(pid)], capture_output=True).returncode == 0 for pid in pids):
        time.sleep(0.1)
    for pid in pids:
        require(subprocess.run(['ps', '-p', str(pid)], capture_output=True).returncode != 0, 'Owned test host did not exit')
    write_json(output / 'host-closure.json', {'process_identifiers': sorted(pids), 'all_exited': True, 'exact_executable_observed_live': True})
    return observed


def self_test():
    sites = {10: cases[0], 20: cases[1], 30: cases[2]}
    def fixture(expected_lane):
        lines = ['◇ Test run started.']
        for index, name in enumerate(cases):
            lines.append('◇ Test ' + name + '() started.')
            result = 'failed' if expected_lane == 'baseline' and index < 3 else 'passed'
            if result == 'failed':
                lines.append('✘ Test ' + name + '() recorded an issue at /source/' + oracle_path + ':' + str((index + 1) * 10) + ':9: Expectation failed: postconditionPassed')
            lines.append(('✘' if result == 'failed' else '✔') + ' Test ' + name + '() ' + result + ' after 0.1 seconds.')
        lines.append(('✘' if expected_lane == 'baseline' else '✔') + ' Test run with 5 tests in 1 suite ' + ('failed' if expected_lane == 'baseline' else 'passed') + ' after 10 seconds.')
        return '\n'.join(lines)
    bad, good = fixture('baseline'), fixture('candidate')
    fixtures = {
        'three-intended-failures': classify(bad, 65, 'baseline', sites)['valid'],
        'five-passed': classify(good, 0, 'candidate', sites)['valid'],
        'wrong-exit-rejected': not classify(bad, 0, 'baseline', sites)['valid'],
        'missing-start-rejected': not classify(bad.replace('◇ Test ' + cases[0] + '() started.', ''), 65, 'baseline', sites)['valid'],
        'missing-issue-rejected': not classify(bad.replace('recorded an issue', 'message'), 65, 'baseline', sites)['valid'],
        'wrong-line-rejected': not classify(bad.replace(':10:9:', ':11:9:'), 65, 'baseline', sites)['valid'],
        'duplicate-rejected': not classify(bad + '\n◇ Test ' + cases[0] + '() started.', 65, 'baseline', sites)['valid'],
        'setup-failure-rejected': not classify(bad + '\nerror: unavailable clipboard', 65, 'baseline', sites)['valid'],
        'skip-rejected': not classify(bad.replace('() passed after', '() skipped after', 1), 65, 'baseline', sites)['valid'],
    }
    print(json.dumps({'valid': all(fixtures.values()), 'classifier_fixtures': fixtures}, indent=2))
    require(all(fixtures.values()), 'Classifier self-test failed')


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    require(lane in ('baseline', 'candidate'), 'Choose immutable baseline or candidate lane')
    if mode == 'self-test':
        self_test()
    elif mode == 'prepare':
        output.mkdir(exist_ok=False)
        source_sha = git(repo, 'rev-parse', 'HEAD').decode().strip()
        require(source_sha == os.environ.get('GITHUB_SHA'), 'Checkout differs from exact workflow SHA')
        require(not git(repo, 'status', '--porcelain', '--untracked-files=all'), 'Fresh committed checkout required')
        require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical 41-pin resolution changed')
        paster_sha = digest((repo / paster_path).read_bytes())
        require((paster_sha == baseline_paster_sha) is (lane == 'baseline'), 'Lane does not identify the immutable known-bad paster or a changed candidate')
        oracle = (repo / oracle_path).read_bytes()
        sites = failure_sites(oracle.decode())
        for name in cases:
            require(len(re.findall(r'func\s+' + name + r'\(', oracle.decode())) == 1, 'Native method missing or duplicated')
        source = output / 'source'
        source.mkdir()
        for path in [paster_path, oracle_path, driver_path, workflow_path, lock_path, 'VoiceInk/Services/KeychainService.swift']:
            destination = source / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((repo / path).read_bytes())
        write_json(output / 'source-before.json', source_manifest())
        write_json(output / 'contract.json', {'source_sha': source_sha, 'lane': lane, 'paster_sha256': paster_sha,
            'known_bad_paster_sha256': baseline_paster_sha, 'oracle_sha256': digest(oracle),
            'canonical_lock_sha256': lock_sha, 'failure_sites': sites, 'cases': cases,
            'scope': scope, 'acceptance': 'known-bad reproduction only' if lane == 'baseline' else 'candidate boundary; matched oracle identity must also be verified against retained old run'})
        write_json(output / 'toolchain-before.json', {name: subprocess.check_output(command, text=True).strip() for name, command in {
            'xcode': ['xcodebuild', '-version'], 'swift': ['swift', '--version'], 'macOS': ['sw_vers']}.items()})
        run(['bash', 'scripts/run-writing-feature-regression.sh', 'packages', str(output / 'packages')], output / 'packages.log')
        verify_source()
    elif mode == 'build':
        verify_source()
        packages, whisper = package_identity(), static_identity()
        write_json(output / 'packages-before.json', packages)
        write_json(output / 'static-whisper-before.json', whisper)
        arguments = build_arguments()
        write_json(output / 'build-command.json', {'arguments': arguments, 'local_build_condition': 'LOCAL_BUILD'})
        run(['xcodebuild', '-showBuildSettings', '-json', *arguments, '-only-testing:VoiceInkTests'], output / 'build-settings.json', timeout=180)
        settings = json.loads((output / 'build-settings.json').read_text())
        host = [value['buildSettings'] for value in settings if value.get('target') == 'VoiceInk']
        require(len(host) == 1 and 'LOCAL_BUILD' in host[0].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split(), 'Actual app settings omit LOCAL_BUILD credential isolation')
        run(['xcodebuild', 'build-for-testing', *arguments, '-only-testing:VoiceInkTests'], output / 'build.log')
        build_log = (output / 'build.log').read_text(errors='replace')
        require(re.search(r'(?:SwiftCompile|CompileSwiftSources)[^\n]*CursorPaster\.swift', build_log) is not None, 'Native build did not record actual CursorPaster compilation')
        require(re.search(r'(?:SwiftCompile|CompileSwiftSources)[^\n]*ClipboardRestorationLeaseTests\.swift', build_log) is not None, 'Native build did not record oracle compilation')
        verify_source()
        require(package_identity() == packages and static_identity() == whisper, 'Dependency sources changed during build')
        identity()
        run(['bash', 'scripts/verify-static-whisper-app.sh', str(app)], output / 'static-app.log')
        run(['bash', 'scripts/verify-adhoc-library-validation.sh', str(app)], output / 'signing.log')
        provision_startup_microphone()
        isolated_configuration()
        write_json(output / 'build-identity.json', identity())
    elif mode == 'run':
        verify_source()
        require(identity() == json.loads((output / 'build-identity.json').read_text()), 'Prepared app identity changed')
        require(digest((output / 'isolated.xctestrun').read_bytes()) == json.loads((output / 'configuration.json').read_text())['isolated_sha256'], 'Prepared launch configuration changed before enumeration')
        selection = enumerate_selection()
        write_json(output / 'identity-before.json', identity())
        execute_native(selection)
        write_json(output / 'identity-after.json', identity())
        verify_source()
    elif mode == 'verify':
        verify_source()
        require(identity() == json.loads((output / 'identity-before.json').read_text()) == json.loads((output / 'identity-after.json').read_text()), 'Actual binary/bundle/signature changed')
        require(package_identity() == json.loads((output / 'packages-before.json').read_text()), 'Package sources changed')
        require(static_identity() == json.loads((output / 'static-whisper-before.json').read_text()), 'Static Whisper bytes changed')
        require(digest((output / 'isolated.xctestrun').read_bytes()) == json.loads((output / 'configuration.json').read_text())['isolated_sha256'], 'Exact native launch configuration changed')
        sites = {int(key): value for key, value in contract()['failure_sites'].items()}
        verdict = classify((output / 'tests.log').read_text(errors='replace'), int((output / 'test-exit.txt').read_text()), lane, sites)
        write_json(output / 'test-classification.json', verdict)
        require(verdict['valid'], 'Native outcomes invalid: ' + '; '.join(verdict['errors']))
        observations = validate_observations()
        write_json(output / 'source-after.json', source_manifest())
        toolchain = {name: subprocess.check_output(command, text=True).strip() for name, command in {
            'xcode': ['xcodebuild', '-version'], 'swift': ['swift', '--version'], 'macOS': ['sw_vers']}.items()}
        require(toolchain == json.loads((output / 'toolchain-before.json').read_text()), 'Toolchain changed')
        write_json(output / 'toolchain-after.json', toolchain)
        write_json(output / 'result.json', {'classification': 'known-bad-reproduced' if lane == 'baseline' else 'candidate-boundary-passed',
            **contract(), 'valid': True, 'test_classification': verdict,
            'observations': {name: {'original_restored': value['originalRestored'], 'postcondition_passed': value['postconditionPassed'], 'elapsed_seconds': value['elapsedSeconds']} for name, value in observations.items()},
            'limits': ['Clipboard restoration only; controlled menu/document seam, no actual editor delivery or Undo command.',
                'Baseline reproduction is not a fixed candidate. Candidate requires same-oracle comparison with retained baseline.',
                'Normal app startup may start microphone pre-roll. No speech recognition, physical keyboard, model quality, rich-text editor, saved Keychain or real customer data exercised.']})
    else:
        raise RuntimeError('Use self-test, prepare, build, run or verify')
except BaseException as error:
    if output.is_dir() and mode != 'self-test':
        write_json(output / ('failure-' + mode + '.json'), {'classification': 'invalid-or-failed', 'phase': mode, 'error': str(error)})
    raise
PY
