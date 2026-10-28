#!/usr/bin/env python3
"""Source-bound hosted observation of the unchanged language picker; no production fix."""
import contextlib
import copy
import hashlib
import json
import math
import os
import plistlib
import re
import shlex
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
lock_path = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
lock_sha = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
bundle_id = 'com.negentropi.RomaJustTalk'
fixture_paths = ['scripts/fixtures/LanguageSelectionProbeHost.swift', 'scripts/fixtures/LanguageSelectionProbeOracle.swift']
driver_paths = ['scripts/run-language-selection-probe.sh', 'scripts/verify-language-selection-probe.py',
    '.github/workflows/voiceink-language-selection-probe.yml']
build_roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'iOS', 'Makefile', 'LocalBuild.xcconfig']
roots = [*build_roots, *fixture_paths, *driver_paths, 'scripts/run-writing-feature-regression.sh',
    'scripts/verify-static-whisper-xcframework.sh', 'scripts/verify-static-whisper-app.sh',
    'scripts/verify-adhoc-macos-test-host.sh']
candidate = output / 'candidate'
derived = output / 'derived'
packages = repo / '.local-build/SourcePackages'
native = output / 'native'
cases = ['same-current-english', 'changed-japanese', 'changed-english']

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
        path.write_text(data)


def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def manifest():
    return {p.decode(): digest((repo / p.decode()).read_bytes())
        for p in git('ls-files', '-z', '--', *roots).split(b'\0') if p}


def contract():
    return json.loads((output / 'contract.json').read_text())


def verify_source():
    require(git('rev-parse', 'HEAD').decode().strip() == contract()['source_sha'], 'Pinned source head changed')
    require(manifest() == json.loads((output / 'source-before.json').read_text()), 'Frozen product/oracle inputs changed')
    require(not git('ls-files', '--others', '--exclude-standard', '-z', '--', *roots), 'Untracked source inputs exist')
    require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical lock changed')


def run(command, log, *, timeout=1800, cwd=None, stderr_log=None):
    print('Running ' + command[0] + '; log ' + str(log), flush=True)
    with log.open('xb') as stream, (stderr_log.open('xb') if stderr_log else contextlib.nullcontext(stream)) as errors:
        process = subprocess.Popen(command, cwd=cwd or repo, stdout=stream, stderr=errors, start_new_session=True)
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
    require(code == 0, 'Command failed (' + str(code) + '): ' + str(log))


def package_identity():
    pins = json.loads((repo / lock_path).read_text())['pins']
    expected = {pin['identity']: pin['state']['revision'] for pin in pins}
    require(len(pins) == len(expected) == 41, 'Exactly 41 canonical pins required')
    actual = {}
    for dependency in json.loads((packages / 'workspace-state.json').read_text())['object']['dependencies']:
        name = dependency['packageRef']['identity']
        if name not in expected:
            continue
        subpath = dependency['subpath']
        require(Path(subpath).name == subpath and subpath not in ('.', '..'), 'Unsafe dependency path')
        checkout = packages / 'checkouts' / subpath
        def depgit(*args):
            return subprocess.check_output(['git', '-C', str(checkout), *args])
        head = depgit('rev-parse', 'HEAD').decode().strip()
        require(name not in actual and head == dependency['state']['checkoutState']['revision'] == expected[name], 'Dependency pin differs: ' + name)
        require(not depgit('status', '--porcelain', '--untracked-files=normal', '--ignore-submodules=none'), 'Dirty dependency: ' + name)
        links = depgit('submodule', 'status', '--recursive').decode().splitlines()
        require(all(line.startswith(' ') for line in links), 'Missing/changed dependency Git link: ' + name)
        actual[name] = {'revision': head, 'tree': depgit('rev-parse', 'HEAD^{tree}').decode().strip(), 'recursive_gitlinks': links}
    require(set(actual) == set(expected), 'Canonical graph not fully checked out')
    return {'lock_sha256': lock_sha, 'packages': actual}


def static_identity():
    framework = Path.home() / 'VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework'
    require(framework.is_dir(), 'Static Whisper framework missing')
    return {str(p.relative_to(framework)): digest(p.read_bytes()) for p in sorted(framework.rglob('*')) if p.is_file()}


def export_candidate():
    candidate.mkdir()
    files = git('ls-files', '-s', '-z', '--', *build_roots).split(b'\0')
    for record in files:
        if not record:
            continue
        header, raw = record.split(b'\t', 1)
        bits, _sha, stage = header.decode().split()
        path = raw.decode()
        require(bits in ('100644', '100755') and stage == '0', 'Unsupported candidate file entry: ' + path)
        target = candidate / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((repo / path).read_bytes())
        target.chmod(0o755 if bits == '100755' else 0o644)
    for path, data in generated_sources().items():
        target = candidate / path
        require(not target.exists(), 'Generated fixture would overwrite product source')
        target.write_bytes(data)
    write_json(output / 'candidate-source.json', candidate_manifest())


def candidate_manifest():
    def generated_metadata(path):
        parts = path.relative_to(candidate).parts
        return parts[:2] == ('VoiceInk.xcodeproj', 'xcuserdata') or parts[:3] == ('VoiceInk.xcodeproj', 'project.xcworkspace', 'xcuserdata')
    return {str(p.relative_to(candidate)): digest(p.read_bytes()) for p in sorted(candidate.rglob('*'))
        if p.is_file() and not generated_metadata(p)}


def verify_candidate():
    before = json.loads((output / 'candidate-source.json').read_text())
    after = candidate_manifest()
    if after != before:
        value = {'classification': 'invalid-or-failed', 'mode': mode, 'cause': 'unknown; hash/path census only',
            'before': before, 'after': after,
            'added': {path: after[path] for path in sorted(after.keys() - before.keys())},
            'removed': {path: before[path] for path in sorted(before.keys() - after.keys())},
            'changed': {path: {'before': before[path], 'after': after[path]}
                for path in sorted(before.keys() & after.keys()) if before[path] != after[path]}}
        path = output / ('candidate-source-mismatch-' + mode + '.json')
        index = 1
        while path.exists() and json.loads(path.read_text()) != value:
            index += 1
            path = output / ('candidate-source-mismatch-' + mode + '-' + str(index) + '.json')
        write_json(path, value)
        raise RuntimeError('Disposable candidate source changed; inspect ' + str(path))


def build_arguments():
    return ['-project', str(candidate / 'VoiceInk.xcodeproj'), '-scheme', 'VoiceInk', '-configuration', 'Debug',
        '-destination', 'platform=macOS', '-derivedDataPath', str(derived), '-xcconfig', str(candidate / 'LocalBuild.xcconfig'),
        '-clonedSourcePackagesDirPath', str(packages), '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile',
        '-skipPackageUpdates', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_ALLOWED=YES', 'DEVELOPMENT_TEAM=',
        'CODE_SIGN_ENTITLEMENTS=' + str(candidate / 'VoiceInk/VoiceInk.local.entitlements'), 'ENABLE_DEBUG_DYLIB=NO',
        'ENABLE_PREVIEWS=NO', 'ENABLE_HARDENED_RUNTIME=YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD',
        'EXCLUDED_SOURCE_FILE_NAMES=VoiceInk.swift']


def identity():
    app = derived / 'Build/Products/Debug/roma just talk.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == bundle_id, 'Unexpected component host identity')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    signing = subprocess.run(['codesign', '-dr', '-', str(app)], check=True, capture_output=True, text=True)
    requirements = re.findall(r'^(?:# )?designated => (.+)$', signing.stdout + signing.stderr, re.M)
    require(len(requirements) == 1, 'Exact signed-host requirement unavailable')
    return {'app_path': str(app), 'executable_path': str(app / 'Contents/MacOS' / info['CFBundleExecutable']),
        'designated_requirement': requirements[0],
        'app_files_sha256': {str(p.relative_to(app)): digest(p.read_bytes()) for p in sorted(app.rglob('*')) if p.is_file()}}


def compile_inputs():
    expected = {str(p) for p in (candidate / 'VoiceInk').rglob('*.swift') if p.name != 'VoiceInk.swift'}
    raw_settings = (output / 'build-settings.json').read_bytes()
    targets = [item['buildSettings'] for item in json.loads(raw_settings) if item.get('target') == 'VoiceInk']
    require(len(targets) == 1, 'Exactly one actual VoiceInk compiler-settings target required')
    settings = targets[0]
    require(settings.get('TARGET_NAME') == settings.get('PRODUCT_MODULE_NAME') == 'VoiceInk'
        and settings.get('PRODUCT_BUNDLE_IDENTIFIER') == bundle_id and settings.get('SRCROOT') == str(candidate)
        and settings.get('PROJECT_FILE_PATH') == str(candidate / 'VoiceInk.xcodeproj'), 'Compiler settings belong to a different target/source tree')
    def resolved_path(key):
        value = settings.get(key)
        require(isinstance(value, str) and value and '$' not in value and '\n' not in value,
            'Missing/unresolved actual compiler path: ' + key)
        path = Path(value)
        require(path.is_absolute() and '..' not in path.parts and path.resolve() == path,
            'Unsafe/noncanonical actual compiler path: ' + key)
        return path
    objroot = resolved_path('OBJROOT')
    target_temp = resolved_path('TARGET_TEMP_DIR')
    objects = resolved_path('OBJECT_FILE_DIR_normal')
    require(objroot == derived / 'Build/Intermediates.noindex' and target_temp.is_relative_to(objroot)
        and target_temp.name == 'VoiceInk.build' and target_temp.parent.name == 'Debug'
        and objects == target_temp / 'Objects-normal', 'Compiler response namespace differs from the isolated app target')
    require(isinstance(settings.get('ARCHS'), str), 'Actual compiler architectures missing')
    architectures = settings['ARCHS'].split()
    require(bool(architectures) and len(architectures) == len(set(architectures))
        and all(re.fullmatch('[A-Za-z0-9_]+', arch) for arch in architectures), 'Missing/duplicate/unsafe actual compiler architectures')
    require({key for key in settings if key.startswith('SWIFT_RESPONSE_FILE_PATH_normal_')}
        == {'SWIFT_RESPONSE_FILE_PATH_normal_' + arch for arch in architectures}, 'Ambiguous architecture response-file settings')
    lists, identities = [], set()
    for arch in architectures:
        path = resolved_path('SWIFT_RESPONSE_FILE_PATH_normal_' + arch)
        require(path.parent == objects / arch and path.name.endswith('.SwiftFileList')
            and path.is_file() and not path.is_symlink(), 'Actual response file is missing or outside its target/architecture namespace')
        identity = (path.stat().st_dev, path.stat().st_ino)
        require(path not in lists and identity not in identities, 'Duplicate/ambiguous actual compiler response files')
        lists.append(path)
        identities.add(identity)
    generated = {}
    for path in lists:
        entries = shlex.split(path.read_text())
        extra = set(entries) - expected
        require(all(Path(p).is_relative_to(derived) and Path(p).name == 'GeneratedAssetSymbols.swift'
            and Path(p).parent.name == 'DerivedSources' for p in extra), 'Unexpected generated compiler source')
        generated.update({str(Path(p).relative_to(derived)): digest(Path(p).read_bytes()) for p in extra})
        require(len(entries) == len(set(entries)) and set(entries) - extra == expected,
            'Compiler inputs must contain every product Swift source plus fixtures, excluding only VoiceInk.swift')
    return {'excluded_source_files': ['VoiceInk.swift'], 'source_paths': sorted(str(Path(p).relative_to(candidate)) for p in expected),
        'build_settings_sha256': digest(raw_settings),
        'response_file_settings': {arch: str(path.relative_to(derived)) for arch, path in zip(architectures, lists)},
        'generated_asset_sources_sha256': generated,
        'swift_file_lists_sha256': {str(p.relative_to(derived)): digest(p.read_bytes()) for p in lists}}


def process_identity(pid):
    result = subprocess.run(['ps', '-p', str(pid), '-ww', '-o', 'lstart=,comm='], capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        return None
    fields = result.stdout.strip().split(None, 5)
    require(len(fields) == 6, 'Process launch identity unavailable')
    return {'started_at': ' '.join(fields[:5]), 'executable_path': fields[5]}


def host_census(executable):
    result = subprocess.run(['ps', '-axo', 'pid=,lstart=,comm=', '-ww'], capture_output=True, text=True, check=True)
    return [{'pid': int(fields[0]), 'started_at': ' '.join(fields[1:6]), 'executable_path': fields[6]}
        for line in result.stdout.splitlines() if len(fields := line.strip().split(None, 6)) == 7 and fields[6] == executable]


def tcc_rows():
    rows = []
    for service, database, prefix in tcc_services():
        query = "SELECT service,client,client_type,auth_value,hex(csreq) AS requirement FROM access WHERE client='" + bundle_id + "' AND service='" + service + "';"
        values = json.loads(subprocess.check_output([*prefix, 'sqlite3', '-json', database, query]) or b'[]')
        rows.extend(dict(row, database=database) for row in values)
    return sorted(rows, key=lambda item: (item['database'], item['service']))


def provision(host):
    requirement = output / 'host-requirement.txt'
    requirement.write_text(host['designated_requirement'] + '\n')
    csreq = output / 'host.csreq'
    subprocess.run(['csreq', '-r', str(requirement), '-b', str(csreq)], check=True)
    requirement_hex = csreq.read_bytes().hex().upper()
    write_json(output / 'tcc-preexisting.json', tcc_rows())
    for service, database, prefix in tcc_services():
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','" + bundle_id + "',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
        subprocess.run([*prefix, 'sqlite3', database], input=statement, text=True, check=True)
    for command in [['killall', 'tccd'], ['sudo', 'killall', 'tccd']]:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    rows = tcc_rows()
    expected = sorted([{'service': service, 'client': bundle_id, 'client_type': 0, 'auth_value': 2,
        'requirement': requirement_hex, 'database': database} for service, database, _ in tcc_services()],
        key=lambda item: (item['database'], item['service']))
    require(rows == expected, 'Fresh TCC rows differ from exact signed host')
    write_json(output / 'tcc-before.json', rows)
    return rows


def run_host(host):
    native.mkdir()
    home = output / 'isolated-user'
    preferences = home / 'Library/Preferences'
    preferences.mkdir(parents=True)
    seed = {'PrewarmModelOnWake': False, 'hasCompletedOnboarding': True,
        'isAIEnhancementEnabled': False, 'enableAnnouncements': False, 'SUEnableAutomaticChecks': False}
    (preferences / (bundle_id + '.plist')).write_bytes(plistlib.dumps(seed))
    profile_path = native / 'profile-%p.profraw'
    environment = dict(os.environ, CFFIXED_USER_HOME=str(home), RJT_LANGUAGE_SELECTION_PROBE='1',
        RJT_LANGUAGE_SELECTION_EVIDENCE=str(native), LLVM_PROFILE_FILE=str(profile_path))
    write_json(output / 'configuration.json', {'executable_path': host['executable_path'], 'seed_preferences': seed,
        'CFFIXED_USER_HOME': str(home), 'RJT_LANGUAGE_SELECTION_EVIDENCE': str(native), 'command_line_arguments': [],
        'RJT_LANGUAGE_SELECTION_PROBE': '1', 'LLVM_PROFILE_FILE': str(profile_path), 'working_directory': str(native),
        'scope': 'Unchanged language picker component; production entry excluded; no engine, provider, ASR or model loading.'})
    executable = host['executable_path']
    require(not host_census(executable), 'Fresh exact host executable already running')
    observed, launched = None, None
    monitor_error, closure_error, candidate_error = None, None, None
    census_empty, descriptors_closed = None, None
    with (output / 'host.log').open('xb') as stream:
        process = subprocess.Popen([executable], cwd=native, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 120
            while True:
                if process.poll() is not None:
                    break
                current = process_identity(process.pid)
                if current is None and process.poll() is not None and observed is not None:
                    break
                require(current is not None and current['executable_path'] == executable, 'Host process identity changed')
                if launched is None:
                    launched = current
                require(current == launched, 'Spawned host process launch identity changed')
                if observed is None:
                    result = subprocess.run(['lsof', '-n', '-P', '-a', '-p', str(process.pid), '-d', 'txt', '-Fn'], capture_output=True, text=True)
                    require(result.returncode in (0, 1) and not result.stderr.strip(), 'Mapped code inspection failed')
                    paths = [line[1:] for line in result.stdout.splitlines() if line.startswith('n')]
                    if executable in paths:
                        observed = dict(current, pid=process.pid, mapped_text_paths=paths)
                elif current != {key: observed[key] for key in ('started_at', 'executable_path')}:
                    raise RuntimeError('Host PID reused')
                if time.monotonic() >= deadline:
                    # Capture the proven spawned process before timeout cleanup, never a name-matched PID.
                    require(launched == current, 'Refusing to sample a changed host process')
                    with (output / 'host-timeout-sample.log').open('xb') as diagnostic:
                        try:
                            sampled = subprocess.run(['/usr/bin/sample', str(process.pid), '3', '-mayDie',
                                '-file', str(native / 'host-timeout-sample.txt')],
                                stdout=diagnostic, stderr=subprocess.STDOUT, timeout=10)
                            write_json(output / 'host-timeout-sample.json', {'host': dict(current, pid=process.pid),
                                'exit_code': sampled.returncode, 'scope': 'External sample of the proven spawned host on timeout'})
                        except subprocess.TimeoutExpired:
                            write_json(output / 'host-timeout-sample.json', {'host': dict(current, pid=process.pid),
                                'classification': 'diagnostic-timeout'})
                    raise RuntimeError('Language host exceeded bounded deadline')
                time.sleep(0.1)
        except BaseException as error:
            monitor_error = str(error) or type(error).__name__
        finally:
            try:
                if process.poll() is None:
                    current = process_identity(process.pid)
                    if current is not None or process.poll() is None:
                        require(launched is not None and current == launched, 'Refusing to terminate unproven or reused spawned-host identity')
                        process.terminate()
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            require(process_identity(process.pid) == current, 'Refusing to kill reused host PID')
                            process.kill()
                            process.wait()
                census_empty = not host_census(executable)
                require(census_empty, 'Exact host executable remains running')
                result = subprocess.run(['lsof', '-n', '-P', '-Fpn', '--', executable], capture_output=True, text=True)
                descriptors_closed = result.returncode in (0, 1) and not result.stderr.strip() and not result.stdout.strip()
                require(descriptors_closed, 'Exact host executable still mapped/open')
            except BaseException as error:
                closure_error = str(error) or type(error).__name__
            write_json(output / 'host-live.json', {'host': observed, 'spawned_identity': launched, 'exit_code': process.returncode})
            write_json(output / 'host-closed.json', {'valid': closure_error is None, 'host': observed,
                'exact_executable_census_empty': census_empty, 'exact_executable_has_no_open_descriptors': descriptors_closed,
                'error': closure_error})
    try:
        verify_candidate()
    except BaseException as error:
        candidate_error = str(error) or type(error).__name__
    receipt_path = native / 'result.json'
    try:
        receipt = json.loads(receipt_path.read_text()) if receipt_path.is_file() else {}
        require(isinstance(receipt, dict), 'Native result must be an object')
    except (OSError, ValueError, TypeError) as error:
        receipt = {'failure': 'Unreadable native result: ' + str(error)}
    native_failure, native_issues = receipt.get('failure'), receipt.get('issues', [])
    valid = process.returncode in (0, 1) and observed is not None and receipt.get('completed') is True
    valid = valid and not any((monitor_error, closure_error, candidate_error, native_failure, native_issues))
    write_json(output / 'host-outcome.json', {'classification': 'valid-observation' if valid else 'invalid',
        'exit_code': process.returncode, 'mapped_host_observed': observed is not None, 'native_failure': native_failure,
        'native_issues': native_issues, 'monitor_error': monitor_error, 'closure_error': closure_error,
        'candidate_error': candidate_error, 'observed_completed_cases': receipt.get('executedCases', [])})
    if native_failure or native_issues:
        raise RuntimeError('Language host oracle invalid (exit ' + str(process.returncode) + '): ' + str(native_failure or native_issues)
            + '; inspect host-outcome.json for secondary diagnostics')
    require(process.returncode in (0, 1), 'Language host exited with code ' + str(process.returncode) + '; inspect host.log and host-outcome.json')
    require(monitor_error is None, 'Language host monitor failed: ' + str(monitor_error))
    require(observed is not None, 'No mapped live host observed')
    require(closure_error is None, 'Language host closure failed: ' + str(closure_error))
    require(candidate_error is None, 'Language host candidate changed: ' + str(candidate_error))
    return observed


def generated_sources():
    return {'VoiceInk/' + Path(path).name: (repo / path).read_bytes() for path in fixture_paths}


def tcc_services():
    system = '/Library/Application Support/com.apple.TCC/TCC.db'
    user = str(Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db')
    return [('kTCCServiceAccessibility', system, ['sudo']),
        ('kTCCServiceScreenCapture', system, ['sudo']), ('kTCCServiceScreenCapture', user, [])]


def receipt_errors(value, executable, pid, expected_home):
    """Validate actual AX and domain observations; do not trust declared pass flags."""
    errors = []
    def check(condition, message):
        if not condition:
            errors.append(message)
    def typed(item, expected):
        return item == ({'type': 'missing'} if expected is None else {'type': 'string', 'value': expected})
    def preferences(item, persisted, effective):
        check(isinstance(item, dict), 'Missing preference observation')
        if not isinstance(item, dict):
            return
        check(typed(item.get('persistent'), persisted) and typed(item.get('cfPersistent'), persisted), 'Persistent language differs')
        check(typed(item.get('registered'), 'en'), 'Registered English changed')
        check(typed(item.get('argument'), None), 'Language argument override exists')
        check(item.get('cfSynchronizeSucceeded') is True, 'CF preference synchronization failed')
        check(typed(item.get('effective'), effective), 'Effective language differs')
    def light(item, language, expected):
        check(isinstance(item, dict), 'Missing fresh Light observation')
        if not isinstance(item, dict):
            return
        check(typed(item.get('capturedLanguage'), language), 'Light did not capture strict persistent language')
        check(item.get('input') == item.get('recognitionText') == 'Um, send it tomorrow.', 'Light recognition input changed')
        check(item.get('output') == item.get('preparedText') == expected, 'Unexpected Light processing result')
        check(all(item.get(key) is True for key in ['emptySnippets', 'emptyReplacementRules', 'noEnhancement', 'noFallback']),
            'Light used other libraries, enhancement or fallback')
    def descriptor(item, role):
        check(isinstance(item, dict), 'Missing actual AX descriptor')
        if not isinstance(item, dict):
            return
        check(item.get('role') in role, 'Unexpected AX role')
        check(item.get('enabled') is True and item.get('actionsAXError') == 0
            and isinstance(item.get('actions'), list) and 'AXPress' in item['actions'], 'Actual enabled AXPress unavailable')
        frame = item.get('frame', {})
        check(isinstance(frame, dict) and set(frame) == {'x', 'y', 'width', 'height'}
            and all(type(n) in (int, float) and math.isfinite(n) and abs(n) < 100000 for n in frame.values())
            and frame.get('width', 0) > 0 and frame.get('height', 0) > 0, 'Invalid actual AX bounds')
    def selection(item, label):
        return isinstance(item, dict) and label in [item.get('title'), item.get('description'), item.get('value', {}).get('value') if isinstance(item.get('value'), dict) else item.get('value')]
    check(isinstance(value, dict), 'Native result must be an object')
    if not isinstance(value, dict):
        return errors
    check(value.get('schemaVersion') == 1 and value.get('completed') is True, 'Native observation incomplete')
    check(value.get('host') == {'pid': pid, 'bundleIdentifier': bundle_id, 'executablePath': executable}, 'Mapped host differs')
    environment = value.get('environment', {})
    check(environment.get('expectedUserHome') == environment.get('observedUserHome') == expected_home
        and environment.get('homeMatchesExpected') is True, 'Isolated preference home differs')
    check(environment.get('arguments') == [] and environment.get('hasLanguageArgumentOverride') is False, 'Unexpected arguments/override')
    model = value.get('model', {})
    check(model.get('name') == 'ggml-tiny' and model.get('provider') == 'Whisper'
        and model.get('isMultilingual') is True and model.get('shouldShowPicker') is True
        and model.get('englishLabel') == 'English' and model.get('japaneseLabel') == 'Japanese'
        and model.get('modelLoaded') is False and model.get('contextAbsent') is True
        and type(model.get('availableModelCount')) is int and model['availableModelCount'] == 0, 'Real multilingual model facts differ')
    check(value.get('finalModelState') == {'modelLoaded': False, 'contextAbsent': True}, 'Model unexpectedly loaded during observation')
    check(value.get('selectedCases') == value.get('executedCases') == cases, 'Missing/extra/reordered cases')
    baseline = value.get('baseline', {})
    preferences(baseline.get('preferences'), None, 'en')
    light(baseline.get('light'), None, 'Um, send it tomorrow.')
    entries = value.get('cases', [])
    check(isinstance(entries, list) and len(entries) == 3, 'Expected all three picker observations')
    if not isinstance(entries, list) or len(entries) != 3:
        return errors
    primary = value.get('primaryPersisted')
    check(type(primary) is bool, 'Missing actual primary persistence outcome')
    persisted = 'en' if primary else None
    transitions = [(None, 'en', persisted, 'en'), (persisted, 'en', 'ja', 'ja'), ('ja', 'ja', 'en', 'en')]
    for index, item in enumerate(entries):
        before_p, before_e, after_p, after_e = transitions[index]
        code, label = ('ja', 'Japanese') if index == 1 else ('en', 'English')
        check(item.get('id') == cases[index] and item.get('requestedCode') == code
            and item.get('requestedLabel') == label and item.get('wasCurrent') is (index == 0), 'Wrong selection case')
        before, after = item.get('before', {}), item.get('after', {})
        preferences(before.get('preferences'), before_p, before_e)
        preferences(after.get('preferences'), after_p, after_e)
        light(before.get('light'), before_p, 'send it tomorrow.' if before_p == 'en' else 'Um, send it tomorrow.')
        light(after.get('light'), after_p, 'send it tomorrow.' if after_p == 'en' else 'Um, send it tomorrow.')
        action = item.get('action', {})
        picker, menu_item, result_picker = action.get('pickerBefore'), action.get('menuItemBefore'), action.get('pickerAfter')
        descriptor(picker, ['AXPopUpButton', 'AXComboBox'])
        descriptor(menu_item, ['AXMenuItem'])
        descriptor(result_picker, ['AXPopUpButton', 'AXComboBox'])
        check(selection(menu_item, label), 'Wrong actual menu item label')
        check(selection(picker, 'Japanese' if before_e == 'ja' else 'English')
            and selection(result_picker, label), 'Actual picker value does not match transition')
        checked = action.get('menuCheckedEvidence', {})
        check(isinstance(checked, dict) and type(checked.get('checked')) is bool, 'Missing actual selected-item evidence')
        if index == 0:
            check(checked.get('checked') is True and
                ((checked.get('markChar', {}).get('type') == 'string' and bool(checked['markChar'].get('value')))
                    or checked.get('selected') == {'type': 'boolean', 'value': True}
                    or checked.get('value') in [{'type': 'boolean', 'value': True}, {'type': 'number', 'value': 1}]),
                'Primary English item was not observably current')
        check(action.get('menuIsPickerDescendant') is True, 'Open menu not bound to actual picker')
        check(type(action.get('pressAXError')) is int and action['pressAXError'] == 0
            and action.get('menuDismissed') is True, 'Actual menu press/dismissal failed')
        check(item.get('passed') is (bool(primary) if index == 0 else True), 'Declared case result differs from observations')
    expected_classification = 'passed' if primary else 'same-selection-not-persisted'
    check(value.get('classification') == expected_classification and value.get('exitCode') == (0 if primary else 1),
        'Classification/exit does not match actual persistence')
    check(value.get('positiveControlsPassed') is True and value.get('issues') == [] and value.get('failure') is None,
        'Positive controls or native setup failed')
    return errors


def classify_native(host, live):
    receipt = json.loads((native / 'result.json').read_text())
    configuration = json.loads((output / 'configuration.json').read_text())
    errors = receipt_errors(receipt, host['executable_path'], live['pid'], configuration['CFFIXED_USER_HOME'])
    screenshots = ['baseline.png'] + [case + suffix for case in cases for suffix in ['-menu.png', '-after.png']]
    for name in screenshots:
        path = native / name
        if not path.is_file():
            errors.append('Missing actual screenshot: ' + name)
            continue
        raw = path.read_bytes()
        if len(raw) < 24 or raw[:8] != b'\x89PNG\r\n\x1a\n' or min(struct.unpack('>II', raw[16:24])) < 100:
            errors.append('Invalid actual screenshot: ' + name)
    for name in ['baseline-hierarchy.json'] + [case + suffix for case in cases for suffix in ['-menu-hierarchy.json', '-after-hierarchy.json']]:
        path = native / name
        if not path.is_file() or not isinstance(json.loads(path.read_text()), list):
            errors.append('Missing actual AX hierarchy: ' + name)
    return {'valid': not errors, 'classification': receipt.get('classification') if not errors else 'invalid',
        'errors': errors, 'primary_persisted': receipt.get('primaryPersisted'),
        'native_receipt_sha256': digest((native / 'result.json').read_bytes())}


def self_test():
    # Fabricated receipts calibrate rejection only; they are never native UI evidence.
    typed = lambda value: {'type': 'missing'} if value is None else {'type': 'string', 'value': value}
    def prefs(persistent, effective):
        return {'persistent': typed(persistent), 'cfPersistent': typed(persistent), 'registered': typed('en'),
            'argument': typed(None), 'effective': typed(effective), 'cfSynchronizeSucceeded': True}
    def light(language):
        result = 'send it tomorrow.' if language == 'en' else 'Um, send it tomorrow.'
        return {'capturedLanguage': typed(language), 'input': 'Um, send it tomorrow.',
            'recognitionText': 'Um, send it tomorrow.', 'output': result, 'preparedText': result,
            'emptySnippets': True, 'emptyReplacementRules': True, 'noEnhancement': True, 'noFallback': True}
    def observed(persistent, effective):
        return {'preferences': prefs(persistent, effective), 'light': light(persistent)}
    def ax(role, label):
        return {'role': role, 'title': label, 'description': '', 'value': typed(label), 'enabled': True,
            'actionsAXError': 0, 'actions': ['AXPress'], 'frame': {'x': 10, 'y': 20, 'width': 120, 'height': 24}}
    def sample(primary):
        persisted = 'en' if primary else None
        result = {'schemaVersion': 1, 'completed': True, 'host': {'pid': 42, 'bundleIdentifier': bundle_id, 'executablePath': '/fixture/host'},
            'environment': {'expectedUserHome': '/fixture/home', 'observedUserHome': '/fixture/home',
                'homeMatchesExpected': True, 'arguments': [], 'hasLanguageArgumentOverride': False},
            'model': {'name': 'ggml-tiny', 'provider': 'Whisper', 'isMultilingual': True,
                'shouldShowPicker': True, 'englishLabel': 'English', 'japaneseLabel': 'Japanese', 'modelLoaded': False, 'contextAbsent': True, 'availableModelCount': 0},
            'finalModelState': {'modelLoaded': False, 'contextAbsent': True},
            'selectedCases': cases[:], 'executedCases': cases[:], 'baseline': observed(None, 'en'),
            'primaryPersisted': primary, 'positiveControlsPassed': True, 'classification': 'passed' if primary else 'same-selection-not-persisted',
            'exitCode': 0 if primary else 1, 'failure': None, 'issues': [], 'cases': []}
        for index, (before_p, before_e, after_p, after_e) in enumerate([(None, 'en', persisted, 'en'), (persisted, 'en', 'ja', 'ja'), ('ja', 'ja', 'en', 'en')]):
            label, code = ('Japanese', 'ja') if index == 1 else ('English', 'en')
            result['cases'].append({'id': cases[index], 'requestedCode': code, 'requestedLabel': label,
                'wasCurrent': index == 0, 'before': observed(before_p, before_e), 'after': observed(after_p, after_e),
                'passed': primary if index == 0 else True, 'action': {'pickerBefore': ax('AXPopUpButton', 'Japanese' if before_e == 'ja' else 'English'),
                    'menuItemBefore': ax('AXMenuItem', label), 'pickerAfter': ax('AXPopUpButton', label),
                    'menuCheckedEvidence': {'markChar': typed('✓') if index == 0 else typed(None),
                        'selected': {'type': 'boolean', 'value': index == 0}, 'value': typed(None), 'checked': index == 0},
                    'pressAXError': 0, 'menuDismissed': True, 'menuIsPickerDescendant': True}})
        return result
    total = 0
    for primary in (True, False):
        valid = sample(primary)
        require(not receipt_errors(valid, '/fixture/host', 42, '/fixture/home'), 'Valid classifier sample rejected')
        mutations = [
            lambda v: v['host'].update(pid=43),
            lambda v: v['environment'].update(arguments=['-SelectedLanguage', 'en']),
            lambda v: v['baseline']['preferences'].update(persistent=typed('en')),
            lambda v: v['baseline']['preferences'].update(cfPersistent=typed('en')),
            lambda v: v['model'].update(name='fake-model'),
            lambda v: v['model'].update(modelLoaded=True),
            lambda v: v['finalModelState'].update(contextAbsent=False),
            lambda v: v['baseline']['preferences'].update(cfSynchronizeSucceeded=False),
            lambda v: v['cases'][0]['action'].update(menuIsPickerDescendant=False),
            lambda v: v['cases'][0]['action']['menuCheckedEvidence'].update(markChar=typed(None), selected={'type': 'boolean', 'value': False}, value=typed(None)),
            lambda v: v['cases'][0]['action'].update(pressAXError=1),
            lambda v: v['cases'][0]['action'].update(menuDismissed=False),
            lambda v: v['cases'][1]['after']['preferences'].update(persistent=typed('en')),
            lambda v: v['cases'][2]['after']['light'].update(output='Um, send it tomorrow.'),
            lambda v: v.update(executedCases=cases[:1]),
            lambda v: v.update(classification='passed' if not primary else 'same-selection-not-persisted'),
            lambda v: v.update(exitCode=2),
        ]
        for mutation in mutations:
            broken = copy.deepcopy(valid)
            mutation(broken)
            require(bool(receipt_errors(broken, '/fixture/host', 42, '/fixture/home')), 'Broken classifier receipt accepted')
            total += 1
    print(json.dumps({'classification': 'classifier-self-test-passed', 'accepted_calibration_shapes': 2,
        'rejected_mutations': total, 'native_UI_execution': False}))


def main():
    if mode == 'self-test':
        self_test()
        return
    require(mode in ('prepare', 'native', 'verify'), 'usage: language probe self-test | prepare | native | verify')
    if mode == 'prepare':
        output.mkdir(exist_ok=False)
        require(not git('status', '--porcelain', '--untracked-files=normal', '--', *roots), 'Commit probe source inputs first')
        require(git('rev-parse', 'HEAD').decode().strip() == os.environ['GITHUB_SHA'], 'Exact GitHub source head differs')
        require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical package lock differs')
        write_json(output / 'source-before.json', manifest())
        write_json(output / 'contract.json', {'source_sha': git('rev-parse', 'HEAD').decode().strip(),
            'github_run_id': os.environ['GITHUB_RUN_ID'], 'cases': cases, 'lock_sha256': lock_sha,
            'canonical_pins': 41, 'excluded_source_files': ['VoiceInk.swift'],
            'generated_sources_sha256': {path: digest(data) for path, data in generated_sources().items()},
            'language_view_sha256': digest((repo / 'VoiceInk/Views/AI Models/LanguageSelectionView.swift').read_bytes()),
            'scope': 'Observe same-current English selection through unchanged LanguageSelectionView.full and real model metadata.',
            'limits': ['Normal app composition excluded; no engine, ASR, inference, model download, provider or physical input.',
                'Persistent transition is behavioral evidence; no private setter instrumentation or direct call counter.',
                'A valid primary non-persistence result is a reproduced issue, not invalid test setup.']})
        for path in fixture_paths:
            write = output / 'source' / Path(path).name
            write.parent.mkdir(parents=True, exist_ok=True)
            write.write_bytes((repo / path).read_bytes())
        export_candidate()
        run(['bash', 'scripts/run-writing-feature-regression.sh', 'packages', str(output / 'packages'), '', '', str(packages)], output / 'packages.log')
        for command, name in [(['sw_vers'], 'sw-vers.txt'), (['xcodebuild', '-version'], 'xcode-version.txt'), (['swift', '--version'], 'swift-version.txt')]:
            run(command, output / name)
        verify_source()
        verify_candidate()
        return
    verify_source()
    verify_candidate()
    if mode == 'native':
        package_state, whisper = package_identity(), static_identity()
        write_json(output / 'packages-before.json', package_state)
        write_json(output / 'static-whisper-before.json', whisper)
        arguments = build_arguments()
        write_json(output / 'build-command.json', {'arguments': arguments, 'action': 'build'})
        run(['xcodebuild', '-showBuildSettings', '-json', *arguments], output / 'build-settings.json', timeout=180,
            cwd=candidate, stderr_log=output / 'build-settings-errors.log')
        settings = [item['buildSettings'] for item in json.loads((output / 'build-settings.json').read_text()) if item.get('target') == 'VoiceInk']
        require(len(settings) == 1 and settings[0].get('EXCLUDED_SOURCE_FILE_NAMES') == 'VoiceInk.swift'
            and 'LOCAL_BUILD' in settings[0].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split(), 'Actual probe composition differs')
        run(['xcodebuild', 'build', *arguments], output / 'build.log', cwd=candidate)
        write_json(output / 'compile-inputs.json', compile_inputs())
        verify_source()
        verify_candidate()
        require(package_identity() == package_state and static_identity() == whisper, 'Dependencies changed during build')
        host = identity()
        write_json(output / 'identity-before.json', host)
        run(['bash', 'scripts/verify-static-whisper-app.sh', host['app_path']], output / 'static-app.log')
        run(['bash', 'scripts/verify-adhoc-macos-test-host.sh', host['app_path'], str(output / 'signature')], output / 'signing.log')
        provision(host)
        live = run_host(host)
        write_json(output / 'tcc-after.json', tcc_rows())
        require(tcc_rows() == json.loads((output / 'tcc-before.json').read_text()), 'Signed TCC rows changed')
        require(host == identity() and package_state == package_identity() and whisper == static_identity(), 'Signed app/dependencies changed')
        verify_source()
        verify_candidate()
        classification = classify_native(host, live)
        write_json(output / 'native-classification.json', classification)
        write_json(output / 'identity-after.json', identity())
        write_json(output / 'source-after.json', manifest())
        write_json(output / 'result.json', {'classification': classification['classification'], 'valid': classification['valid'],
            'source_sha': contract()['source_sha'], 'cases': cases, 'native_receipt_sha256': classification['native_receipt_sha256'],
            'classification_sha256': digest((output / 'native-classification.json').read_bytes()), 'limits': contract()['limits']})
        require(classification['valid'], 'Native probe invalid: ' + '; '.join(classification['errors']))
        raise SystemExit(0 if classification['primary_persisted'] else 1)
    host = json.loads((output / 'identity-before.json').read_text())
    live = json.loads((output / 'host-live.json').read_text())
    closed = json.loads((output / 'host-closed.json').read_text())
    require(host == json.loads((output / 'identity-after.json').read_text()) == identity(), 'Retained signed host changed')
    require(compile_inputs() == json.loads((output / 'compile-inputs.json').read_text()), 'Actual compiler input census changed')
    require(package_identity() == json.loads((output / 'packages-before.json').read_text())
        and static_identity() == json.loads((output / 'static-whisper-before.json').read_text()), 'Frozen dependencies changed')
    require(tcc_rows() == json.loads((output / 'tcc-before.json').read_text()) == json.loads((output / 'tcc-after.json').read_text()), 'Frozen signed TCC changed')
    require(closed['valid'] is True and closed['host'] == live['host'] and closed['exact_executable_census_empty'] is True
        and closed['exact_executable_has_no_open_descriptors'] is True and not host_census(host['executable_path']), 'Host closure invalid')
    require(live['spawned_identity'] == {key: live['host'][key] for key in ('started_at', 'executable_path')}, 'Spawned/mapped identity differs')
    actual = classify_native(host, live['host'])
    require(actual['valid'] and actual == json.loads((output / 'native-classification.json').read_text()), 'Retained native classification invalid')
    require(live['exit_code'] == (0 if actual['primary_persisted'] else 1), 'Actual native exit differs')
    write_json(output / 'complete-result.json', {'classification': actual['classification'], 'valid': True,
        'source_sha': contract()['source_sha'], 'cases': cases, 'native_receipt_sha256': actual['native_receipt_sha256'],
        'limits': contract()['limits']})
    raise SystemExit(0 if actual['primary_persisted'] else 1)


try:
    main()
except SystemExit:
    raise
except BaseException as error:
    try:
        if output.is_dir() and mode != 'self-test':
            write_json(output / ('failure-' + mode + '.json'), {'mode': mode, 'classification': 'invalid', 'error': str(error)})
    except Exception as receipt_error:
        print('Could not retain invalid-probe diagnostic: ' + str(receipt_error), file=sys.stderr)
    print('Language selection probe invalid: ' + str(error), file=sys.stderr)
    raise SystemExit(2)
