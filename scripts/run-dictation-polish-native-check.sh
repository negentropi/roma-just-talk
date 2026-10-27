#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run dictation polish checks only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The native check must own the logged-in disposable desktop." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/dictation-polish-native-proof" "${1:-}" <<'PY'
import contextlib
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
import wave
from pathlib import Path
from urllib.parse import urlparse

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
driver_path = 'scripts/run-dictation-polish-native-check.sh'
workflow_path = '.github/workflows/voiceink-dictation-polish-native-check.yml'
oracle_paths = ['VoiceInkTests/DictationProfileImportLiveTests.swift', 'VoiceInkTests/WritingTargetLiveTests.swift']
lock_path = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
lock_sha = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
wave_path = 'docs/research/competitors/evidence/none-matched-40532555248/import/input.wav'
wave_sha = 'a9f5d6fad663dccaaf1a3a72487ae8653cac36b88c8d81e470a0702dc30ad805'
model_sha = '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'
model_url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin'
bundle_id = 'com.negentropi.RomaJustTalk'
cases = [
    'liveLightImportQueueUsesRealWhisperRecognition',
    'liveClarityImportQueueUsesRealWhisperRecognition',
    'liveLightRetranscriptionUsesRealWhisperRecognition',
    'liveClarityRetranscriptionUsesRealWhisperRecognition',
    'liveDictationPolishPipelineDeliversLiteralTextToTextEdit',
]
derived = repo / '.local-build'
package_checkouts = derived / 'SourcePackages'
roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'VoiceInkTests', 'iOS',
    driver_path, workflow_path, wave_path, 'Makefile', 'LocalBuild.xcconfig', 'scripts/run-writing-feature-regression.sh',
    'scripts/verify-static-whisper-xcframework.sh', 'scripts/verify-static-whisper-app.sh', 'scripts/verify-adhoc-macos-test-host.sh']


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


def classify(text, code):
    errors = []
    starts = re.findall(r'\bTest (\w+)\(\) started\.', text)
    if sorted(starts) != sorted(cases):
        errors.append('The exact five selected tests must each start once')
    results = {}
    for name in cases:
        results[name] = re.findall(r'\bTest ' + name + r'\(\) (passed|failed|skipped) after ', text)
        if results[name] != ['passed']:
            errors.append(name + ' must finish once and pass')
    summaries = re.findall(r'Test run with (\d+) tests? in (\d+) suites? (passed|failed)', text)
    if len(summaries) != 1 or summaries[0][0] != '5' or int(summaries[0][1]) <= 0 or summaries[0][2] != 'passed' or code != 0:
        errors.append('One five-test passed summary and exit zero are required')
    if re.search(r'\brecorded an issue\b|\bskipped\b|Test session ended prematurely|Testing cancelled|failed to launch|fatal error:|crashed', text, re.I):
        errors.append('Issues, skips, cancellation, crashes and launch errors cannot pass')
    return {'valid': not errors, 'classification': 'passed' if not errors else 'invalid-or-failed', 'exit_code': code,
        'starts': starts, 'results': results, 'summaries': [list(item) for item in summaries], 'errors': errors}


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


def provision(host):
    requirement = output / 'host-requirement.txt'
    requirement.write_text(host['designated_requirement'] + '\n')
    csreq = output / 'host.csreq'
    subprocess.run(['csreq', '-r', str(requirement), '-b', str(csreq)], check=True)
    requirement_hex = csreq.read_bytes().hex().upper()
    rows = []
    for service, database, prefix in [
        ('kTCCServiceAccessibility', '/Library/Application Support/com.apple.TCC/TCC.db', ['sudo']),
        ('kTCCServiceMicrophone', str(Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db'), [])]:
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','" + bundle_id + "',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
        subprocess.run([*prefix, 'sqlite3', database], input=statement, text=True, check=True)
        query = "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='" + bundle_id + "' AND service='" + service + "';"
        rows.extend(json.loads(subprocess.check_output([*prefix, 'sqlite3', '-json', database, query])))
    require(len(rows) == 2 and all(row['auth_value'] == 2 and row['requirement'] == requirement_hex for row in rows), 'Fresh TCC rows do not match exact signed host')
    write_json(output / 'tcc.json', rows)
    for command in [['killall', 'tccd'], ['sudo', 'killall', 'tccd']]:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['sleep', '2'], check=True)


def input_identity():
    inputs = output / 'inputs'
    model, audio = inputs / 'ggml-base.bin', inputs / 'input.wav'
    require(digest(model.read_bytes()) == model_sha and model.stat().st_size == 147951465, 'Model fixture bytes differ from the pinned base model')
    require(digest(audio.read_bytes()) == wave_sha and audio.stat().st_size == 165984, 'Audio differs from accepted committed WAV')
    with wave.open(str(audio), 'rb') as value:
        shape = {'channels': value.getnchannels(), 'rate': value.getframerate(), 'sample_width': value.getsampwidth(), 'frames': value.getnframes()}
    require(shape == {'channels': 1, 'rate': 16000, 'sample_width': 2, 'frames': 80944}, 'Pinned WAV shape differs')
    return {'model_path': str(model), 'model_source': model_url, 'model_sha256': model_sha, 'model_bytes': 147951465,
        'audio_path': str(audio), 'audio_source': wave_path, 'audio_sha256': wave_sha, 'audio_bytes': 165984, 'audio_shape': shape}


def configuration():
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
    home = output / 'isolated-user'
    preferences = home / 'Library/Preferences'
    preferences.mkdir(parents=True)
    seed = {'selectedAIProvider': 'Local CLI', 'CurrentTranscriptionModel': 'whisper-large-v3-turbo', 'PrewarmModelOnWake': False,
        'hasCompletedOnboarding': True, 'isAIEnhancementEnabled': False, 'IsAudioCleanupEnabled': False, 'IsTranscriptionCleanupEnabled': False,
        'enableAnnouncements': False}
    (preferences / (bundle_id + '.plist')).write_bytes(plistlib.dumps(seed))
    observations = output / 'observations'
    observations.mkdir()
    editor_observations = output / 'editor-observations'
    editor_observations.mkdir()
    flags = {'CFFIXED_USER_HOME': str(home), 'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
        'RJT_DICTATION_POLISH_LIVE_CHECKS': '1', 'RJT_LIVE_WRITING_TARGET_EVIDENCE': str(editor_observations),
        'RJT_DICTATION_POLISH_MODEL': str(output / 'inputs/ggml-base.bin'), 'RJT_DICTATION_POLISH_AUDIO': str(output / 'inputs/input.wav'),
        'RJT_DICTATION_POLISH_EVIDENCE': str(observations)}
    target.setdefault('EnvironmentVariables', {}).update(flags)
    # The spaced provider launch value became Local in NSArgumentDomain; use the isolated plist.
    arguments = [item for key, item_value in seed.items() if key != 'selectedAIProvider'
        for item in ['-' + key, 'YES' if item_value is True else 'NO' if item_value is False else item_value]]
    require('-selectedAIProvider' not in arguments and all(not any(character.isspace() for character in str(item)) for item in arguments),
        'Launch arguments must not shadow the isolated provider or contain a spaced value')
    require(plistlib.loads((preferences / (bundle_id + '.plist')).read_bytes())['selectedAIProvider'] == 'Local CLI',
        'The isolated persistent provider must retain its complete raw value')
    target['CommandLineArguments'], target['ParallelizationEnabled'] = arguments, False
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
        'seed_preferences': seed, 'command_line_arguments': arguments, 'environment': flags,
        'credential_contract': 'LOCAL_BUILD routes app KeychainService to fresh UserDefaults. Local CLI is selected before AI initialization. Source/configuration assurance, not SecItem tracing.'})
    return path


def enumerate_tests(directory, config, selected=()):
    directory.mkdir()
    run(['xcodebuild', 'test-without-building', '-xctestrun', str(config), '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
        *selected, '-enumerate-tests', '-test-enumeration-style', 'flat', '-test-enumeration-format', 'json',
        '-test-enumeration-output-path', str(directory / 'selected-tests.json')], directory / 'enumeration.log', timeout=180)
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


def close_native_hosts(seen, executable):
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
    open_code = subprocess.run(['lsof', '-n', '-P', '-Fpn', '--', executable], capture_output=True, text=True)
    require(open_code.returncode in (0, 1) and not open_code.stderr.strip() and not open_code.stdout.strip(), 'Exact native executable still has open descriptors after host exit')
    write_json(output / 'host-closed.json', {'valid': True, 'executable_path': executable, 'host_pids': sorted(seen),
        'observed_host_launches': sorted(seen.values(), key=lambda item: item['pid']), 'all_observed_hosts_exited': True,
        'exact_executable_census_empty': True, 'exact_executable_has_no_open_descriptors': True,
        'limits': 'Test-host closure only; this does not assert TextEdit window closure or microphone inactivity.'})


def run_native(command, executable):
    require(not host_census(executable), 'A native host was already using this exact freshly built executable')
    seen = {}
    deadline = time.monotonic() + 1200
    print('Running xcodebuild; log ' + str(output / 'tests.log'), flush=True)
    with (output / 'tests.log').open('xb') as stream:
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
                require(time.monotonic() < deadline, 'Exact five-case native run exceeded its bounded deadline')
                time.sleep(0.1)
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            close_native_hosts(seen, executable)
            raise
    require(seen, 'No actual signed native host was observed live with its mapped executable')
    write_json(output / 'host-live.json', {'executable_path': executable, 'hosts': sorted(seen.values(), key=lambda item: item['pid'])})
    close_native_hosts(seen, executable)
    return process.returncode, seen


def exact(lhs, rhs):
    return isinstance(lhs, str) and isinstance(rhs, str) and lhs.encode('utf-8') == rhs.encode('utf-8') and lhs.encode('utf-16-le') == rhs.encode('utf-16-le')


def valid_uuid(value):
    try:
        uuid.UUID(value)
        return isinstance(value, str)
    except (ValueError, TypeError, AttributeError):
        return False


def observation_errors(name, value, executable, processed_audio=None):
    errors = []
    def check(condition, message):
        if not condition:
            errors.append(name + ': ' + message)
    if not isinstance(value, dict):
        return [name + ': missing object receipt']
    check(value.get('version') == 1 and type(value.get('version')) is int and value.get('testName') == name and value.get('classification') == 'passed', 'wrong receipt identity or classification')
    check(value.get('bundleIdentifier') == bundle_id and value.get('executablePath') == executable and type(value.get('processIdentifier')) is int and value.get('processIdentifier', 0) > 0, 'wrong actual host identity')
    check(isinstance(value.get('sourcePath'), str) and Path(value['sourcePath']).name == Path(oracle_paths[1 if name == cases[-1] else 0]).name, 'wrong oracle source path')
    check(value.get('ownedCleanupCompleted') is True, 'owned cleanup did not finish')
    if name == cases[-1]:
        scenarios = value.get('scenarios')
        if not isinstance(scenarios, list) or [item.get('scenario') for item in scenarios if isinstance(item, dict)] != ['light', 'clarity-success', 'clarity-fallback']:
            return errors + [name + ': exactly three ordered native editor scenarios required']
        for index, scenario in enumerate(scenarios):
            check(scenario.get('profile') == ('light' if index == 0 else 'clarity'), 'wrong captured scenario profile')
            check(exact(scenario.get('observedDocument'), scenario.get('expectedDocument')), 'native editor differs in UTF-8 or UTF-16')
            selection = scenario.get('expectedSelection')
            valid_selection = isinstance(selection, dict) and set(selection) == {'location', 'length'} and all(type(item) is int and item >= 0 for item in selection.values())
            check(scenario.get('observedSelection') == selection and valid_selection and selection['length'] == 0, 'native editor selection differs or is not a valid collapsed range')
            check(all(scenario.get(key) is True for key in ['utf8Equal', 'utf16Equal', 'selectionEqual']), 'scenario postconditions missing')
            check(scenario.get('syntheticRecognitionCalls') == 1 and type(scenario.get('syntheticRecognitionCalls')) is int, 'exactly one controlled pipeline recognition required')
            check(scenario.get('warningCount') == (1 if index == 2 else 0) and type(scenario.get('warningCount')) is int, 'wrong pipeline warning count')
            check(scenario.get('actualCLIRequestCount') == (0 if index == 0 else 1) and type(scenario.get('actualCLIRequestCount')) is int, 'wrong actual Local CLI invocation count')
            check(valid_uuid(scenario.get('recordID')), 'missing actual saved record UUID')
            if index:
                check(scenario.get('requestFrozen') is True, 'captured Clarity request was not verified')
                child = scenario.get('childPID')
                check(type(child) is int and child > 0 and child != value.get('processIdentifier'), 'actual Local CLI child identity missing')
            reason = scenario.get('processingFailureReason')
            if index == 2:
                check(isinstance(reason, str) and bool(reason.strip()) and scenario.get('enhancedText') is None and exact(scenario.get('text'), scenario.get('recognitionText')), 'pipeline fallback must retain untouched recognition')
            else:
                check('processingFailureReason' in scenario and reason is None, 'unexpected pipeline cleanup failure')
        return errors
    clarity = name.startswith('liveClarity')
    fallback = name == cases[1]
    check(value.get('profile') == ('clarity' if clarity else 'light') and 'style' in value and value.get('style') == ('natural' if clarity else None), 'wrong captured profile/style')
    check(value.get('modelSHA256') == model_sha and value.get('audioSHA256') == wave_sha, 'wrong actual ASR fixture bytes')
    check(value.get('actualWhisperInferenceCount') == 1 and type(value.get('actualWhisperInferenceCount')) is int, 'exactly one actual Whisper inference required')
    raw = value.get('sameContextRecognition')
    check(isinstance(raw, str) and bool(raw.strip()) and {'quick', 'brown', 'fox'}.issubset(set(re.findall(r'[a-z]+', raw.lower()))), 'same-context recognition lacks fixture sanity words')
    check(exact(value.get('recognitionText'), raw) and value.get('sameContextRecognitionExact') is True, 'saved recognition differs from actual inference')
    check(exact(value.get('storedText'), value.get('expectedText')), 'saved prepared text differs from expected exact bytes')
    actual_enhanced, expected_enhanced = value.get('enhancedText'), value.get('expectedEnhancedText')
    check(('enhancedText' in value and 'expectedEnhancedText' in value) and (actual_enhanced is None and expected_enhanced is None or exact(actual_enhanced, expected_enhanced)), 'saved enhancement differs from expected exact bytes')
    check(value.get('utf8Equal') is True and value.get('utf16Equal') is True, 'exact code-unit checks missing')
    check(value.get('warningCount') == (1 if fallback else 0) and type(value.get('warningCount')) is int, 'wrong saved fallback warning count')
    check(value.get('actualCLIRequestCount') == (1 if clarity else 0) and type(value.get('actualCLIRequestCount')) is int, 'wrong actual file Local CLI invocation count')
    if clarity:
        child = value.get('childPID')
        check(type(child) is int and child > 0 and child != value.get('processIdentifier') and value.get('requestFrozen') is True, 'actual file Local CLI child or captured request missing')
    check(valid_uuid(value.get('recordID')), 'missing actual saved record UUID')
    permanent_url = value.get('permanentAudioURL')
    check(isinstance(permanent_url, str) and urlparse(permanent_url).scheme == 'file', 'missing actual retained WAV URL')
    check(isinstance(processed_audio, bytes) and bool(processed_audio) and digest(processed_audio) == value.get('permanentAudioSHA256'), 'retained processed WAV differs from actual saved audio hash')
    reason = value.get('processingFailureReason')
    if fallback:
        check(isinstance(reason, str) and bool(reason.strip()) and actual_enhanced is None and exact(value.get('storedText'), raw), 'Clarity import must retain untouched recognition and distinct failure')
    else:
        check('processingFailureReason' in value and reason is None, 'unexpected cleanup failure')
    if name == cases[3]:
        check(isinstance(actual_enhanced, str) and bool(actual_enhanced.strip()), 'successful Clarity retranscription must save decoded enhancement')
    return errors


def self_test():
    global derived, output
    original_derived, original_output = derived, output
    try:
        with tempfile.TemporaryDirectory(prefix='rjt-polish-configuration-') as temporary:
            output = Path(temporary) / 'proof'
            output.mkdir()
            derived = Path(temporary) / 'derived'
            products = derived / 'Build/Products'
            products.mkdir(parents=True)
            target = {'BlueprintName': 'VoiceInkTests', 'TestBundlePath': '__TESTROOT__/VoiceInkTests.xctest',
                'TestHostPath': '__TESTROOT__/roma just talk.app'}
            (products / 'fixture.xctestrun').write_bytes(plistlib.dumps({'TestConfigurations': [{'TestTargets': [target]}]}))
            configured = plistlib.loads(configuration().read_bytes())['TestConfigurations'][0]['TestTargets'][0]
            arguments = configured['CommandLineArguments']
            require('-selectedAIProvider' not in arguments and 'Local CLI' not in arguments and 'Local' not in arguments,
                'The configuration fixture still shadows the persistent provider')
            home = Path(configured['EnvironmentVariables']['CFFIXED_USER_HOME'])
            require(plistlib.loads((home / 'Library/Preferences' / (bundle_id + '.plist')).read_bytes())['selectedAIProvider'] == 'Local CLI',
                'The actual serialized configuration lost the complete persistent provider')
    finally:
        derived, output = original_derived, original_output
    good = ''.join('Test ' + name + '() started.\nTest ' + name + '() passed after 1.0 seconds.\n' for name in cases) + 'Test run with 5 tests in 1 suite passed after 5.0 seconds.\n'
    require(classify(good, 0)['valid'], 'Valid exact-five log rejected')
    bad = [good.replace(cases[0], 'wrong'), good.replace('with 5 tests', 'with 4 tests'), good.replace('passed after 1.0', 'skipped after 1.0', 1),
        good + 'Test extra() started.\n', good + 'Test ' + cases[0] + '() started.\n', good + 'Test recorded an issue: setup failed\n', good + 'fatal error: crash\n']
    require(all(not classify(value, 0)['valid'] for value in bad) and not classify(good, 65)['valid'], 'Invalid native result accepted')
    require(not exact('é', 'e\u0301') and exact('e\u0301 🧪\r\n', 'e\u0301 🧪\r\n'), 'Code-unit comparison is not exact')
    require(not valid_uuid(True) and not valid_uuid(None) and valid_uuid(str(uuid.uuid4())), 'UUID validation failed')
    executable = '/fixture/roma just talk.app/Contents/MacOS/roma just talk'
    def base(name):
        return {'version': 1, 'testName': name, 'classification': 'passed', 'bundleIdentifier': bundle_id, 'executablePath': executable,
            'processIdentifier': 123, 'sourcePath': oracle_paths[1 if name == cases[-1] else 0], 'ownedCleanupCompleted': True}
    valid = {}
    for name in cases[:-1]:
        clarity, fallback = name.startswith('liveClarity'), name == cases[1]
        raw = ' The quick Brown Fox 🧪 e\u0301'
        enhanced = 'Literal <tag> e\u0301 🧪\r\n' if name == cases[3] else None
        stored = raw if fallback else ' The quick Brown RJT-482 🧪 e\u0301'
        valid[name] = dict(base(name), profile='clarity' if clarity else 'light', style='natural' if clarity else None,
            modelSHA256=model_sha, audioSHA256=wave_sha, actualWhisperInferenceCount=1, sameContextRecognition=raw,
            recognitionText=raw, sameContextRecognitionExact=True, storedText=stored, expectedText=stored,
            enhancedText=enhanced, expectedEnhancedText=enhanced, utf8Equal=True, utf16Equal=True,
            warningCount=1 if fallback else 0, actualCLIRequestCount=1 if clarity else 0,
            childPID=456, requestFrozen=True,
            recordID=str(uuid.uuid4()), processingFailureReason='expected CLI failure' if fallback else None,
            permanentAudioURL='file:///fixture/saved.wav', permanentAudioSHA256=digest(b'fixture WAV bytes'))
    pipeline = base(cases[-1])
    pipeline['scenarios'] = [dict(scenario=name, profile='light' if index == 0 else 'clarity',
        expectedDocument='literal e\u0301 🧪\r\n', observedDocument='literal e\u0301 🧪\r\n',
        expectedSelection={'location': 0, 'length': 0}, observedSelection={'location': 0, 'length': 0},
        utf8Equal=True, utf16Equal=True, selectionEqual=True, syntheticRecognitionCalls=1,
        warningCount=1 if index == 2 else 0, actualCLIRequestCount=0 if index == 0 else 1,
        recordID=str(uuid.uuid4()), requestFrozen=True, childPID=456, recognitionText='raw', text='raw', enhancedText=None,
        processingFailureReason='expected CLI failure' if index == 2 else None) for index, name in enumerate(['light', 'clarity-success', 'clarity-fallback'])]
    valid[cases[-1]] = pipeline
    require(all(not observation_errors(name, value, executable, b'fixture WAV bytes') for name, value in valid.items()), 'Valid synthetic observation contract rejected')
    invalid = 0
    for name, value in valid.items():
        for key, mutation in [('classification', 'failed'), ('processIdentifier', True), ('bundleIdentifier', 'foreign'), ('sourcePath', '/foreign/wrong.swift'), ('ownedCleanupCompleted', False)]:
            require(observation_errors(name, dict(value, **{key: mutation}), executable, b'fixture WAV bytes'), 'Invalid host receipt accepted: ' + key)
            invalid += 1
    for key, mutation in [('modelSHA256', 'foreign'), ('actualWhisperInferenceCount', 0), ('actualWhisperInferenceCount', True),
        ('recognitionText', ' The quick Brown Fox 🧪 é'), ('sameContextRecognitionExact', False), ('storedText', 'changed'),
        ('enhancedText', ''), ('warningCount', 1), ('recordID', None), ('processingFailureReason', 'unexpected'),
        ('actualCLIRequestCount', 1), ('permanentAudioURL', 'https://foreign.test/audio'), ('permanentAudioSHA256', 'foreign')]:
        require(observation_errors(cases[0], dict(valid[cases[0]], **{key: mutation}), executable, b'fixture WAV bytes'), 'Invalid file observation accepted: ' + key)
        invalid += 1
    require(observation_errors(cases[1], dict(valid[cases[1]], warningCount=0), executable, b'fixture WAV bytes'), 'Missing fallback warning accepted')
    require(observation_errors(cases[0], valid[cases[0]], executable), 'Missing retained processed audio accepted')
    require(observation_errors(cases[-1], dict(pipeline, scenarios=pipeline['scenarios'][:2]), executable), 'Missing native scenario accepted')
    invalid += 3
    print(json.dumps({'classification': 'passed', 'valid_log': True, 'invalid_logs_rejected': len(bad) + 1,
        'valid_observations': len(valid), 'invalid_observations_rejected': invalid, 'exact_string_and_uuid_controls': True}))


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
        require(digest((repo / lock_path).read_bytes()) == lock_sha and digest((repo / wave_path).read_bytes()) == wave_sha, 'Canonical lock or accepted WAV differs')
        require(git(repo, 'rev-parse', 'HEAD').decode().strip() == os.environ['GITHUB_SHA'], 'GitHub head differs from actual source')
        for name in cases:
            source = (repo / oracle_paths[1 if name == cases[-1] else 0]).read_text()
            require(len(re.findall(r'\bfunc ' + name + r'\(\)', source)) == 1, 'Native method missing or duplicated: ' + name)
        write_json(output / 'source-before.json', manifest())
        write_json(output / 'contract.json', {'source_sha': git(repo, 'rev-parse', 'HEAD').decode().strip(), 'github_run_id': os.environ['GITHUB_RUN_ID'],
            'oracle_sha256': {path: digest((repo / path).read_bytes()) for path in oracle_paths}, 'tests': cases, 'lock_sha256': lock_sha,
            'canonical_pins': 41, 'scope': 'Four real synthetic-WAV Whisper file operations and three native TextEdit pipeline scenarios with controlled recognition and real synthetic Local CLI transport',
            'limits': ['No microphone or real-speaker proof.', 'Local CLI responses are deterministic fixtures, not model-quality evidence.', 'Native editor insertion applies only to the three pipeline scenarios.', 'No release, CloudKit or general editor compatibility claim.']})
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
        settings = json.loads((output / 'build-settings.json').read_text())
        host_settings = [value['buildSettings'] for value in settings if value.get('target') == 'VoiceInk']
        require(len(host_settings) == 1 and 'LOCAL_BUILD' in host_settings[0].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split(), 'Actual host build lacks LOCAL_BUILD credential isolation')
        expected = {'ENABLE_DEBUG_DYLIB': 'NO', 'ENABLE_PREVIEWS': 'NO', 'ENABLE_HARDENED_RUNTIME': 'YES'}
        actual = {key: host_settings[0].get(key) for key in expected}
        require(actual == expected, 'Resolved native app build settings differ from the frozen request')
        write_json(output / 'resolved-test-host-settings.json', {'target': 'VoiceInk', 'requested': expected, 'resolved': actual,
            'limits': 'Build settings only; actual ad-hoc CodeDirectory flags are retained and verified separately. No Hardened Runtime signature claim.'})
        run(['xcodebuild', 'build-for-testing', *arguments, '-only-testing:VoiceInkTests'], output / 'build.log')
        verify_source()
        require(package_identity() == packages and static_identity() == whisper, 'Dependency bytes changed during build')
        host = identity()
        run(['bash', 'scripts/verify-static-whisper-app.sh', host['app_path']], output / 'static-app.log')
        run(['bash', str(repo / 'scripts/verify-adhoc-macos-test-host.sh'), host['app_path'], str(output / 'test-host-signature')], output / 'signing.log')
        inputs = output / 'inputs'
        inputs.mkdir()
        (inputs / 'input.wav').write_bytes((repo / wave_path).read_bytes())
        run(['curl', '--location', '--fail', '--retry', '3', '--max-time', '600', '--output', str(inputs / 'ggml-base.bin'), model_url], output / 'model-download.log', timeout=630)
        input_snapshot = input_identity()
        write_json(output / 'inputs.json', input_snapshot)
        provision(host)
        config = configuration()
        config_sha = digest(config.read_bytes())
        enabled, disabled = enumerate_tests(output / 'discovery', config)
        requested = []
        for name in cases:
            matches = [identifier for identifier in enabled if identifier.endswith('/' + name + '()')]
            require(len(matches) == 1 and matches[0] not in disabled, 'Native method did not resolve once enabled: ' + name)
            requested.append(matches[0])
        selected = ['-only-testing:' + identifier for identifier in requested]
        narrow, inactive = enumerate_tests(output / 'selection', config, selected)
        require(sorted(narrow) == sorted(requested) and not set(requested).intersection(inactive), 'Narrow native selection differs from five methods')
        write_json(output / 'selection/receipt.json', {'valid': True, 'requested': requested, 'enabled': narrow, 'disabled': inactive})
        write_json(output / 'identity-before.json', host)
        code, seen_hosts = run_native(['xcodebuild', 'test-without-building', '-xctestrun', str(config), '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
            *selected, '-resultBundlePath', str(output / 'Native.xcresult')], host['executable_path'])
        write_json(output / 'exit.json', {'test_without_building_exit_code': code})
        write_json(output / 'identity-after.json', identity())
        require(host == identity() and digest(config.read_bytes()) == config_sha, 'Signed app, oracle binary or launch configuration changed')
        require(package_identity() == packages and static_identity() == whisper and input_identity() == input_snapshot, 'Dependencies or ASR fixture bytes changed during native execution')
        verify_source()
        write_json(output / 'source-after.json', manifest())
        verdict = classify((output / 'tests.log').read_text(errors='replace'), code)
        receipt_paths = sorted((output / 'observations').glob('*.json'))
        require(sorted(path.stem for path in receipt_paths) == sorted(cases), 'Exactly five per-method observation receipts are required')
        observations = {path.stem: json.loads(path.read_text()) for path in receipt_paths}
        for name, value in observations.items():
            verdict['errors'].extend([] if value.get('processIdentifier') in seen_hosts else [name + ': receipt host PID was not independently observed live with the exact mapped executable'])
            processed = output / 'observations' / (name + '.wav')
            verdict['errors'].extend(observation_errors(name, value, host['executable_path'], processed.read_bytes() if processed.is_file() else None))
        verdict['valid'] = not verdict['errors']
        verdict['classification'] = 'passed' if verdict['valid'] else 'invalid-or-failed'
        verdict['source_sha'] = contract()['source_sha']
        verdict['observation_sha256'] = {path.name: digest(path.read_bytes()) for path in receipt_paths}
        verdict['actual_whisper_file_operations'] = 4
        verdict['native_textedit_scenarios'] = 3
        write_json(output / 'result.json', verdict)
        require(verdict['valid'], 'Native acceptance did not satisfy the exact contract: ' + '; '.join(verdict['errors']))
    elif mode == 'verify':
        verify_source()
        result = json.loads((output / 'result.json').read_text())
        expected = classify((output / 'tests.log').read_text(errors='replace'), json.loads((output / 'exit.json').read_text())['test_without_building_exit_code'])
        before = json.loads((output / 'identity-before.json').read_text())
        require(before == json.loads((output / 'identity-after.json').read_text()) == identity(), 'Retained signed host/oracle identity changed')
        live = json.loads((output / 'host-live.json').read_text())
        closed = json.loads((output / 'host-closed.json').read_text())
        observed_pids = {item['pid'] for item in live['hosts']}
        require(closed['valid'] and closed['all_observed_hosts_exited'] and closed['exact_executable_census_empty'] and closed['exact_executable_has_no_open_descriptors'], 'Actual native host closure was not established')
        require(live['executable_path'] == closed['executable_path'] == before['executable_path'] and observed_pids == set(closed['host_pids']), 'Live and closed native host identities differ')
        require(not host_census(before['executable_path']) and all(process_identity(pid) is None for pid in observed_pids), 'Observed native host is still running or its PID was reused')
        require(package_identity() == json.loads((output / 'packages-before.json').read_text()) and static_identity() == json.loads((output / 'static-whisper-before.json').read_text()), 'Frozen dependencies changed')
        require(input_identity() == json.loads((output / 'inputs.json').read_text()), 'ASR fixtures changed')
        for name in cases:
            path = output / 'observations' / (name + '.json')
            observed = json.loads(path.read_text())
            require(observed.get('processIdentifier') in observed_pids, 'Method receipt host was not independently observed live')
            processed = output / 'observations' / (name + '.wav')
            expected['errors'].extend(observation_errors(name, observed, before['executable_path'], processed.read_bytes() if processed.is_file() else None))
            require(digest(path.read_bytes()) == result['observation_sha256'][path.name], 'Native observation changed')
        require(expected['valid'] and not expected['errors'] and result['valid'] and result['classification'] == 'passed', 'Retained native acceptance is invalid')
        write_json(output / 'complete-result.json', {'classification': 'passed', 'source_sha': contract()['source_sha'],
            'result_sha256': digest((output / 'result.json').read_bytes()), 'tests': cases, 'actual_whisper_file_operations': 4,
            'native_textedit_scenarios': 3, 'limits': contract()['limits']})
    else:
        raise RuntimeError('usage: run-dictation-polish-native-check.sh self-test | prepare | native | verify')
except BaseException as error:
    if output.is_dir() and mode != 'self-test':
        (output / ('failure-' + mode + '.json')).write_text(json.dumps({'mode': mode, 'classification': 'invalid-or-failed', 'error': str(error)}, indent=2) + '\n')
    raise
PY
