#!/usr/bin/env python3
"""Source-bound disposable Mac acceptance for unchanged Undo controls."""
import ast
import contextlib
import copy
import hashlib
import json
import os
import plistlib
import re
import shlex
import signal
import subprocess
import struct
import sys
import tempfile
import time
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
lock_path = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
lock_sha = 'bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f'
bundle_id = 'com.negentropi.RomaJustTalk'
fixture_paths = ['scripts/fixtures/WritingUndoControlHost.swift', 'scripts/fixtures/WritingUndoControlOracle.swift']
helper_path = 'VoiceInkTests/WritingTargetLiveTests.swift'
driver_paths = ['scripts/run-writing-undo-controls-check.sh', 'scripts/verify-writing-undo-controls.py',
    '.github/workflows/voiceink-writing-undo-controls-check.yml']
build_roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'iOS', 'Makefile', 'LocalBuild.xcconfig']
roots = [*build_roots, helper_path, *fixture_paths, *driver_paths, 'scripts/run-writing-feature-regression.sh',
    'scripts/verify-static-whisper-xcframework.sh', 'scripts/verify-static-whisper-app.sh',
    'scripts/verify-adhoc-macos-test-host.sh']
candidate = output / 'candidate'
derived = output / 'derived'
packages = repo / '.local-build/SourcePackages'
native = output / 'native'
cases = ['textedit-menu', 'textedit-shortcut', 'safari-menu', 'safari-shortcut']
prefix, passage, suffix = 'Before 👩🏽‍💻 ', 'target e\u0301', ' after 🧑‍🚀.\n'
original = prefix + passage + suffix
replacement_menu = 'Longer 👩🏽‍💻 e\u0301\nRJT, 台灣, 🧑‍🚀.'
replacement_shortcut = 'Short e\u0301 😀'
restored_message = 'Restored the original text and selection.'
busy_message = "RJT is busy right now, so Undo didn't replace any text."
refused_message = "The edited field changed or isn't focused, so Undo didn't replace any text."


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


def generated_sources():
    result = {('VoiceInk/' + Path(path).name): (repo / path).read_bytes() for path in fixture_paths}
    source = (repo / helper_path).read_bytes()
    marker = b'private enum LiveWritingFailure:'
    require(source.count(marker) == 1, 'Editor helper extraction boundary changed')
    # The existing native editor helper remains byte-identical after these imports.
    result['VoiceInk/LiveWritingEditor.swift'] = b'import AppKit\nimport Carbon.HIToolbox\nimport Foundation\n\n' + source[source.index(marker):]
    return result


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
    require(candidate_manifest() == json.loads((output / 'candidate-source.json').read_text()), 'Disposable candidate source changed')


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


def tcc_services():
    system = '/Library/Application Support/com.apple.TCC/TCC.db'
    user = str(Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db')
    return [(service, system, ['sudo']) for service in ('kTCCServiceAccessibility', 'kTCCServiceListenEvent',
        'kTCCServicePostEvent', 'kTCCServiceScreenCapture')] + [('kTCCServiceScreenCapture', user, [])]


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
    seed = {'selectedAIProvider': 'Local CLI', 'PrewarmModelOnWake': False, 'hasCompletedOnboarding': True,
        'isAIEnhancementEnabled': False, 'IsAudioCleanupEnabled': False, 'IsTranscriptionCleanupEnabled': False,
        'enableAnnouncements': False, 'SUEnableAutomaticChecks': False, 'restoreClipboardAfterPaste': True,
        'clipboardRestoreDelay': 2.0}
    (preferences / (bundle_id + '.plist')).write_bytes(plistlib.dumps(seed))
    environment = dict(os.environ, CFFIXED_USER_HOME=str(home), RJT_UNDO_CONTROLS_CHECKS='1', RJT_UNDO_CONTROLS_EVIDENCE=str(native),
        RJT_LIVE_WRITING_TARGET_EVIDENCE=str(native / 'editor-observations'), RJT_LIVE_WRITING_TARGET_CHECKS='1')
    write_json(output / 'configuration.json', {'executable_path': host['executable_path'], 'seed_preferences': seed,
        'CFFIXED_USER_HOME': str(home), 'RJT_UNDO_CONTROLS_EVIDENCE': str(native), 'command_line_arguments': [],
        'RJT_UNDO_CONTROLS_CHECKS': '1',
        'scope': 'One isolated component host; VoiceInkApp entry point excluded; no provider, recording, ASR or model loading.'})
    executable = host['executable_path']
    require(not host_census(executable), 'Fresh exact host executable already running')
    observed, launched = None, None
    with (output / 'host.log').open('xb') as stream:
        process = subprocess.Popen([executable], cwd=candidate, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 900
            while process.poll() is None:
                current = process_identity(process.pid)
                if current is None and process.poll() == 0 and observed is not None:
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
                require(time.monotonic() < deadline, 'Control host exceeded bounded deadline')
                time.sleep(0.1)
            require(process.returncode == 0 and observed is not None, 'Host failed or no mapped live host observed')
        finally:
            if process.poll() is None:
                current = process_identity(process.pid)
                require(launched is not None and current == launched, 'Refusing to terminate unproven or reused spawned-host identity')
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    require(process_identity(process.pid) == current, 'Refusing to kill reused host PID')
                    process.kill()
                    process.wait()
            write_json(output / 'host-live.json', {'host': observed, 'spawned_identity': launched, 'exit_code': process.returncode})
    require(not host_census(executable), 'Exact host executable remains running')
    result = subprocess.run(['lsof', '-n', '-P', '-Fpn', '--', executable], capture_output=True, text=True)
    require(result.returncode in (0, 1) and not result.stderr.strip() and not result.stdout.strip(), 'Exact host executable still mapped/open')
    write_json(output / 'host-closed.json', {'valid': True, 'host': observed, 'exact_executable_census_empty': True, 'exact_executable_has_no_open_descriptors': True})
    return observed


def units(value):
    data = value.encode('utf-16-le')
    return list(struct.unpack('<' + 'H' * (len(data) // 2), data))


def exact_range(location, length):
    return {'location': location, 'length': length}


def receipt_errors(value, executable, pid):
    """Recompute the oracle, including normalization-sensitive text and ranges."""
    errors = []
    def check(condition, message):
        if not condition:
            errors.append(message)
    def control(item, identifier, roles, enabled=True, actionable=True):
        check(isinstance(item, dict), 'Control is missing')
        if not isinstance(item, dict):
            return
        check(item.get('id') == identifier and item.get('role') in roles, 'Actual control identity/role differs: ' + identifier)
        check(item.get('enabled') is enabled, 'Control enabled state differs: ' + identifier)
        frame = item.get('frame', {})
        check(isinstance(frame, dict) and set(frame) == {'x', 'y', 'width', 'height'}
            and all(type(v) in (int, float) and abs(v) < 100000 for v in frame.values())
            and frame.get('width', 0) > 0 and frame.get('height', 0) > 0, 'Actual control frame invalid: ' + identifier)
        check(type(item.get('actionsAXError')) is int and item['actionsAXError'] == 0
            and isinstance(item.get('actions'), list) and all(isinstance(action, str) for action in item['actions']),
            'AX action inventory failed: ' + identifier)
        if actionable:
            check('AXPress' in item.get('actions', []), 'Control has no genuine AXPress: ' + identifier)
    def menu(item, enabled):
        control(item, 'undoLastWritingEdit.menuCommand', ['AXMenuItem', 'AXButton'], enabled)
        check(item.get('kind') == 'product-menu', 'Wrong product menu boundary')
        status = item.get('statusControl', {})
        control(status, status.get('id', ''), ['AXMenuBarItem', 'AXButton'])
        check(status.get('id') == 'undoControlHost.statusItem' or status.get('label') == 'RJT Undo check', 'Wrong actual status control')
    def notice(item, message):
        check(isinstance(item, dict) and item.get('id') == 'undoLastWritingEdit.notice'
            and item.get('expectedMessage') == message and message in (item.get('label'), item.get('value')),
            'Actual passive notice differs: ' + message)
    def snapshot(item, text, selected_range, bundle, focused=True):
        expected = units(text)
        start, length = selected_range['location'], selected_range['length']
        check(isinstance(item, dict), 'Missing editor snapshot')
        if not isinstance(item, dict):
            return
        check(item.get('valueUTF16') == expected and item.get('range') == selected_range
            and item.get('selectedTextUTF16') == expected[start:start + length], 'Exact editor value/selection differs')
        check(isinstance(item.get('range'), dict) and set(item['range']) == {'location', 'length'}
            and all(type(number) is int for number in item['range'].values())
            and all(isinstance(item.get(key), list) and all(type(unit) is int for unit in item[key])
                for key in ('valueUTF16', 'selectedTextUTF16')), 'Editor code units/range must contain integers')
        check(item.get('sameFocusedEditor') is focused and type(item.get('sameProcess')) is bool,
            'Focused editor/process observation missing or differs')
        if focused:
            check(item.get('sameProcess') is True, 'Product command changed foreground process')
        check(all(item.get(key) is True for key in ('sameWindow', 'windowPresent', 'targetAlive')), 'Live window/editor identity failed')
        check(type(item.get('pid')) is int and item['pid'] > 0 and item.get('bundleIdentifier') == bundle, 'Editor process identity invalid')
        check(item.get('usesSystemPaste') is (bundle == 'com.apple.Safari'), 'Observed native editor route policy differs')
        check(isinstance(item.get('token'), str) and re.fullmatch(r'RJT-Writing-Live-[0-9A-Fa-f-]{36}', item['token']) is not None,
            'Owned editor token missing')
    try:
        check(isinstance(value, dict) and type(value.get('schemaVersion')) is int and value['schemaVersion'] == 1
            and value.get('completed') is True, 'Missing completed schema-1 receipt')
        check(value.get('selectedCases') == cases and value.get('executedCases') == cases, 'Exact selected/executed control cases differ')
        check(value.get('host') == {'pid': pid, 'bundleIdentifier': bundle_id, 'executablePath': executable}, 'Observed host differs from exact mapped executable')
        check(value.get('runtimeBounds') == {'productMenuOrShortcut': True, 'normalAppComposition': False, 'fullPipeline': False,
            'ASR': False, 'provider': False} and all(type(item) is bool for item in value['runtimeBounds'].values()), 'Component/bridge scope differs')
        check(value.get('issues') == [] and 'failure' in value and value['failure'] is None, 'Oracle/helper reported issues or failure')
        check(value.get('forwardBoundary') == 'Real WritingTarget delivery into the sole engine-owned controller', 'Forward delivery boundary differs')
        check(value.get('pastePreferences') == {'restoreClipboardAfterPaste': True, 'clipboardRestoreDelay': 2.0,
            'hasArgumentOverrides': False} and value['pastePreferences']['restoreClipboardAfterPaste'] is True
            and value['pastePreferences']['hasArgumentOverrides'] is False, 'Actual persistent clipboard policy differs')
        shortcut = value.get('shortcut', {})
        check(shortcut.get('recordedViaActualRecorder') is True and shortcut.get('keyCode') == 32
            and shortcut.get('modifierFlagsRawValue') == 1835008 and bool(shortcut.get('displayString')), 'Actual configured recorder chord differs')
        control(shortcut.get('recorderControl'), 'shortcutRecorder.undoLastWritingEdit', ['AXButton'])
        records = value.get('cases', [])
        check(isinstance(records, list) and [item.get('id') for item in records] == cases, 'Four exact ordered case records required')
        selected = exact_range(len(units(prefix)), len(units(passage)))
        for item in records:
            name = item['id']
            is_menu = name.endswith('-menu')
            editor = 'textedit' if name.startswith('textedit-') else 'safari'
            bundle = 'com.apple.TextEdit' if editor == 'textedit' else 'com.apple.Safari'
            replacement = replacement_menu if is_menu else replacement_shortcut
            result = prefix + replacement + suffix
            caret = exact_range(len(units(prefix + replacement)), 0)
            check(item.get('editor') == editor and item.get('commandKind') == ('menu' if is_menu else 'shortcut'), 'Wrong editor/command case')
            check(type(item.get('forwardAttempts')) is int and item['forwardAttempts'] == 1
                and type(item.get('forwardConfirmations')) is int and item['forwardConfirmations'] == 1, 'Forward was not confirmed once')
            check(item.get('originalUTF16') == units(original) and item.get('resultUTF16') == units(result)
                and item.get('originalRange') == selected, 'Claimed before/result oracle differs')
            snapshot(item.get('before'), original, selected, bundle)
            snapshot(item.get('forward'), result, caret, bundle)
            snapshot(item.get('restored'), original, selected, bundle)
            check(len({(item[key]['pid'], item[key]['token']) for key in ('before', 'forward', 'restored')}) == 1,
                'Product command switched captured process/document')
            if is_menu:
                menu(item.get('command', {}), True)
            else:
                check(item.get('command') == {'kind': 'configured-global-shortcut', 'keyCode': 32,
                    'modifierFlagsRawValue': 1835008, 'nativeEventsPosted': 2}, 'Actual registered shortcut invocation differs')
            notice(item.get('notice'), restored_message)
            check(item.get('noticeWasAbsentBeforeCommand') is True, 'A stale product notice could satisfy the new command')
            check(item.get('capabilityConsumed') is True and item.get('screenshots') == [name + '-forward.png', name + '-restored.png'],
                'Capability consumption or exact capture names differ')
        states = value.get('stateChecks', {})
        check(set(states) == {'unavailable', 'busy', 'focusRefusal'} and all(item.get('passed') is True for item in states.values()), 'Three exact control states must pass')
        menu(states['unavailable']['menu'], False)
        busy = states['busy']
        menu(busy['menu'], False)
        check(busy.get('recordingStateFixture') == 'busy' and busy.get('capabilityRetained') is True, 'Busy component guard did not retain capability')
        notice(busy.get('notice'), busy_message)
        snapshot(busy.get('observed'), prefix + replacement_shortcut + suffix, exact_range(len(units(prefix + replacement_shortcut)), 0), 'com.apple.TextEdit')
        check(busy['observed'] == records[1]['forward'], 'Busy shortcut changed editor state or identity')
        focus = states['focusRefusal']
        check(focus.get('capabilityRetired') is True and focus.get('differentWindow') is True, 'Focus refusal failed to retire authority')
        notice(focus.get('notice'), refused_message)
        replacement = 'Source remains e\u0301 🧪'
        snapshot(focus.get('sourceAfter'), prefix + replacement + suffix, exact_range(len(units(prefix + replacement)), 0), 'com.apple.TextEdit', False)
        for key in ('otherBefore', 'otherAfter'):
            snapshot(focus.get(key), original, selected, 'com.apple.TextEdit')
        check(focus['otherBefore'] == focus['otherAfter'] and focus['sourceAfter']['token'] != focus['otherAfter']['token'],
            'Refusal changed destination or reused the source surface')
        tokens = [item['before']['token'] for item in records] + [focus['sourceAfter']['token'], focus['otherAfter']['token']]
        check(len(tokens) == len(set(tokens)) == 6, 'Six separately owned native editor fixtures required')
    except (TypeError, KeyError, AttributeError, ValueError) as error:
        errors.append('Malformed receipt: ' + str(error))
    return errors


def classify_native(host, live):
    value = json.loads((native / 'result.json').read_text())
    errors = receipt_errors(value, host['executable_path'], live['pid'])
    screenshots = [name + suffix for name in cases for suffix in ('-forward.png', '-restored.png')]
    screenshots += ['unavailable-menu.png', 'busy-menu.png', 'busy-shortcut-refused.png', 'shortcut-configured.png',
        'focus-refusal.png', 'textedit-menu-menu.png', 'safari-menu-menu.png']
    hashes = {}
    for name in screenshots:
        path = native / name
        if not path.is_file() or path.is_symlink():
            errors.append('Missing actual screenshot: ' + name)
            continue
        data = path.read_bytes()
        if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR' or min(struct.unpack('>II', data[16:24])) <= 0:
            errors.append('Invalid actual screenshot: ' + name)
        hashes[name] = digest(data)
    hierarchies = ['unavailable-menu', 'busy-menu', 'shortcut-configured', 'textedit-menu-menu', 'safari-menu-menu',
        *[name + '-restored' for name in cases]]
    for name in hierarchies:
        path = native / (name + '-hierarchy.json')
        if not path.is_file() or path.is_symlink():
            errors.append('Missing actual native hierarchy: ' + name)
            continue
        hierarchy = json.loads(path.read_text())
        if not isinstance(hierarchy, list) or not hierarchy or not all(isinstance(node, dict) and isinstance(node.get('role'), str) for node in hierarchy):
            errors.append('Invalid actual native hierarchy: ' + name)
        hashes[path.name] = digest(path.read_bytes())
    if not errors:
        owned = [item['before'] for item in value['cases']] + [value['stateChecks']['focusRefusal'][key] for key in ('sourceAfter', 'otherAfter')]
        for item in owned:
            for suffix in ('fixture-startup', 'cleanup'):
                path = native / 'editor-observations' / (item['token'] + '-' + suffix + '.json')
                if not path.is_file() or path.is_symlink():
                    errors.append('Missing editor lifetime receipt: ' + path.name)
                    continue
                observation = json.loads(path.read_text())
                valid = observation.get('token') == item['token'] and observation.get('bundleIdentifier') == item['bundleIdentifier']
                valid = valid and observation.get('processIdentifier') == item['pid']
                valid = valid and (observation.get('finalStage') == 'ready' and observation.get('failure') is None
                    if suffix == 'fixture-startup' else observation.get('expected') == 'owned surface closed')
                if not valid:
                    errors.append('Editor lifetime receipt failed: ' + path.name)
                hashes[path.name] = digest(path.read_bytes())
    return {'valid': not errors, 'classification': 'passed' if not errors else 'invalid-or-failed', 'errors': errors,
        'cases': cases, 'native_receipt_sha256': digest((native / 'result.json').read_bytes()), 'evidence_sha256': hashes}


def self_test():
    # This tests the acceptance classifier only; it creates no native success evidence.
    def control(identifier, role='AXButton', enabled=True):
        return {'id': identifier, 'role': role, 'enabled': enabled, 'label': '', 'value': '', 'actions': ['AXPress'],
            'actionsAXError': 0, 'frame': {'x': 1, 'y': 2, 'width': 100, 'height': 22}}
    def menu(enabled=True):
        return dict(control('undoLastWritingEdit.menuCommand', 'AXMenuItem', enabled), kind='product-menu',
            statusControl=control('undoControlHost.statusItem', 'AXMenuBarItem'))
    def notice(message):
        return dict(control('undoLastWritingEdit.notice'), expectedMessage=message, label=message)
    def snapshot(text, selected, bundle, token='RJT-Writing-Live-00000000-0000-4000-8000-000000000001', focused=True):
        data = units(text)
        return {'valueUTF16': data, 'range': selected, 'selectedTextUTF16': data[selected['location']:selected['location'] + selected['length']],
            'sameProcess': True, 'sameFocusedEditor': focused, 'sameWindow': True, 'windowPresent': True, 'targetAlive': True,
            'pid': 100, 'bundleIdentifier': bundle, 'token': token, 'usesSystemPaste': bundle == 'com.apple.Safari'}
    selected = exact_range(len(units(prefix)), len(units(passage)))
    value = {'schemaVersion': 1, 'completed': True, 'selectedCases': cases, 'executedCases': cases,
        'host': {'pid': 42, 'bundleIdentifier': bundle_id, 'executablePath': '/fixture/app'},
        'runtimeBounds': {'productMenuOrShortcut': True, 'normalAppComposition': False, 'fullPipeline': False, 'ASR': False, 'provider': False},
        'forwardBoundary': 'Real WritingTarget delivery into the sole engine-owned controller',
        'pastePreferences': {'restoreClipboardAfterPaste': True, 'clipboardRestoreDelay': 2.0, 'hasArgumentOverrides': False},
        'issues': [], 'failure': None, 'shortcut': {'recordedViaActualRecorder': True, 'keyCode': 32, 'modifierFlagsRawValue': 1835008,
            'displayString': 'fixture', 'recorderControl': control('shortcutRecorder.undoLastWritingEdit')}, 'cases': []}
    for name in cases:
        is_menu = name.endswith('-menu')
        replacement = replacement_menu if is_menu else replacement_shortcut
        bundle = 'com.apple.TextEdit' if name.startswith('textedit') else 'com.apple.Safari'
        result = prefix + replacement + suffix
        token = 'RJT-Writing-Live-00000000-0000-4000-8000-' + str(len(value['cases']) + 1).zfill(12)
        value['cases'].append({'id': name, 'editor': 'textedit' if name.startswith('textedit') else 'safari',
            'commandKind': 'menu' if is_menu else 'shortcut', 'forwardAttempts': 1, 'forwardConfirmations': 1,
            'originalUTF16': units(original), 'resultUTF16': units(result), 'originalRange': selected,
            'before': snapshot(original, selected, bundle, token), 'forward': snapshot(result, exact_range(len(units(prefix + replacement)), 0), bundle, token),
            'restored': snapshot(original, selected, bundle, token), 'command': menu() if is_menu else {'kind': 'configured-global-shortcut',
                'keyCode': 32, 'modifierFlagsRawValue': 1835008, 'nativeEventsPosted': 2}, 'notice': notice(restored_message),
            'capabilityConsumed': True, 'noticeWasAbsentBeforeCommand': True,
            'screenshots': [name + '-forward.png', name + '-restored.png']})
    value['stateChecks'] = {'unavailable': {'passed': True, 'menu': menu(False)},
        'busy': {'passed': True, 'recordingStateFixture': 'busy', 'menu': menu(False), 'notice': notice(busy_message),
            'observed': copy.deepcopy(value['cases'][1]['forward']), 'capabilityRetained': True},
        'focusRefusal': {'passed': True, 'capabilityRetired': True, 'differentWindow': True, 'notice': notice(refused_message),
            'sourceAfter': snapshot(prefix + 'Source remains e\u0301 🧪' + suffix, exact_range(len(units(prefix + 'Source remains e\u0301 🧪')), 0), 'com.apple.TextEdit', 'RJT-Writing-Live-00000000-0000-4000-8000-000000000005', focused=False),
            'otherBefore': snapshot(original, selected, 'com.apple.TextEdit', 'RJT-Writing-Live-00000000-0000-4000-8000-000000000006'),
            'otherAfter': snapshot(original, selected, 'com.apple.TextEdit', 'RJT-Writing-Live-00000000-0000-4000-8000-000000000006')}}
    require(not receipt_errors(value, '/fixture/app', 42), 'Valid classifier fixture rejected')
    mutations = [lambda v: v.update(completed=False), lambda v: v['selectedCases'].pop(), lambda v: v['cases'].pop(),
        lambda v: v['host'].update(pid=99), lambda v: v['runtimeBounds'].update(normalAppComposition=True),
        lambda v: v['shortcut'].update(recordedViaActualRecorder=False), lambda v: v['shortcut']['recorderControl'].update(actions=[]),
        lambda v: v['cases'][0]['command'].update(role='AXGroup'), lambda v: v['cases'][0]['command'].update(enabled=False),
        lambda v: v['cases'][0].update(forwardAttempts=2), lambda v: v['cases'][0]['restored'].update(valueUTF16=units('wrong')),
        lambda v: v['cases'][1]['forward'].update(valueUTF16=units(prefix + 'Short é 😀' + suffix)),
        lambda v: v['cases'][0]['restored'].update(sameFocusedEditor=False), lambda v: v['cases'][0]['restored'].update(token='foreign'),
        lambda v: v['cases'][2]['forward'].update(usesSystemPaste=False),
        lambda v: v['cases'][0].update(noticeWasAbsentBeforeCommand=False),
        lambda v: v['pastePreferences'].update(hasArgumentOverrides=True),
        lambda v: v['cases'][0]['notice'].update(label='invented'), lambda v: v['stateChecks']['busy'].update(capabilityRetained=False),
        lambda v: v['stateChecks']['focusRefusal'].update(differentWindow=False), lambda v: v['issues'].append('cleanup failed'),
        lambda v: v.update(failure='setup failure')]
    for mutation in mutations:
        invalid = copy.deepcopy(value)
        mutation(invalid)
        require(receipt_errors(invalid, '/fixture/app', 42), 'Malformed acceptance fixture incorrectly passed')
    print('Undo controls classifier passed: four exact cases and three states; ' + str(len(mutations))
        + ' malformed receipts rejected. No app, clipboard or native interaction executed.')
    compiler_inputs_self_test()


def compiler_inputs_self_test():
    # The actual failed 40605378801 build resolved a product-named response file.
    # Run the historical owning function against this same metadata/path fixture.
    historical = git('show', '794fa2595f943ae501bbe3407a9dd1120c678f76:scripts/verify-writing-undo-controls.py').decode()
    functions = [node for node in ast.parse(historical).body if isinstance(node, ast.FunctionDef) and node.name == 'compile_inputs']
    require(len(functions) == 1, 'Known-bad compiler-input function missing/ambiguous')
    old_namespace = dict(globals())
    exec(compile(ast.Module(body=functions, type_ignores=[]), '<794fa259 compile_inputs>', 'exec'), old_namespace)
    current_globals = globals()
    saved = {key: current_globals[key] for key in ('candidate', 'derived', 'output')}
    with tempfile.TemporaryDirectory(prefix='rjt-undo-compiler-inputs-') as directory:
        fixture = Path(directory).resolve()
        current_globals.update(output=fixture, candidate=fixture / 'candidate', derived=fixture / 'derived')
        old_namespace.update(output=current_globals['output'], candidate=current_globals['candidate'], derived=current_globals['derived'])
        try:
            source_paths = ['VoiceInk.swift', 'Engine.swift', 'Views/AI Models/Editor.swift', 'WritingUndoControlHost.swift', 'WritingUndoControlOracle.swift']
            for relative in source_paths:
                path = candidate / 'VoiceInk' / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('// compiler-input fixture only\n')
            target_temp = derived / 'Build/Intermediates.noindex/VoiceInk.build/Debug/VoiceInk.build'
            response = target_temp / 'Objects-normal/arm64/roma just talk.SwiftFileList'
            response.parent.mkdir(parents=True)
            generated = target_temp / 'DerivedSources/GeneratedAssetSymbols.swift'
            generated.parent.mkdir()
            generated.write_text('// Xcode asset symbol fixture only\n')
            expected_entries = [str(candidate / 'VoiceInk' / path) for path in source_paths if path != 'VoiceInk.swift'] + [str(generated)]
            original_list = '\n'.join(shlex.quote(path) for path in expected_entries) + '\n'
            response.write_text(original_list)
            settings = {'target': 'VoiceInk', 'buildSettings': {'TARGET_NAME': 'VoiceInk', 'PRODUCT_MODULE_NAME': 'VoiceInk',
                'PRODUCT_NAME': 'roma just talk', 'PRODUCT_BUNDLE_IDENTIFIER': bundle_id, 'SRCROOT': str(candidate),
                'PROJECT_FILE_PATH': str(candidate / 'VoiceInk.xcodeproj'), 'OBJROOT': str(derived / 'Build/Intermediates.noindex'),
                'TARGET_TEMP_DIR': str(target_temp), 'OBJECT_FILE_DIR_normal': str(target_temp / 'Objects-normal'), 'ARCHS': 'arm64',
                'SWIFT_RESPONSE_FILE_PATH_normal_arm64': str(response)}}
            def write_settings(value):
                (output / 'build-settings.json').write_text(json.dumps(value))
            write_settings([settings])
            try:
                old_namespace['compile_inputs']()
            except RuntimeError as error:
                require(str(error) == 'Actual Swift compiler input list unavailable', 'Known-bad function failed outside the observed filename defect')
                print('RED 794fa259 actual compile_inputs: Actual Swift compiler input list unavailable (product-named path with spaces).')
            else:
                raise RuntimeError('Known-bad compile_inputs accepted the observed failed-run fixture; regression invalid')
            result = compile_inputs()
            require(result['source_paths'] == sorted(str(Path(path).relative_to(candidate)) for path in expected_entries if path != str(generated))
                and result['response_file_settings'] == {'arm64': str(response.relative_to(derived))}, 'Candidate did not validate exact actual response path/source inputs')
            print('GREEN candidate compile_inputs: actual SWIFT_RESPONSE_FILE_PATH_normal_arm64 resolved; exact sources and sole main exclusion preserved.')
            bad_settings = []
            bad = copy.deepcopy(settings); bad['target'] = 'VoiceInkTests'; bad_settings.append([bad])
            bad_settings.append([settings, settings])
            bad = copy.deepcopy(settings); bad['buildSettings']['SWIFT_RESPONSE_FILE_PATH_normal_arm64'] = str(fixture / 'foreign.SwiftFileList'); bad_settings.append([bad])
            bad = copy.deepcopy(settings); bad['buildSettings']['ARCHS'] = 'arm64 arm64'; bad_settings.append([bad])
            bad = copy.deepcopy(settings); bad['buildSettings']['SWIFT_RESPONSE_FILE_PATH_normal_arm64'] = str(response.parent / '..' / 'arm64' / response.name); bad_settings.append([bad])
            alias = target_temp / 'Objects-normal/x86_64' / response.name
            alias.parent.mkdir()
            os.link(response, alias)
            bad = copy.deepcopy(settings); bad['buildSettings'].update(ARCHS='arm64 x86_64', SWIFT_RESPONSE_FILE_PATH_normal_x86_64=str(alias)); bad_settings.append([bad])
            for value in bad_settings:
                write_settings(value)
                try:
                    compile_inputs()
                except RuntimeError:
                    pass
                else:
                    raise RuntimeError('Invalid compiler target/response namespace accepted')
            write_settings([settings])
            bad_lists = [original_list + shlex.quote(expected_entries[0]) + '\n',
                '\n'.join(shlex.quote(path) for path in expected_entries[1:]) + '\n',
                original_list + shlex.quote(str(candidate / 'VoiceInk/VoiceInk.swift')) + '\n']
            for value in bad_lists:
                response.write_text(value)
                try:
                    compile_inputs()
                except RuntimeError:
                    pass
                else:
                    raise RuntimeError('Duplicate/missing/normal-main compiler source accepted')
            print('Compiler input controls passed: wrong/duplicate target, unsafe/outside path, duplicate architecture/response inode, duplicate/missing source and normal-main inclusion rejected (9 controls). Metadata fixture only; no build/native execution.')
        finally:
            current_globals.update(saved)


def interrupted(signum, _frame):
    raise RuntimeError('Interrupted by signal ' + str(signum))


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def main():
    if mode == 'self-test':
        self_test()
        return
    if mode == 'prepare':
        output.mkdir(exist_ok=False)
        require(not git('status', '--porcelain', '--untracked-files=normal', '--', *roots), 'Commit source inputs before verification')
        require(git('rev-parse', 'HEAD').decode().strip() == os.environ['GITHUB_SHA'], 'GitHub head differs from actual source')
        require(digest((repo / lock_path).read_bytes()) == lock_sha, 'Canonical lock differs')
        helper = (repo / helper_path).read_bytes()
        marker = b'private enum LiveWritingFailure:'
        require(helper.count(marker) == 1, 'Editor helper boundary differs')
        write_json(output / 'source-before.json', manifest())
        write_json(output / 'contract.json', {'source_sha': git('rev-parse', 'HEAD').decode().strip(),
            'github_run_id': os.environ['GITHUB_RUN_ID'], 'cases': cases, 'lock_sha256': lock_sha, 'canonical_pins': 41,
            'excluded_source_files': ['VoiceInk.swift'], 'helper_tail_sha256': digest(helper[helper.index(marker):]),
            'generated_sources_sha256': {path: digest(data) for path, data in generated_sources().items()},
            'scope': 'Isolated genuine Undo controls, SwiftUI MenuBarExtra bridge and real configured shortcut into one real engine; actual TextEdit and Safari surfaces.',
            'limits': ['Normal VoiceInkApp composition is excluded; this is component-host acceptance.',
                'No ASR, microphone, model loading, provider, full recording pipeline or physical keyboard proof.',
                'Exact signed Accessibility, ListenEvent, PostEvent and ScreenCapture grants on a disposable runner only.',
                'Plain-text inverse only; no release or general editor compatibility claim.']})
        for path in [*fixture_paths, helper_path]:
            destination = output / 'source' / Path(path).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((repo / path).read_bytes())
        export_candidate()
        run(['bash', 'scripts/run-writing-feature-regression.sh', 'packages', str(output / 'packages'), '', '', str(packages)], output / 'packages.log')
        run(['sw_vers'], output / 'sw-vers.txt')
        run(['xcodebuild', '-version'], output / 'xcode-version.txt')
        run(['swift', '--version'], output / 'swift-version.txt')
        verify_source()
        verify_candidate()
        return
    require(mode in ('native', 'verify'), 'usage: run-writing-undo-controls-check.sh self-test | prepare | native | verify')
    verify_source()
    verify_candidate()
    if mode == 'native':
        package_state, whisper = package_identity(), static_identity()
        write_json(output / 'packages-before.json', package_state)
        write_json(output / 'static-whisper-before.json', whisper)
        arguments = build_arguments()
        write_json(output / 'build-command.json', {'arguments': arguments, 'action': 'build', 'test_host': False})
        run(['xcodebuild', '-showBuildSettings', '-json', *arguments], output / 'build-settings.json', timeout=180,
            cwd=candidate, stderr_log=output / 'build-settings-errors.log')
        settings = [item['buildSettings'] for item in json.loads((output / 'build-settings.json').read_text()) if item.get('target') == 'VoiceInk']
        require(len(settings) == 1, 'Exactly one app build-settings target required')
        expected = {'EXCLUDED_SOURCE_FILE_NAMES': 'VoiceInk.swift', 'ENABLE_DEBUG_DYLIB': 'NO',
            'ENABLE_PREVIEWS': 'NO', 'ENABLE_HARDENED_RUNTIME': 'YES'}
        require({key: settings[0].get(key) for key in expected} == expected, 'Actual isolated host settings differ')
        require('LOCAL_BUILD' in settings[0].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split(), 'Host lacks LOCAL_BUILD credential isolation')
        write_json(output / 'resolved-host-settings.json', {'target': 'VoiceInk', 'resolved': expected,
            'limits': 'Actual ad-hoc CodeDirectory/entitlements independently verified; settings alone are not signature proof.'})
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
        require(tcc_rows() == json.loads((output / 'tcc-before.json').read_text()), 'Signed TCC rows changed during execution')
        require(host == identity() and package_state == package_identity() and whisper == static_identity(), 'Signed app/dependencies changed during execution')
        verify_source()
        verify_candidate()
        result = classify_native(host, live)
        require(result['valid'], 'Native control receipt failed: ' + '; '.join(result['errors']))
        write_json(output / 'native-classification.json', result)
        write_json(output / 'identity-after.json', identity())
        write_json(output / 'source-after.json', manifest())
        write_json(output / 'result.json', {'classification': 'passed', 'valid': True, 'source_sha': contract()['source_sha'],
            'cases': cases, 'native_receipt_sha256': digest((native / 'result.json').read_bytes()),
            'classification_sha256': digest((output / 'native-classification.json').read_bytes()), 'limits': contract()['limits']})
        return
    host = json.loads((output / 'identity-before.json').read_text())
    require(host == json.loads((output / 'identity-after.json').read_text()) == identity(), 'Retained host identity changed')
    require(compile_inputs() == json.loads((output / 'compile-inputs.json').read_text()), 'Actual compiler input evidence changed')
    require(package_identity() == json.loads((output / 'packages-before.json').read_text()), 'Frozen package identity changed')
    require(static_identity() == json.loads((output / 'static-whisper-before.json').read_text()), 'Frozen static dependency changed')
    require(tcc_rows() == json.loads((output / 'tcc-before.json').read_text()) == json.loads((output / 'tcc-after.json').read_text()), 'Frozen TCC rows changed')
    live = json.loads((output / 'host-live.json').read_text())
    closed = json.loads((output / 'host-closed.json').read_text())
    require(live['exit_code'] == 0 and closed['valid'] is True and closed['host'] == live['host'], 'Host lifecycle evidence invalid')
    require(live['spawned_identity'] == {key: live['host'][key] for key in ('started_at', 'executable_path')}, 'Spawned and mapped host identities differ')
    require(closed['exact_executable_census_empty'] is True and closed['exact_executable_has_no_open_descriptors'] is True,
        'Host closure observations invalid')
    require(not host_census(host['executable_path']), 'Exact native host is running during verification')
    actual = classify_native(host, live['host'])
    require(actual['valid'] and actual == json.loads((output / 'native-classification.json').read_text()), 'Retained control classifier differs or failed')
    retained = json.loads((output / 'result.json').read_text())
    require(retained['valid'] is True and retained['classification'] == 'passed' and retained['source_sha'] == contract()['source_sha']
        and retained['cases'] == cases and retained['native_receipt_sha256'] == digest((native / 'result.json').read_bytes())
        and retained['classification_sha256'] == digest((output / 'native-classification.json').read_bytes()), 'Full native result binding invalid')
    write_json(output / 'complete-result.json', {'classification': 'passed', 'source_sha': contract()['source_sha'], 'cases': cases,
        'native_cases': 4, 'host_launches': 1, 'result_sha256': digest((output / 'result.json').read_bytes()), 'limits': contract()['limits']})


try:
    main()
except BaseException as error:
    if output.is_dir() and mode != 'self-test':
        (output / ('failure-' + mode + '.json')).write_text(json.dumps({'mode': mode, 'classification': 'invalid-or-failed', 'error': str(error)}, indent=2) + '\n')
    raise
