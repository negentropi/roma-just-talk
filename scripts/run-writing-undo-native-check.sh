#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run writing Undo checks only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" || "${RUNNER_TEMP:-}" != /* ]]; then
    echo "The native check must own the logged-in disposable desktop and RUNNER_TEMP." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/writing-undo-native-proof" "${1:-}" <<'PY'
import base64
import contextlib
import copy
import hashlib
import json
import os
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
driver_path = 'scripts/run-writing-undo-native-check.sh'
workflow_path = '.github/workflows/voiceink-writing-undo-native-check.yml'
oracle_paths = ['VoiceInkTests/WritingUndoLiveTests.swift', 'VoiceInkTests/WritingTargetLiveTests.swift']
lock_path = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
lock_sha = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
bundle_id = 'com.negentropi.RomaJustTalk'
cases = [
    'liveWritingUndoTextEditRejectsTerminatedProcess',
    'liveWritingUndoTextEditRestoresExactUnicodeSelection',
    'liveWritingUndoSafariPreservesClipboardWithEitherForwardPreference',
    'liveWritingUndoSafariKeepsNewClipboardGeneration',
    'liveWritingUndoRefusesTextCaretAndWindowDrift',
    'liveWritingUndoLatestOwnerAndCancellation',
]
phases = {'process': cases[:1], 'remaining': cases[1:]}
stages = dict(zip(cases, [
    ['process-before', 'process-forward', 'process-terminated', 'replacement-process-refused'],
    ['unicode1-forward', 'unicode1-restored', 'unicode2-forward', 'unicode2-restored', 'second-undo-refused'],
    ['restore-on-forward', 'restore-on-restored', 'restore-on-clipboard', 'restore-off-forward',
     'restore-off-current-copy', 'restore-off-restored', 'restore-off-clipboard'],
    ['forward', 'new-copy', 'restored', 'clipboard'],
    ['caret-forward', 'caret-refused', 'text-forward', 'text-refused', 'window-forward', 'window-refused'],
    ['first-forward', 'second-forward', 'canceled-before-attempt', 'latest-restored', 'second-undo-refused'],
]))
case_checks = dict(zip(cases, [
    ['differentApplicationInstance', 'terminatedProcessRejected'],
    ['unicodeAndSelectionRestoredOnce'],
    ['bothForwardPreferencesPreserveCurrentClipboard'],
    ['newClipboardGeneration', 'newerCopySurvivedBothRestorationOwners'],
    ['sameProcessDifferentWindow', 'driftNeverRetargetedOrMutated'],
    ['newPendingDeliveryOwnsBusyState', 'leaseOverlapPreservedPreviousCapability', 'onlyLatestRewriteWasUndoable'],
]))
clipboard_stages = set(['restore-on-clipboard', 'restore-off-current-copy', 'restore-off-clipboard', 'new-copy', 'clipboard'])
clipboard_argument_keys = {'restoreClipboardAfterPaste', 'clipboardRestoreDelay', 'pasteMethod', 'useAppleScriptPaste'}
derived = repo / '.local-build'
package_checkouts = derived / 'SourcePackages'
roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'VoiceInkTests', 'iOS',
    driver_path, workflow_path, 'Makefile', 'LocalBuild.xcconfig', 'scripts/run-writing-feature-regression.sh',
    'scripts/verify-static-whisper-xcframework.sh', 'scripts/verify-static-whisper-app.sh',
    'scripts/verify-adhoc-macos-test-host.sh', 'scripts/tests/verify-adhoc-macos-test-host.test.sh']

def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(value, indent=2, sort_keys=True) + '\n'
    if path.exists():
        require(path.read_text() == data, 'Immutable evidence changed: ' + str(path))
    else:
        with path.open('x') as stream:
            stream.write(data)


def git(checkout, *args):
    return subprocess.check_output(['git', '-C', str(checkout), *args])


def manifest():
    paths = git(repo, 'ls-files', '-z', '--', *roots).split(b'\0')
    return {path.decode(): digest((repo / path.decode()).read_bytes()) for path in paths if path}


def contract():
    return json.loads((output / 'contract.json').read_text())


def verify_source():
    value = contract()
    require(git(repo, 'rev-parse', 'HEAD').decode().strip() == value['source_sha'], 'The pinned source revision changed')
    require(manifest() == json.loads((output / 'source-before.json').read_text()), 'Product, oracle or verification source changed')
    require(not git(repo, 'ls-files', '--others', '--exclude-standard', '-z', '--', *roots), 'Unexpected untracked product/test inputs exist')
    require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical dependency lock changed')


def run(command, log, *, timeout=1800, allow_failure=False, stderr_log=None):
    print('Running ' + command[0] + '; log ' + str(log), flush=True)
    with log.open('xb') as stream, (stderr_log.open('xb') if stderr_log else contextlib.nullcontext(stream)) as errors:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=errors, start_new_session=True)
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


def package_identity():
    pins = json.loads((repo / lock_path).read_text())['pins']
    expected = {pin['identity']: pin['state']['revision'] for pin in pins}
    require(len(pins) == len(expected) == 41, 'Exactly 41 canonical pins are required')
    workspace = json.loads((package_checkouts / 'workspace-state.json').read_text())
    actual, trees, gitlinks = {}, {}, {}
    for dependency in workspace['object']['dependencies']:
        name = dependency['packageRef']['identity']
        if name not in expected:
            continue
        subpath = dependency['subpath']
        require(Path(subpath).name == subpath and subpath not in ('.', '..'), 'Unsafe dependency checkout path')
        checkout = package_checkouts / 'checkouts' / subpath
        head = git(checkout, 'rev-parse', 'HEAD').decode().strip()
        require(name not in actual and dependency['state']['checkoutState']['revision'] == head == expected[name], 'Actual dependency differs from canonical pin: ' + name)
        require(not git(checkout, 'status', '--porcelain', '--untracked-files=normal', '--ignore-submodules=none'), 'Dependency source tree is dirty: ' + name)
        submodules = git(checkout, 'submodule', 'status', '--recursive').decode().splitlines()
        require(all(line.startswith(' ') for line in submodules), 'A dependency Git link is missing, changed or conflicted: ' + name)
        actual[name], trees[name], gitlinks[name] = head, git(checkout, 'rev-parse', 'HEAD^{tree}').decode().strip(), submodules
    require(actual == expected, 'Actual package checkouts do not close all canonical pins')
    return {'lock_sha256': lock_sha, 'revisions': actual, 'source_trees': trees, 'recursive_gitlinks': gitlinks}


def static_identity():
    framework = Path.home() / 'VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework'
    require(framework.is_dir(), 'Static Whisper framework is missing')
    return {str(path.relative_to(framework)): digest(path.read_bytes()) for path in sorted(framework.rglob('*')) if path.is_file()}


def build_arguments():
    return ['-project', str(repo / 'VoiceInk.xcodeproj'), '-scheme', 'VoiceInk', '-configuration', 'Debug',
        '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO', '-derivedDataPath', str(derived),
        '-xcconfig', str(repo / 'LocalBuild.xcconfig'), '-clonedSourcePackagesDirPath', str(package_checkouts),
        '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
        'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_ALLOWED=YES', 'DEVELOPMENT_TEAM=',
        'CODE_SIGN_ENTITLEMENTS=' + str(repo / 'VoiceInk/VoiceInk.local.entitlements'),
        'ENABLE_DEBUG_DYLIB=NO', 'ENABLE_PREVIEWS=NO', 'ENABLE_HARDENED_RUNTIME=YES',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD']


def identity():
    app = derived / 'Build/Products/Debug/roma just talk.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == bundle_id, 'Unexpected native host identity')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    signing = subprocess.run(['codesign', '-dr', '-', str(app)], check=True, capture_output=True, text=True)
    requirements = re.findall(r'^(?:# )?designated => (.+)$', signing.stdout + signing.stderr, re.M)
    require(len(requirements) == 1, 'Exact signed-host requirement unavailable')
    tests = sorted((derived / 'Build/Products/Debug').rglob('VoiceInkTests.xctest'))
    require(len(tests) == 1, 'Exactly one compiled app-unit bundle is required')
    return {'app_path': str(app), 'executable_path': str(app / 'Contents/MacOS' / info['CFBundleExecutable']),
        'designated_requirement': requirements[0],
        'app_files_sha256': {str(path.relative_to(app)): digest(path.read_bytes()) for path in sorted(app.rglob('*')) if path.is_file()},
        'test_files_sha256': {str(path.relative_to(tests[0])): digest(path.read_bytes()) for path in sorted(tests[0].rglob('*')) if path.is_file()}}


def enumerate_tests(directory, config, host, selected=()):
    directory.mkdir()
    before = tcc_rows()
    write_json(directory / 'tcc-before.json', before)
    try:
        code, _ = run_native(directory, ['xcodebuild', 'test-without-building', '-xctestrun', str(config), '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
        *selected, '-enumerate-tests', '-test-enumeration-style', 'flat', '-test-enumeration-format', 'json',
            '-test-enumeration-output-path', str(directory / 'selected-tests.json')], host['executable_path'], log_name='enumeration.log', execution=False)
        write_json(directory / 'exit.json', {'enumeration_exit_code': code})
        require(code == 0, 'Native enumeration command failed')
    finally:
        after = tcc_rows()
        write_json(directory / 'tcc-after.json', after)
    require(before == after, 'Signature-bound grants changed during enumeration')
    require(not re.search(r'\bTest \w+\(\) started\.', (directory / 'enumeration.log').read_text(errors='replace')), 'Enumeration unexpectedly executed tests')
    value = json.loads((directory / 'selected-tests.json').read_text())
    require(not value.get('errors'), 'Native enumeration reported errors')
    enabled = [test['identifier'] for plan in value.get('values', []) for test in plan.get('enabledTests', [])]
    disabled = [test.get('identifier') for plan in value.get('values', []) for test in plan.get('disabledTests', [])]
    return enabled, disabled


def process_identity(pid):
    result = subprocess.run(['ps', '-p', str(pid), '-ww', '-o', 'lstart=,comm='], capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        return None
    fields = result.stdout.strip().split(None, 5)
    require(len(fields) == 6, 'Native process launch identity could not be read')
    return {'started_at': ' '.join(fields[:5]), 'executable_path': fields[5]}


def host_census(executable):
    result = subprocess.run(['ps', '-axo', 'pid=,lstart=,comm=', '-ww'], capture_output=True, text=True, check=True)
    hosts = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 6)
        if len(fields) == 7 and fields[6] == executable:
            hosts.append({'pid': int(fields[0]), 'started_at': ' '.join(fields[1:6]), 'executable_path': fields[6]})
    return hosts


def mapped_text(pid, executable):
    result = subprocess.run(['lsof', '-n', '-P', '-a', '-p', str(pid), '-d', 'txt', '-Fn'], capture_output=True, text=True)
    require(result.returncode in (0, 1) and not result.stderr.strip(), 'Native host mapped-code inspection failed')
    paths = [line[1:] for line in result.stdout.splitlines() if line.startswith('n')]
    return paths if executable in paths else None



def canonical(identifier):
    return identifier[:-2] if identifier.endswith('()') else identifier


def selected_identifiers(enabled, disabled, names):
    expected = ['VoiceInkTests/VoiceInkTests/' + name for name in names]
    require(len(enabled) == len(set(enabled)), 'Duplicate enabled test identifiers')
    inactive = {canonical(item) for item in disabled}
    result = []
    for identifier in expected:
        matches = [item for item in enabled if canonical(item) == identifier]
        require(len(matches) == 1 and identifier not in inactive, 'Test is missing, duplicated or disabled: ' + identifier)
        result.extend(matches)
    return result


def classify(text, code, names):
    starts = re.findall(r'\bTest (\w+)\(\) started\.', text)
    results = {name: re.findall(r'\bTest ' + name + r'\(\) (passed|failed|skipped) after ', text) for name in names}
    summaries = re.findall(r'Test run with (\d+) tests? in (\d+) suites? (passed|failed)', text)
    errors = []
    if sorted(starts) != sorted(names):
        errors.append('Exactly the selected methods must each start once')
    if any(result != ['passed'] for result in results.values()):
        errors.append('Every selected method must pass exactly once')
    if len(summaries) != 1 or summaries[0][0] != str(len(names)) or int(summaries[0][1]) <= 0 or summaries[0][2] != 'passed' or code != 0:
        errors.append('One exact positive passed summary and exit zero are required')
    if re.search(r'\brecorded an issue\b|\bTest \w+\(\) skipped\b|Test session ended prematurely|Testing cancel(?:led|ed)|failed to launch|fatal error:|crashed|error:.*(?:compil|Swift)', text, re.I):
        errors.append('Issues, skips, cancellation, crashes and compilation/launch failures cannot pass')
    return {'valid': not errors, 'classification': 'passed' if not errors else 'invalid-or-failed', 'exit_code': code,
        'starts': starts, 'results': results, 'summaries': [list(item) for item in summaries], 'errors': errors}


def tcc_rows():
    rows = []
    for service, database, prefix in tcc_services():
        query = "SELECT service,client,client_type,auth_value,hex(csreq) AS requirement FROM access WHERE client='" + bundle_id + "' AND service='" + service + "';"
        rows.extend(json.loads(subprocess.check_output([*prefix, 'sqlite3', '-json', database, query]) or b'[]'))
    return sorted(rows, key=lambda item: item['service'])


def tcc_services():
    # App initialization starts pre-roll independently of these controller tests.
    return [('kTCCServiceAccessibility', '/Library/Application Support/com.apple.TCC/TCC.db', ['sudo']),
        ('kTCCServiceMicrophone', str(Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db'), [])]


def validate_tcc(rows, requirement_hex):
    return rows == sorted([{'service': service, 'client': bundle_id, 'client_type': 0, 'auth_value': 2,
        'requirement': requirement_hex} for service, _, _ in tcc_services()], key=lambda item: item['service'])


def provision(directory, host):
    requirement = directory / 'host-requirement.txt'
    requirement.write_text(host['designated_requirement'] + '\n')
    csreq = directory / 'host.csreq'
    subprocess.run(['csreq', '-r', str(requirement), '-b', str(csreq)], check=True)
    requirement_hex = csreq.read_bytes().hex().upper()
    write_json(directory / 'tcc-preexisting.json', tcc_rows())
    for service, database, prefix in tcc_services():
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','" + bundle_id + "',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
        subprocess.run([*prefix, 'sqlite3', database], input=statement, text=True, check=True)
    for command in [['killall', 'tccd'], ['sudo', 'killall', 'tccd']]:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    before = tcc_rows()
    write_json(directory / 'tcc-before.json', before)
    require(validate_tcc(before, requirement_hex), 'Fresh TCC rows differ from the exact signed host')
    return requirement_hex


def configuration(directory):
    candidates = sorted((derived / 'Build/Products').glob('*.xctestrun'))
    require(len(candidates) == 1, 'Exactly one generated native configuration is required')
    original = candidates[0].read_bytes()
    value = plistlib.loads(original)
    if 'TestConfigurations' in value:
        targets = [target for config in value['TestConfigurations'] for target in config.get('TestTargets', []) if target.get('BlueprintName') == 'VoiceInkTests']
        for config in value['TestConfigurations']:
            config['TestTargets'] = [target for target in config.get('TestTargets', []) if target.get('BlueprintName') == 'VoiceInkTests']
    else:
        targets = [target for name, target in value.items() if name == 'VoiceInkTests' and isinstance(target, dict)]
        value = {name: target for name, target in value.items() if name == 'VoiceInkTests' or name.startswith('__')}
    require(len(targets) == 1, 'Native launch must contain one app-unit target')
    target = targets[0]
    require('VoiceInkTests.xctest' in target.get('TestBundlePath', '') and 'roma just talk.app' in target.get('TestHostPath', ''), 'Wrong native host or oracle bundle')
    home = directory / 'isolated-user'
    preferences = home / 'Library/Preferences'
    preferences.mkdir(parents=True)
    seed = {'selectedAIProvider': 'Local CLI', 'CurrentTranscriptionModel': 'whisper-large-v3-turbo', 'PrewarmModelOnWake': False,
        'hasCompletedOnboarding': True, 'isAIEnhancementEnabled': False, 'IsAudioCleanupEnabled': False,
        'IsTranscriptionCleanupEnabled': False, 'enableAnnouncements': False, 'SUEnableAutomaticChecks': False}
    require(not clipboard_argument_keys.intersection(seed), 'Clipboard preferences must be changed persistently by the actual test')
    (preferences / (bundle_id + '.plist')).write_bytes(plistlib.dumps(seed))
    observations, editors = directory / 'observations', directory / 'editor-observations'
    observations.mkdir()
    editors.mkdir()
    flags = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted', 'RUNNER_TEMP': os.environ['RUNNER_TEMP'],
        'RJT_WRITING_UNDO_LIVE_CHECKS': '1', 'RJT_LIVE_WRITING_TARGET_CHECKS': '1',
        'RJT_WRITING_UNDO_EVIDENCE': str(observations), 'RJT_LIVE_WRITING_TARGET_EVIDENCE': str(editors)}
    environment = target.setdefault('EnvironmentVariables', {})
    environment.update(flags)
    environment.update({'TEST_RUNNER_' + key: val for key, val in flags.items()})
    environment['CFFIXED_USER_HOME'] = str(home)
    # Cocoa splits the provider's space-containing value in NSArgumentDomain.
    arguments = [item for key, val in seed.items() if key != 'selectedAIProvider'
        for item in ['-' + key, 'YES' if val is True else 'NO' if val is False else val]]
    require(not clipboard_argument_keys.intersection(item.lstrip('-') for item in arguments), 'Forbidden clipboard launch override')
    target['CommandLineArguments'], target['ParallelizationEnabled'] = arguments, False
    def expand(node):
        if isinstance(node, str):
            return node.replace('__TESTROOT__', str(candidates[0].parent))
        if isinstance(node, list):
            return [expand(item) for item in node]
        if isinstance(node, dict):
            return {key: expand(item) for key, item in node.items()}
        return node
    path = directory / 'isolated.xctestrun'
    path.write_bytes(plistlib.dumps(expand(value)))
    write_json(directory / 'configuration.json', {'original_sha256': digest(original), 'isolated_sha256': digest(path.read_bytes()),
        'seed_preferences': seed, 'command_line_arguments': arguments, 'environment': flags,
        'clipboard_preferences': 'No clipboard keys in argument domain; tests mutate and restore actual persistent preferences.',
        'credential_contract': 'LOCAL_BUILD uses fresh UserDefaults instead of the saved Keychain; exact Local CLI provider lives only in the isolated persistent plist, never NSArgumentDomain. No provider calls.'})
    return path


def close_native_hosts(directory, seen, executable):
    for host in seen.values():
        current = process_identity(host['pid'])
        if current is not None:
            require(current == {key: host[key] for key in ['started_at', 'executable_path']}, 'Refuse to terminate a reused or foreign native-host PID')
            try:
                os.kill(host['pid'], signal.SIGTERM)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                current = process_identity(host['pid'])
                if current is None:
                    break
                require(current == {key: host[key] for key in ['started_at', 'executable_path']}, 'Native-host PID was reused during cleanup')
                time.sleep(0.1)
        require(process_identity(host['pid']) is None, 'Owned native test host did not exit within the bounded cleanup')
    require(not host_census(executable), 'An unclosed or unobserved native host still uses the exact executable')
    result = subprocess.run(['lsof', '-n', '-P', '-Fpn', '--', executable], capture_output=True, text=True)
    require(result.returncode in (0, 1) and not result.stderr.strip() and not result.stdout.strip(), 'Exact native executable still has open descriptors after host exit')
    write_json(directory / 'host-closed.json', {'valid': True, 'executable_path': executable, 'host_pids': sorted(seen),
        'observed_host_launches': sorted(seen.values(), key=lambda item: item['pid']), 'all_observed_hosts_exited': True,
        'exact_executable_census_empty': True, 'exact_executable_has_no_open_descriptors': True,
        'limits': 'Only exact observed RJT host processes are terminated. Editor cleanup belongs to owned test fixtures; no editor process-name termination.'})


def run_native(directory, command, executable, *, log_name='tests.log', execution=True):
    require(not host_census(executable), 'A native host already uses this exact freshly built executable')
    seen = {}
    deadline = time.monotonic() + (1200 if execution else 180)
    print('Running xcodebuild; log ' + str(directory / log_name), flush=True)
    with (directory / log_name).open('xb') as stream:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                for host in host_census(executable):
                    pid = host['pid']
                    if pid in seen:
                        require(all(host[key] == seen[pid][key] for key in host), 'Observed native PID was reused')
                    else:
                        paths = mapped_text(pid, executable)
                        if paths is not None:
                            seen[pid] = dict(host, mapped_text_paths=paths, observed_live=True)
                require(time.monotonic() < deadline, 'Native phase exceeded its bounded deadline')
                time.sleep(0.1)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            write_json(directory / 'host-live.json', {'executable_path': executable, 'hosts': sorted(seen.values(), key=lambda item: item['pid'])})
            close_native_hosts(directory, seen, executable)
    require(len(seen) == 1 if execution else len(seen) <= 1, 'Unexpected live mapped native host count')
    return process.returncode, seen


def integer(value):
    return type(value) is int and value >= 0


def code_units(value):
    return isinstance(value, list) and bool(value) and all(type(unit) is int and 0 <= unit <= 65535 for unit in value)


def valid_range(value, length):
    return isinstance(value, dict) and set(value) == {'location', 'length'} and all(integer(item) for item in value.values()) and value['location'] + value['length'] <= length


def valid_clipboard(value):
    if not isinstance(value, list) or len(value) != 2:
        return False
    names = []
    for item in value:
        if not isinstance(item, dict) or set(item) != {'types'} or not isinstance(item['types'], list) or not item['types']:
            return False
        types = []
        for representation in item['types']:
            if not isinstance(representation, dict) or set(representation) != {'type', 'dataBase64'}:
                return False
            name, encoded = representation['type'], representation['dataBase64']
            if not isinstance(name, str) or not name or not isinstance(encoded, str):
                return False
            try:
                raw = base64.b64decode(encoded, validate=True)
            except ValueError:
                return False
            if not raw:
                return False
            if name == 'com.negentropi.undo-native.binary' and raw != bytes([0, 255, 12, 0, 128]):
                return False
            types.append(name)
        if types != sorted(set(types)):
            return False
        names.append(types)
    return names == [sorted(['public.utf8-plain-text', 'com.negentropi.undo-native.binary']), ['com.negentropi.undo-native.second']]


def observation_errors(name, value, executable, observed_pids):
    errors = []
    def check(condition, message):
        if not condition:
            errors.append(name + ': ' + message)
    check(type(value.get('schemaVersion')) is int and value['schemaVersion'] == 1 and value.get('caseName') == name and value.get('completed') is True, 'Incomplete or wrong method/schema receipt')
    check(type(value.get('hostPID')) is int and value['hostPID'] in observed_pids and value.get('hostExecutablePath') == executable, 'Receipt host was not independently observed with exact mapped executable')
    bounds = value.get('runtimeBounds', {})
    check(isinstance(bounds, dict) and all(bounds.get(key) is expected for key, expected in
        {'controllerAPI': True, 'productMenuOrShortcut': False, 'syntheticProvider': False, 'ASR': False}.items()), 'Runtime scope changed')
    checks = value.get('checks', {})
    required = {'completedStages', 'exactTextObservations', 'exactRangeObservations', 'expectedEditorRoutes', *case_checks[name]}
    check(isinstance(checks, dict) and required.issubset(checks) and all(item is True for item in checks.values()), 'Actual case checks missing or false')
    extra = value.get('extra', {})
    check(isinstance(extra, dict) and all(type(extra.get(key)) is int and extra[key] == 1 for key in ['latestForwardAttempts', 'latestForwardConfirmations']), 'Actual forward attempt/confirmation must be singular')
    observations = value.get('observations', [])
    if not isinstance(observations, list) or not all(isinstance(item, dict) for item in observations):
        return errors + [name + ': Invalid observations']
    actual_names = [item.get('name') for item in observations]
    check(len(actual_names) == len(stages[name]) and len(actual_names) == len(set(str(item) for item in actual_names)) and set(str(item) for item in actual_names) == set(stages[name]), 'Exact unique actual stage set required')
    editors = []
    for item in observations:
        stage = item.get('name')
        check(isinstance(item.get('uptime'), (int, float)) and not isinstance(item['uptime'], bool) and item['uptime'] > 0, 'Actual stage uptime missing')
        if stage in clipboard_stages:
            expected, observed = item.get('clipboardExpected'), item.get('clipboardObserved')
            check(valid_clipboard(expected) and valid_clipboard(observed) and expected == observed, 'All-format two-item clipboard differs or is invalid')
            before, after = item.get('readBeforeCount'), item.get('readAfterCount')
            check(integer(before) and integer(after) and before == after, 'Clipboard readback generation changed')
            continue
        check(type(item.get('pid')) is int and item['pid'] > 0, 'Actual editor PID missing')
        check(item.get('bundleIdentifier') == ('com.apple.Safari' if name in cases[2:4] + cases[5:] else 'com.apple.TextEdit'), 'Wrong native editor')
        try:
            token = item.get('token', '')
            require(isinstance(token, str) and token.startswith('RJT-Writing-Live-'), 'Missing owned editor token prefix')
            uuid.UUID(token.removeprefix('RJT-Writing-Live-'))
        except (ValueError, TypeError, AttributeError, RuntimeError):
            errors.append(name + ': Owned editor token missing')
        if stage == 'process-terminated':
            check(item.get('isTerminated') is True and item.get('undoAvailable') is False, 'Old process termination/refusal not observed')
            check(not {'expectedUTF16', 'observedUTF16', 'range', 'expectedRange'}.intersection(item), 'Terminated process cannot assert live AX text')
            continue
        expected, observed, original = item.get('expectedUTF16'), item.get('observedUTF16'), item.get('sourceUTF16')
        check(code_units(expected) and code_units(observed) and expected == observed and code_units(original), 'Exact actual UTF16 observation required')
        count = len(observed) if isinstance(observed, list) else 0
        check(valid_range(item.get('range'), count) and valid_range(item.get('expectedRange'), count) and item.get('range') == item.get('expectedRange'), 'Actual selected range differs')
        check(item.get('sameWindow') is True and item.get('windowPresent') is True, 'Owned window identity absent')
        route = item.get('bundleIdentifier') == 'com.apple.Safari'
        check(item.get('usesSystemPaste') is route and item.get('expectedUsesSystemPaste') is route, 'Actual native editor route differs')
        focus = stage != 'window-refused'
        check(item.get('expectsFocused') is focus and (item.get('sameProcess') is True and item.get('sameFocusedEditor') is True if focus else item.get('sameFocusedEditor') is False), 'Focus identity contradicts actual stage')
        editors.append(item)
    if name == cases[0] and len(editors) == 3:
        observed = {item['name']: item for item in observations}
        check(observed['process-before'].get('pid') == observed['process-forward'].get('pid') == observed['process-terminated'].get('pid'), 'Original owned process identity differs')
        check(observed['process-before'].get('token') == observed['process-forward'].get('token') == observed['process-terminated'].get('token') != observed['replacement-process-refused'].get('token'), 'Replacement owned window must differ')
    return errors


def closed_launches(directory, host, *, execution):
    live = json.loads((directory / 'host-live.json').read_text())
    closed = json.loads((directory / 'host-closed.json').read_text())
    pids = {item['pid'] for item in live['hosts']}
    require(len(pids) == 1 if execution else len(pids) <= 1, 'Unexpected retained host count')
    require(len(live['hosts']) == len(pids) and live['hosts'] == closed['observed_host_launches'], 'Retained live and closed host launches differ')
    require(live['executable_path'] == closed['executable_path'] == host['executable_path'] and pids == set(closed['host_pids']), 'Launch/closure identity differs')
    require(all(item['observed_live'] is True and item['executable_path'] == host['executable_path'] and host['executable_path'] in item['mapped_text_paths'] and item['started_at'] for item in live['hosts']), 'Actual mapped-code launch evidence missing')
    require(closed['valid'] and all(closed[key] is True for key in ['all_observed_hosts_exited', 'exact_executable_census_empty', 'exact_executable_has_no_open_descriptors']), 'Native host closure missing')
    return live['hosts']


def phase_result(directory, names, host):
    exit_code = json.loads((directory / 'exit.json').read_text())['test_without_building_exit_code']
    verdict = classify((directory / 'tests.log').read_text(errors='replace'), exit_code, names)
    paths = sorted((directory / 'observations').glob('*.json'))
    require(sorted(path.stem for path in paths) == sorted(names), 'Exactly the selected per-method observations are required')
    launches = closed_launches(directory, host, execution=True)
    pids = {item['pid'] for item in launches}
    for path in paths:
        verdict['errors'].extend(observation_errors(path.stem, json.loads(path.read_text()), host['executable_path'], pids))
    requirement_hex = (directory / 'host.csreq').read_bytes().hex().upper()
    before, after = [json.loads((directory / ('tcc-' + point + '.json')).read_text()) for point in ['before', 'after']]
    require(validate_tcc(before, requirement_hex) and before == after, 'Actual signature-bound TCC grants changed during phase')
    enumeration_hosts = {}
    for scope in ['discovery', 'selection']:
        root = directory / scope
        enumeration_hosts[scope] = closed_launches(root, host, execution=False)
        require(json.loads((root / 'exit.json').read_text())['enumeration_exit_code'] == 0, 'Retained enumeration failed')
        require(json.loads((root / 'tcc-before.json').read_text()) == json.loads((root / 'tcc-after.json').read_text()) == before, 'Enumeration signature-bound grants changed')
        require(not re.search(r'\bTest \w+\(\) started\.', (root / 'enumeration.log').read_text(errors='replace')), 'Retained enumeration executed tests')
    selection = json.loads((directory / 'selection/receipt.json').read_text())
    require(selection['valid'] and selected_identifiers(selection['enabled'], selection['disabled'], names) == selection['requested'] and len(selection['enabled']) == len(names), 'Retained exact selection invalid')
    verdict.update({'valid': not verdict['errors'], 'classification': 'passed' if not verdict['errors'] else 'invalid-or-failed',
        'observation_sha256': {path.name: digest(path.read_bytes()) for path in paths}, 'native_host_launch': launches[0],
        'enumeration_host_launches': enumeration_hosts})
    return verdict


def execute_phase(phase, names, host):
    directory = output / phase
    directory.mkdir()
    require(host == identity(), 'Signed app/oracle changed before phase')
    config = configuration(directory)
    config_sha = digest(config.read_bytes())
    # Enumeration itself launches the app on Xcode 26; grant first and close each host.
    provision(directory, host)
    enabled, disabled = enumerate_tests(directory / 'discovery', config, host)
    requested = selected_identifiers(enabled, disabled, names)
    selected = ['-only-testing:' + identifier for identifier in requested]
    narrow, inactive = enumerate_tests(directory / 'selection', config, host, selected)
    require(selected_identifiers(narrow, inactive, names) == requested and len(narrow) == len(names), 'Exact narrow selection differs')
    write_json(directory / 'selection/receipt.json', {'valid': True, 'requested': requested, 'enabled': narrow, 'disabled': inactive})
    require(not list((directory / 'observations').iterdir()), 'Enumeration created native case observations')
    write_json(directory / 'identity-before.json', identity())
    try:
        code, seen = run_native(directory, ['xcodebuild', 'test-without-building', '-xctestrun', str(config), '-destination', 'platform=macOS',
            '-parallel-testing-enabled', 'NO', *selected, '-resultBundlePath', str(directory / 'Native.xcresult')], host['executable_path'])
        write_json(directory / 'exit.json', {'test_without_building_exit_code': code})
    finally:
        # Save actual after-state before any later phase can regrant permissions.
        write_json(directory / 'tcc-after.json', tcc_rows())
        write_json(directory / 'identity-after.json', identity())
    require(host == identity() and digest(config.read_bytes()) == config_sha, 'Signed app, oracle binary or launch configuration changed')
    verdict = phase_result(directory, names, host)
    write_json(directory / 'result.json', verdict)
    require(verdict['valid'], phase + ': ' + '; '.join(verdict['errors']))
    verify_source()
    return verdict


def recipe_self_test():
    # Exercise the real orchestration with inert command boundaries: the old
    # enumerate-before-grant ordering must fail even when every test would pass.
    saved = {key: globals()[key] for key in ['output', 'configuration', 'provision', 'enumerate_tests',
        'identity', 'run_native', 'tcc_rows', 'phase_result', 'verify_source']}
    events = []
    host = {'executable_path': '/inert-fixture/app'}
    names = cases[:1]
    def config(directory):
        (directory / 'observations').mkdir()
        path = directory / 'isolated.xctestrun'
        path.write_bytes(b'inert configuration')
        return path
    def grant(directory, value):
        events.append('fresh-grants')
    def enumeration(directory, config, value, selected=()):
        require(events and events[0] == 'fresh-grants', 'Enumeration ran before fresh signature-bound grants')
        events.append(directory.name)
        (directory).mkdir()
        return ['VoiceInkTests/VoiceInkTests/' + names[0] + '()'], []
    def execution(directory, command, executable):
        require(events == ['fresh-grants', 'discovery', 'selection'], 'Native execution preceded exact discovery/selection')
        events.append('execution')
        return 0, {}
    try:
        with tempfile.TemporaryDirectory(prefix='rjt-undo-recipe-') as temporary:
            globals().update(output=Path(temporary), configuration=config, provision=grant, enumerate_tests=enumeration,
                identity=lambda: host, run_native=execution, tcc_rows=lambda: [],
                phase_result=lambda *args: {'valid': True, 'errors': []}, verify_source=lambda: None)
            execute_phase('inert', names, host)
            require(events == ['fresh-grants', 'discovery', 'selection', 'execution'], 'Phase recipe omitted required boundaries')
    finally:
        globals().update(saved)


def configuration_self_test():
    saved_derived, saved_temporary = derived, os.environ.get('RUNNER_TEMP')
    try:
        with tempfile.TemporaryDirectory(prefix='rjt-undo-config-') as temporary:
            root = Path(temporary)
            os.environ['RUNNER_TEMP'] = temporary
            globals()['derived'] = root / 'derived'
            products = derived / 'Build/Products'
            products.mkdir(parents=True)
            template = {'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'VoiceInkTests',
                'TestBundlePath': '__TESTROOT__/VoiceInkTests.xctest', 'TestHostPath': '__TESTROOT__/roma just talk.app',
                'CommandLineArguments': ['-selectedAIProvider', 'Wrong Provider', '-restoreClipboardAfterPaste', 'YES']}]}]}
            (products / 'fixture.xctestrun').write_bytes(plistlib.dumps(template))
            directory = root / 'phase'
            directory.mkdir()
            value = plistlib.loads(configuration(directory).read_bytes())
            target = value['TestConfigurations'][0]['TestTargets'][0]
            arguments = target['CommandLineArguments']
            require('-selectedAIProvider' not in arguments and not clipboard_argument_keys.intersection(item.lstrip('-') for item in arguments), 'Provider or clipboard launch override survived configuration')
            seed = plistlib.loads((directory / 'isolated-user/Library/Preferences' / (bundle_id + '.plist')).read_bytes())
            require(seed['selectedAIProvider'] == 'Local CLI', 'Full provider value missing from isolated persistent plist')
            require(target['EnvironmentVariables']['RUNNER_TEMP'] == temporary and target['EnvironmentVariables']['TEST_RUNNER_RUNNER_TEMP'] == temporary, 'Required runner temporary directory was not passed to the test host')
    finally:
        globals()['derived'] = saved_derived
        if saved_temporary is None:
            os.environ.pop('RUNNER_TEMP', None)
        else:
            os.environ['RUNNER_TEMP'] = saved_temporary


def self_test():
    good = '\n'.join('Test ' + name + '() started.\nTest ' + name + '() passed after 1 second.' for name in cases)
    good += '\nTest run with 6 tests in 1 suite passed'
    require(classify(good, 0, cases)['valid'], 'Valid exact log rejected')
    require(classify(good + '\n[CoreAudioRecorder] stopRecording: skipped, not recording and no audio unit', 0, cases)['valid'], 'Benign app startup skipped message rejected')
    for text, code in [(good, 1), (good.replace(cases[0], cases[1]), 0), (good + '\nTest ' + cases[0] + '() started.', 0),
                       (good.replace('6 tests', '0 tests'), 0), (good + '\nTesting cancelled', 0),
                       (good.replace('passed after', 'skipped after', 1), 0), (good + '\nrecorded an issue', 0)]:
        require(not classify(text, code, cases)['valid'], 'Malformed result accepted')
    one = 'VoiceInkTests/VoiceInkTests/' + cases[0]
    require(selected_identifiers([one + '()'], [], cases[:1]) == [one + '()'], 'Exact selector suffix normalization failed')
    for enabled, disabled in [([], []), ([one, one + '()'], []), ([one], [one + '()']), (['Other/VoiceInkTests/' + cases[0]], [])]:
        try:
            selected_identifiers(enabled, disabled, cases[:1])
        except RuntimeError:
            pass
        else:
            raise RuntimeError('Missing/duplicate/disabled/foreign selector accepted')
    clip = [{'types': [{'type': 'com.negentropi.undo-native.binary', 'dataBase64': base64.b64encode(bytes([0, 255, 12, 0, 128])).decode()},
                       {'type': 'public.utf8-plain-text', 'dataBase64': 'YQ=='}]},
            {'types': [{'type': 'com.negentropi.undo-native.second', 'dataBase64': 'Yg=='}]}]
    require(valid_clipboard(clip) and not valid_clipboard([]), 'Clipboard structural classifier invalid')
    count = 0
    for name in cases:
        value = {'schemaVersion': 1, 'caseName': name, 'completed': True, 'hostPID': 42, 'hostExecutablePath': '/fixture/app',
            'checks': {key: True for key in ['completedStages', 'exactTextObservations', 'exactRangeObservations', 'expectedEditorRoutes', *case_checks[name]]},
            'extra': {'latestForwardAttempts': 1, 'latestForwardConfirmations': 1},
            'runtimeBounds': {'controllerAPI': True, 'productMenuOrShortcut': False, 'syntheticProvider': False, 'ASR': False}, 'observations': []}
        for stage in stages[name]:
            item = {'name': stage, 'uptime': 1.0}
            if stage in clipboard_stages:
                item.update(clipboardExpected=copy.deepcopy(clip), clipboardObserved=copy.deepcopy(clip), readBeforeCount=10, readAfterCount=10)
            else:
                item.update(pid=101 if stage == 'replacement-process-refused' else 100,
                    bundleIdentifier='com.apple.Safari' if name in cases[2:4] + cases[5:] else 'com.apple.TextEdit', token='RJT-Writing-Live-' + ('00000000-0000-0000-0000-000000000002' if stage == 'replacement-process-refused' else '00000000-0000-0000-0000-000000000001'))
                if stage == 'process-terminated':
                    item.update(isTerminated=True, undoAvailable=False)
                else:
                    item.update(sourceUTF16=[65, 0xD83D, 0xDE00], expectedUTF16=[65, 0xD83D, 0xDE00], observedUTF16=[65, 0xD83D, 0xDE00],
                        expectedRange={'location': 1, 'length': 2}, range={'location': 1, 'length': 2}, sameWindow=True,
                        windowPresent=True, expectsFocused=stage != 'window-refused', sameProcess=True, sameFocusedEditor=stage != 'window-refused',
                        usesSystemPaste=name in cases[2:4] + cases[5:], expectedUsesSystemPaste=name in cases[2:4] + cases[5:])
            value['observations'].append(item)
        require(not observation_errors(name, value, '/fixture/app', {42}), 'Valid synthetic protocol fixture rejected: ' + name)
        mutations = []
        bad = copy.deepcopy(value); bad['completed'] = False; mutations.append(bad)
        bad = copy.deepcopy(value); bad['observations'].pop(); mutations.append(bad)
        bad = copy.deepcopy(value); bad['hostPID'] = 99; mutations.append(bad)
        bad = copy.deepcopy(value); bad['checks'][case_checks[name][0]] = False; mutations.append(bad)
        bad = copy.deepcopy(value); bad['runtimeBounds']['ASR'] = True; mutations.append(bad)
        bad = copy.deepcopy(value); bad['observations'][0]['usesSystemPaste'] = not value['observations'][0]['usesSystemPaste']; mutations.append(bad)
        bad = copy.deepcopy(value); bad['observations'][0]['observedUTF16'] = [66]; mutations.append(bad)
        if any(item['name'] in clipboard_stages for item in value['observations']):
            bad = copy.deepcopy(value)
            next(item for item in bad['observations'] if item['name'] in clipboard_stages)['readAfterCount'] = 11
            mutations.append(bad)
            bad = copy.deepcopy(value)
            next(item for item in bad['observations'] if item['name'] in clipboard_stages)['clipboardObserved'][0]['types'][0]['dataBase64'] = '!!!'
            mutations.append(bad)
        for bad in mutations:
            require(observation_errors(name, bad, '/fixture/app', {42}), 'Broken observation accepted: ' + name)
            count += 1
    recipe_self_test()
    configuration_self_test()
    print('Undo classifier self-test passed: exact selection, benign startup log, grant-before-enumeration recipe, persistent provider configuration and six receipt protocols; ' + str(count) + ' rejected observation mutations. No app or clipboard execution.')


def interrupted(signum, _frame):
    raise RuntimeError('Native verification interrupted by signal ' + str(signum))


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)

try:
    if mode == 'self-test':
        self_test()
    elif mode == 'prepare':
        output.mkdir(exist_ok=False)
        require(not git(repo, 'status', '--porcelain', '--untracked-files=normal', '--', *roots), 'Commit source inputs before native verification')
        require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical lock differs')
        require(git(repo, 'rev-parse', 'HEAD').decode().strip() == os.environ['GITHUB_SHA'], 'GitHub head differs from actual source')
        for name in cases:
            require(len(re.findall(r'\bfunc ' + name + r'\(\)', (repo / oracle_paths[0]).read_text())) == 1, 'Native method missing or duplicated: ' + name)
        write_json(output / 'source-before.json', manifest())
        write_json(output / 'contract.json', {'source_sha': git(repo, 'rev-parse', 'HEAD').decode().strip(), 'github_run_id': os.environ['GITHUB_RUN_ID'],
            'oracle_sha256': {path: digest((repo / path).read_bytes()) for path in oracle_paths}, 'tests': cases, 'phases': phases,
            'lock_sha256': lock_sha, 'canonical_pins': 41,
            'scope': 'Six native WritingActionUndoController cases with real TextEdit/Safari AX targets and disposable clipboard payloads; one built Debug app, two separate closed execution hosts plus independently observed/closed enumeration hosts.',
            'limits': ['Product menu/shortcut route is a separate UI gate.', 'No ASR, microphone, model/provider-quality or physical-keyboard proof.',
                'Clipboard fixtures only on the disposable runner; no shared-user clipboard.', 'No release or broad editor compatibility claim.',
                'Accessibility and Microphone are provisioned for the signed app; normal app initialization starts pre-roll. No Automation grant or microphone acceptance claim.']})
        for path in oracle_paths:
            destination = output / 'source' / Path(path).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((repo / path).read_bytes())
        run(['bash', 'scripts/run-writing-feature-regression.sh', 'packages', str(output / 'packages'), '', '', str(package_checkouts)], output / 'packages.log')
        run(['sw_vers'], output / 'sw-vers.txt')
        run(['xcodebuild', '-version'], output / 'xcode-version.txt')
        run(['swift', '--version'], output / 'swift-version.txt')
        verify_source()
    elif mode == 'native':
        verify_source()
        packages, whisper = package_identity(), static_identity()
        write_json(output / 'packages-before.json', packages)
        write_json(output / 'static-whisper-before.json', whisper)
        arguments = build_arguments()
        write_json(output / 'build-command.json', {'arguments': arguments, 'local_build_condition': 'LOCAL_BUILD'})
        run(['xcodebuild', '-showBuildSettings', '-json', *arguments], output / 'build-settings.json', timeout=180, stderr_log=output / 'build-settings-errors.log')
        settings = [item['buildSettings'] for item in json.loads((output / 'build-settings.json').read_text()) if item.get('target') == 'VoiceInk']
        require(len(settings) == 1 and 'LOCAL_BUILD' in settings[0].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split(), 'Actual host lacks LOCAL_BUILD isolation')
        expected = {'ENABLE_DEBUG_DYLIB': 'NO', 'ENABLE_PREVIEWS': 'NO', 'ENABLE_HARDENED_RUNTIME': 'YES'}
        require({key: settings[0].get(key) for key in expected} == expected, 'Resolved native build settings differ')
        write_json(output / 'resolved-test-host-settings.json', {'target': 'VoiceInk', 'resolved': expected,
            'limits': 'Build settings only; actual ad-hoc CodeDirectory flags are verified separately. No Hardened Runtime signature claim.'})
        run(['xcodebuild', 'build-for-testing', *arguments, '-only-testing:VoiceInkTests'], output / 'build.log')
        verify_source()
        require(package_identity() == packages and static_identity() == whisper, 'Dependencies changed during build')
        host = identity()
        write_json(output / 'identity-before.json', host)
        run(['bash', 'scripts/verify-static-whisper-app.sh', host['app_path']], output / 'static-app.log')
        run(['bash', 'scripts/verify-adhoc-macos-test-host.sh', host['app_path'], str(output / 'test-host-signature')], output / 'signing.log')
        results = {phase: execute_phase(phase, names, host) for phase, names in phases.items()}
        require(results['process']['native_host_launch'] != results['remaining']['native_host_launch'], 'The exclusive first phase did not use a separate host launch')
        require(host == identity() and package_identity() == packages and static_identity() == whisper, 'App, oracle binary or dependencies changed during execution')
        verify_source()
        write_json(output / 'identity-after.json', identity())
        write_json(output / 'source-after.json', manifest())
        write_json(output / 'result.json', {'valid': True, 'classification': 'passed', 'source_sha': contract()['source_sha'], 'tests': cases,
            'phases': {phase: digest((output / phase / 'result.json').read_bytes()) for phase in phases}, 'limits': contract()['limits']})
    elif mode == 'verify':
        verify_source()
        host = json.loads((output / 'identity-before.json').read_text())
        require(host == json.loads((output / 'identity-after.json').read_text()) == identity(), 'Retained app/oracle identity changed')
        require(package_identity() == json.loads((output / 'packages-before.json').read_text()) and static_identity() == json.loads((output / 'static-whisper-before.json').read_text()), 'Frozen dependencies changed')
        launches = []
        for phase, names in phases.items():
            directory = output / phase
            expected = phase_result(directory, names, host)
            require(expected['valid'] and expected == json.loads((directory / 'result.json').read_text()), 'Retained phase result differs or failed')
            require(json.loads((directory / 'identity-before.json').read_text()) == json.loads((directory / 'identity-after.json').read_text()) == host, 'Phase app/oracle identity differs')
            config = json.loads((directory / 'configuration.json').read_text())
            require(digest((directory / 'isolated.xctestrun').read_bytes()) == config['isolated_sha256'], 'Phase launch configuration changed')
            launches.append(expected['native_host_launch'])
        require(launches[0] != launches[1] and not host_census(host['executable_path']), 'Separate closed native-host launches required')
        result = json.loads((output / 'result.json').read_text())
        require(result['valid'] is True and result['source_sha'] == contract()['source_sha'] and result['tests'] == cases and result['phases'] == {phase: digest((output / phase / 'result.json').read_bytes()) for phase in phases}, 'Full native result binding invalid')
        write_json(output / 'complete-result.json', {'classification': 'passed', 'source_sha': contract()['source_sha'], 'tests': cases,
            'result_sha256': digest((output / 'result.json').read_bytes()), 'native_cases': 6, 'execution_host_launches': 2, 'limits': contract()['limits']})
    else:
        raise RuntimeError('usage: run-writing-undo-native-check.sh self-test | prepare | native | verify')
except BaseException as error:
    if output.is_dir() and mode != 'self-test':
        (output / ('failure-' + mode + '.json')).write_text(json.dumps({'mode': mode, 'classification': 'invalid-or-failed', 'error': str(error)}, indent=2) + '\n')
    raise
PY
