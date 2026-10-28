#!/usr/bin/env python3
"""Source-bound disposable Mac acceptance for unchanged Undo controls."""
import ast
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


def progress_files():
    directory = native / 'progress'
    return sorted(str(path.relative_to(native)) for path in directory.glob('*.json') if path.is_file() and not path.is_symlink())


def profile_files():
    return {str(path.relative_to(native)): {'bytes': path.stat().st_size, 'sha256': digest(path.read_bytes())}
        for path in sorted((native / 'profiles').glob('*.profraw')) if path.is_file() and not path.is_symlink()}


def verify_profile_configuration(configuration):
    require(configuration.get('working_directory') == str(native)
        and configuration.get('LLVM_PROFILE_FILE') == str(native / 'profiles/undo-controls-%p-%m.profraw')
        and configuration.get('host_timeout_seconds') == 180,
        'Host working directory/profile destination differs from the owned external diagnostic output')
    profile = Path(configuration['LLVM_PROFILE_FILE'])
    require(profile.is_absolute() and profile.parent.resolve() == profile.parent
        and not profile.is_relative_to(candidate) and not profile.is_relative_to(derived),
        'Raw profile destination reaches frozen source/compiler inputs')


def sample_host(host, checkpoint, elapsed_seconds):
    directory = native / ('sample-' + checkpoint)
    directory.mkdir()
    expected = {key: host[key] for key in ('started_at', 'executable_path')}
    before = process_identity(host['pid'])
    result = {'checkpoint': checkpoint, 'pid': host['pid'], 'expected_identity': expected, 'identity_before': before,
        'identity_after': None, 'tool': '/usr/bin/sample', 'tool_timeout_seconds': 8, 'tool_exit_code': None,
        'tool_arguments': [str(host['pid']), '1', '1', '-file', str(directory / 'sample.txt')],
        'status': 'identity-refused', 'valid': False, 'progress_files': progress_files(), 'observed_elapsed_seconds': elapsed_seconds}
    if before == expected and expected['executable_path'] in host['mapped_text_paths']:
        try:
            tool = subprocess.run(['/usr/bin/sample', str(host['pid']), '1', '1', '-file', str(directory / 'sample.txt')],
                capture_output=True, timeout=8)
            (directory / 'tool-stdout.txt').write_bytes(tool.stdout)
            (directory / 'tool-stderr.txt').write_bytes(tool.stderr)
            result.update(tool_exit_code=tool.returncode, status='tool-failed')
            after = process_identity(host['pid'])
            result['identity_after'] = after
            if after != expected:
                result['status'] = 'identity-changed-during-sample'
            elif tool.returncode == 0 and (directory / 'sample.txt').is_file() and not (directory / 'sample.txt').is_symlink() and (directory / 'sample.txt').stat().st_size > 0:
                result.update(status='captured', valid=True, sample_sha256=digest((directory / 'sample.txt').read_bytes()))
        except subprocess.TimeoutExpired as error:
            (directory / 'tool-stdout.txt').write_bytes(error.stdout or b'')
            (directory / 'tool-stderr.txt').write_bytes(error.stderr or b'')
            result.update(status='timeout', identity_after=process_identity(host['pid']))
        except OSError as error:
            result.update(status='tool-unavailable', error=str(error), identity_after=process_identity(host['pid']))
    write_json(directory / 'receipt.json', result)
    return result


def capture_diagnostic_screen(host, checkpoint, elapsed_seconds):
    """Independent screen observation; never a replacement for a native case screenshot."""
    directory = native / ('diagnostic-screen-' + checkpoint)
    directory.mkdir()
    path = directory / 'screen.png'
    expected = {key: host[key] for key in ('started_at', 'executable_path')}
    before = process_identity(host['pid'])
    result = {'checkpoint': checkpoint, 'pid': host['pid'], 'expected_identity': expected, 'identity_before': before,
        'identity_after': None, 'tool': '/usr/sbin/screencapture', 'tool_timeout_seconds': 8, 'tool_exit_code': None,
        'status': 'identity-refused', 'valid': False, 'observed_elapsed_seconds': elapsed_seconds,
        'progress_files': progress_files()}
    if before == expected and expected['executable_path'] in host['mapped_text_paths']:
        try:
            tool = subprocess.run(['/usr/sbin/screencapture', '-x', '-t', 'png', str(path)], capture_output=True, timeout=8)
            (directory / 'tool-stdout.txt').write_bytes(tool.stdout)
            (directory / 'tool-stderr.txt').write_bytes(tool.stderr)
            result.update(tool_exit_code=tool.returncode, identity_after=process_identity(host['pid']), status='tool-failed')
            if result['identity_after'] != expected:
                result['status'] = 'identity-changed-during-capture'
            elif tool.returncode == 0 and path.is_file() and not path.is_symlink():
                data = path.read_bytes()
                if len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR' and min(struct.unpack('>II', data[16:24])) > 0:
                    result.update(status='captured', valid=True, png_bytes=len(data), png_sha256=digest(data))
        except subprocess.TimeoutExpired as error:
            (directory / 'tool-stdout.txt').write_bytes(error.stdout or b'')
            (directory / 'tool-stderr.txt').write_bytes(error.stderr or b'')
            result.update(status='timeout', identity_after=process_identity(host['pid']))
        except OSError as error:
            result.update(status='tool-unavailable', error=str(error), identity_after=process_identity(host['pid']))
    write_json(directory / 'receipt.json', result)
    return result


def verify_diagnostic_screens(outcome, host):
    records = outcome['diagnostic_screens']
    require(isinstance(records, list) and len(records) <= 2
        and len(records) == len({item['checkpoint'] for item in records}), 'Duplicate/unbounded diagnostic screen captures')
    expected = {key: host[key] for key in ('started_at', 'executable_path')}
    for item in records:
        require(item['checkpoint'] in ('15s', '60s') and item['pid'] == host['pid']
            and item['expected_identity'] == expected and item['tool'] == '/usr/sbin/screencapture'
            and item['tool_timeout_seconds'] == 8 and type(item['valid']) is bool
            and type(item['observed_elapsed_seconds']) in (int, float) and math.isfinite(item['observed_elapsed_seconds'])
            and item['observed_elapsed_seconds'] >= int(item['checkpoint'][:-1]), 'Diagnostic screen identity/checkpoint invalid')
        directory = native / ('diagnostic-screen-' + item['checkpoint'])
        require(item == json.loads((directory / 'receipt.json').read_text()), 'Diagnostic screen receipt changed')
        if item['valid']:
            path = directory / 'screen.png'
            require(item['status'] == 'captured' and item['tool_exit_code'] == 0
                and item['identity_before'] == item['identity_after'] == expected and not path.is_symlink()
                and item['png_bytes'] == path.stat().st_size and item['png_sha256'] == digest(path.read_bytes()),
                'Diagnostic screen tool/identity/retained PNG changed')
        else:
            require(item['status'] in ('identity-refused', 'identity-changed-during-capture', 'timeout', 'tool-unavailable', 'tool-failed'),
                'Invalid diagnostic screen falsely labeled captured')


def run_host(host):
    native.mkdir()
    profiles = native / 'profiles'
    profiles.mkdir()
    profile_template = profiles / 'undo-controls-%p-%m.profraw'
    require(native.is_absolute() and native.resolve() == native and profiles.resolve() == profiles
        and not profiles.is_relative_to(candidate) and not profiles.is_relative_to(derived),
        'Profile output must be owned and outside the frozen candidate/compiler tree')
    home = output / 'isolated-user'
    preferences = home / 'Library/Preferences'
    preferences.mkdir(parents=True)
    seed = {'selectedAIProvider': 'Local CLI', 'PrewarmModelOnWake': False, 'hasCompletedOnboarding': True,
        'isAIEnhancementEnabled': False, 'IsAudioCleanupEnabled': False, 'IsTranscriptionCleanupEnabled': False,
        'enableAnnouncements': False, 'SUEnableAutomaticChecks': False, 'restoreClipboardAfterPaste': True,
        'clipboardRestoreDelay': 2.0}
    (preferences / (bundle_id + '.plist')).write_bytes(plistlib.dumps(seed))
    environment = dict(os.environ, CFFIXED_USER_HOME=str(home), RJT_UNDO_CONTROLS_CHECKS='1', RJT_UNDO_CONTROLS_EVIDENCE=str(native),
        RJT_LIVE_WRITING_TARGET_EVIDENCE=str(native / 'editor-observations'), RJT_LIVE_WRITING_TARGET_CHECKS='1',
        LLVM_PROFILE_FILE=str(profile_template))
    configuration = {'executable_path': host['executable_path'], 'seed_preferences': seed,
        'CFFIXED_USER_HOME': str(home), 'RJT_UNDO_CONTROLS_EVIDENCE': str(native), 'command_line_arguments': [],
        'RJT_UNDO_CONTROLS_CHECKS': '1',
        'working_directory': str(native), 'LLVM_PROFILE_FILE': str(profile_template),
        'host_timeout_seconds': 180,
        'coverage_policy': 'Compiler instrumentation preserved; raw profiles stay outside frozen source/compiler inputs.',
        'scope': 'One isolated component host; VoiceInkApp entry point excluded; no provider, recording, ASR or model loading.'}
    verify_profile_configuration(configuration)
    write_json(output / 'configuration.json', configuration)
    executable = host['executable_path']
    require(not host_census(executable), 'Fresh exact host executable already running')
    observed, launched = None, None
    monitor_error, closure_error, candidate_error = None, None, None
    census_empty, descriptors_closed = None, None
    samples, diagnostic_screens = [], []
    with (output / 'host.log').open('xb') as stream:
        process = subprocess.Popen([executable], cwd=native, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            started = time.monotonic()
            deadline = started + 180
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
                for threshold in (15, 60):
                    checkpoint = str(threshold) + 's'
                    if observed is not None and time.monotonic() - started >= threshold and checkpoint not in [item['checkpoint'] for item in samples]:
                        diagnostic_screens.append(capture_diagnostic_screen(observed, checkpoint, time.monotonic() - started))
                        samples.append(sample_host(observed, checkpoint, time.monotonic() - started))
                require(time.monotonic() < deadline, 'Control host exceeded the 180-second diagnostic deadline')
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
    valid = process.returncode == 0 and observed is not None and receipt.get('completed') is True
    valid = valid and not any((monitor_error, closure_error, candidate_error, native_failure, native_issues))
    write_json(output / 'host-outcome.json', {'classification': 'passed' if valid else 'invalid-or-failed',
        'exit_code': process.returncode, 'mapped_host_observed': observed is not None, 'native_failure': native_failure,
        'native_issues': native_issues, 'monitor_error': monitor_error, 'closure_error': closure_error,
        'candidate_error': candidate_error, 'observed_completed_cases': receipt.get('executedCases', []),
        'progress_files': progress_files(), 'samples': samples, 'diagnostic_screens': diagnostic_screens,
        'profile_files': profile_files()})
    if native_failure or native_issues:
        raise RuntimeError('Control host oracle failed (exit ' + str(process.returncode) + '): ' + str(native_failure or native_issues)
            + '; inspect host-outcome.json for secondary diagnostics')
    require(process.returncode == 0, 'Control host exited with code ' + str(process.returncode) + '; inspect host.log and host-outcome.json')
    require(monitor_error is None, 'Control host monitor failed: ' + str(monitor_error))
    require(observed is not None, 'No mapped live host observed')
    require(closure_error is None, 'Control host closure failed: ' + str(closure_error))
    require(candidate_error is None, 'Control host candidate changed: ' + str(candidate_error))
    return observed


def units(value):
    data = value.encode('utf-16-le')
    return list(struct.unpack('<' + 'H' * (len(data) // 2), data))


def exact_range(location, length):
    return {'location': location, 'length': length}


def case_text_fixture(case_id):
    require(case_id in cases, 'Unknown fixed native control case')
    if case_id.startswith('safari-'):
        source = 'target \u00e9'
        replacement = 'Longer 👩🏽‍💻 \u00e9\nRJT, 台灣, 🧑‍🚀.' if case_id.endswith('-menu') else 'Short \u00e9 😀'
    else:
        source = passage
        replacement = replacement_menu if case_id.endswith('-menu') else replacement_shortcut
    return prefix + source + suffix, replacement, exact_range(len(units(prefix)), len(units(source)))


def receipt_errors(value, executable, pid, expected_home):
    """Recompute the oracle, including normalization-sensitive text and ranges."""
    errors = []
    def check(condition, message):
        if not condition:
            errors.append(message)
    def control(item, identifier, roles, enabled=True):
        check(isinstance(item, dict), 'Control is missing')
        if not isinstance(item, dict):
            return
        check(item.get('id') == identifier and item.get('role') in roles, 'Actual control identity/role differs: ' + identifier)
        check(item.get('enabled') is enabled, 'Control enabled state differs: ' + identifier)
        frame = item.get('frame', {})
        check(isinstance(frame, dict) and set(frame) == {'x', 'y', 'width', 'height'}
            and all(type(v) in (int, float) and abs(v) < 100000 for v in frame.values())
            and frame.get('width', 0) > 0 and frame.get('height', 0) > 0, 'Actual control frame invalid: ' + identifier)
        # Action names describe AX support; native mouse input does not invoke AXPress.
        check(type(item.get('actionsAXError')) is int
            and isinstance(item.get('actions'), list) and all(isinstance(action, str) for action in item['actions']),
            'AX action diagnostic is malformed: ' + identifier)
    def menu_identity(proof, target, status=None):
        check(isinstance(proof, dict), 'Status-owned native menu proof missing')
        if not isinstance(proof, dict):
            return
        check(proof.get('schemaVersion') == 2 and proof.get('kind') == 'native-menu-bridge-identity'
            and proof.get('contract') == 'status-owned-native-menu-item-title'
            and proof.get('identityAuthority') == 'retained-status-downward-subtree'
            and proof.get('upwardParentAuthorizes') is False
            and proof.get('expectedTitle') == 'Undo Last Writing Edit' and proof.get('expectedRole') == 'AXMenuItem'
            and proof.get('hostPID') == pid and proof.get('identifierRequired') is False
            and proof.get('globalSearchUsed') is False and proof.get('textFallbackUsed') is False
            and proof.get('maxDepth') == 4 and proof.get('maxNodes') == 64
            and proof.get('proven') is True and proof.get('reason') is None, 'Native menu contract/source/ownership differs')
        owner, walk, command = (proof.get(k, {}) for k in ('status', 'traversal', 'command'))
        check(owner.get('pid') == pid and owner.get('role') in ('AXMenuBarItem', 'AXButton')
            and owner.get('identityContract') in ('identifier', 'fixture-title')
            and (owner.get('identifier') == 'undoControlHost.statusItem' or owner.get('identityContract') == 'fixture-title')
            and owner.get('sameRetainedReference') is True and owner.get('parentAXError') == 0
            and owner.get('parentIsHostExtrasMenuBar') is True and owner.get('extrasMenuBarPresent') is True
            and owner.get('extrasMenuBarPID') == pid and owner.get('parentRole') == 'AXMenuBar',
            'Native menu is not under the retained owned extras status item')
        if status is not None:
            check(owner.get('identifier') == status.get('id') and owner.get('role') == status.get('role'),
                'Native menu owner differs from opened status item')
        check(type(walk.get('discoveredCount')) is int and 1 <= walk['discoveredCount'] <= 64
            and walk.get('expandedCount') == walk['discoveredCount'] and walk.get('truncated') is False
            and walk.get('unreadableChildren') == [] and walk.get('exactMatchCount') == 1
            and proof.get('uniqueMatch') is True, 'Native submenu uniqueness was not proven within its bound')
        check(command.get('role') == 'AXMenuItem' and command.get('title') == 'Undo Last Writing Edit'
            and command.get('pid') == pid and command.get('identifier') == target.get('id')
            and command.get('identifierEmpty') is (target.get('id') == '')
            and command.get('frame') == target.get('frame') and command.get('enabled') is target.get('enabled'),
            'Native command differs from actual described menu item')
        down = proof.get('downwardPath', [])
        check(isinstance(down, list) and 2 <= len(down) <= 4, 'Native downward submenu ancestry missing')
        if isinstance(down, list) and 2 <= len(down) <= 4:
            check(all(item.get('pid') == pid and item.get('depth') == n
                and item.get('role') in ('AXMenu', 'AXMenuItem') for n, item in enumerate(down, 1))
                and down[-1].get('role') == 'AXMenuItem' and down[-1].get('title') == 'Undo Last Writing Edit',
                'Native downward path is not a host-owned submenu chain')
            check(proof.get('downwardProof') == {'rootIsRetainedStatus': True, 'statusParentIsHostExtrasMenuBar': True,
                'fullyReadable': True, 'truncated': False, 'uniqueExactMatch': True, 'pathLength': len(down),
                'allHostPID': True, 'menuRole': 'AXMenu', 'commandRole': 'AXMenuItem', 'exactTitle': 'Undo Last Writing Edit'},
                'Authoritative downward proof differs from the retained owned subtree')
            # Native run40629369072 has a nonreciprocal AXParent edge. These
            # bounded observations describe that graph; they never grant identity.
            diagnostic = proof.get('upwardParentDiagnostics', {})
            up = diagnostic.get('observations', [])
            check(diagnostic.get('diagnosticOnly') is True and diagnostic.get('authorizationCondition') is False
                and diagnostic.get('maxLevels') == len(down) and isinstance(up, list) and 1 <= len(up) <= len(down),
                'Upward parent diagnostics lack explicit non-authority or bounds')
            expected_up = list(reversed(down[:-1])) + [dict(owner, depth=0)]
            if isinstance(up, list) and 1 <= len(up) <= len(down):
                check(all(type(item.get('axError')) is int and item.get('level') == n
                    and type(item.get('elementPresent')) is bool and type(item.get('matchesDownwardPath')) is bool
                    and type(item.get('isRetainedStatus')) is bool and item.get('expectedDownwardRole') == expected.get('role')
                    and (not item['elementPresent'] or isinstance(item.get('role'), str)
                        and isinstance(item.get('identifier'), str) and (item.get('title') is None or isinstance(item['title'], str))
                        and (item.get('pid') is None or type(item['pid']) is int and item['pid'] > 0))
                    for n, (item, expected) in enumerate(zip(up, expected_up), 1)), 'Malformed raw upward parent observations')
                check(all(item.get('axError') == 0 and item.get('elementPresent') is True for item in up[:-1]),
                    'Upward diagnostic walk continued after an AX error or missing parent')
                reciprocal = len(up) == len(down) and all(item.get('axError') == 0 and item.get('matchesDownwardPath') is True for item in up)
                check(diagnostic.get('reciprocalToDownwardPath') is reciprocal
                    and diagnostic.get('reachesRetainedStatus') is any(item.get('isRetainedStatus') is True for item in up),
                    'Upward diagnostic summary invents reciprocal ownership')
    def click(item, target, identifier, roles, checkpoint, status=False):
        check(isinstance(item, dict) and isinstance(target, dict), 'Native mouse input receipt is missing')
        if not isinstance(item, dict) or not isinstance(target, dict):
            return
        check(item.get('kind') == 'native-mouse-click' and item.get('eventTypes') == ['leftMouseDown', 'leftMouseUp']
            and type(item.get('eventCount')) is int and item['eventCount'] == 2
            and item.get('tap') == 'cghidEventTap' and type(item.get('clickState')) is int and item['clickState'] == 1
            and type(item.get('flagsRawValue')) is int and item['flagsRawValue'] == 0,
            'Native mouse transport/event count differs')
        check(type(item.get('hostPID')) is int and item['hostPID'] == pid
            and type(item.get('hitPID')) is int and item['hitPID'] == pid,
            'Native mouse target/hit process differs from mapped host')
        check(item.get('targetID') == target.get('id') and item.get('targetRole') == target.get('role')
            and item.get('targetRole') in roles, 'Native mouse target identity/role differs from observed control')
        native_menu = item.get('identityContract') == 'status-owned-native-menu-item-title' and identifier == 'undoLastWritingEdit.menuCommand'
        if native_menu:
            menu_identity(item.get('nativeMenuIdentity'), target)
        else:
            check(item.get('identityContract') == 'identifier' and item.get('targetID') == identifier
                or status and item.get('identityContract') == 'fixture-title' and target.get('label') == 'RJT Undo check',
                'Native mouse target does not satisfy its exact identity contract')
        def rectangle(raw):
            return isinstance(raw, dict) and set(raw) == {'x', 'y', 'width', 'height'} \
                and all(type(v) in (int, float) and math.isfinite(v) and abs(v) < 100000 for v in raw.values()) \
                and raw['width'] > 0 and raw['height'] > 0
        frame, bounds, point = item.get('targetFrame'), item.get('activeDisplayBounds'), item.get('point')
        geometry = rectangle(frame) and rectangle(bounds) and isinstance(point, dict) and set(point) == {'x', 'y'} \
            and all(type(v) in (int, float) and math.isfinite(v) for v in point.values())
        check(geometry, 'Native mouse frame/display/point geometry invalid')
        if geometry:
            check(frame == target.get('frame') and point == {'x': frame['x'] + frame['width'] / 2, 'y': frame['y'] + frame['height'] / 2}
                and bounds['x'] <= frame['x'] and bounds['y'] <= frame['y']
                and frame['x'] + frame['width'] <= bounds['x'] + bounds['width']
                and frame['y'] + frame['height'] <= bounds['y'] + bounds['height'],
                'Native mouse point is not the exact observed center in its display')
        check(type(item.get('activeDisplayID')) is int and item['activeDisplayID'] > 0
            and type(item.get('hitDepth')) is int and 0 <= item['hitDepth'] <= 8,
            'Native mouse display/hit ancestry observation invalid')
        check(all(item.get(key) is True for key in ('sameTargetOrDescendant', 'uniqueTarget', 'frameStable',
            'targetOwnedByHost', 'hitOwnedByHost')), 'Native mouse hit/identity/geometry proof failed')
        if item.get('windowPolicy') == 'same-window':
            check(all(item.get(key) is True for key in ('targetWindowPresent', 'hitWindowPresent', 'sameWindow', 'windowOwnedByHost'))
                and item.get('nativeMenuAncestry') is False and item.get('menuAncestorRole') == '',
                'Native mouse window ownership differs')
        elif item.get('windowPolicy') == 'windowless-native-menu':
            check(all(item.get(key) is False for key in ('targetWindowPresent', 'hitWindowPresent', 'sameWindow', 'windowOwnedByHost'))
                and item.get('nativeMenuAncestry') is True and item.get('menuAncestorRole') in ('AXMenu', 'AXMenuBar')
                and item.get('targetRole') in ('AXMenuItem', 'AXMenuBarItem'),
                'Windowless native mouse control lacks owned menu ancestry')
        else:
            check(False, 'Unknown native mouse window ownership policy')
        readiness = item.get('readiness', {})
        check(isinstance(readiness, dict), 'Pre-input readiness summary missing')
        if isinstance(readiness, dict):
            count = readiness.get('attemptCount')
            check(readiness.get('experiment') == 'preinput-readiness-calibration'
                and type(count) is int and 1 <= count <= 6 and readiness.get('maxAttempts') == 6
                and readiness.get('deadlineSeconds') == 6 and readiness.get('intervalMilliseconds') == 1000
                and type(readiness.get('elapsedSeconds')) in (int, float) and math.isfinite(readiness['elapsedSeconds'])
                and readiness['elapsedSeconds'] >= 0 and readiness.get('noInputBeforeReady') is True
                and readiness.get('finalObservationReady') is True, 'Pre-input readiness bounds/authority invalid')
            if type(count) is int and 1 <= count <= 6:
                names = ['click-readiness-' + checkpoint + '-attempt-' + str(n) + '.json' for n in range(1, count + 1)]
                check(readiness.get('observations') == names and readiness.get('finalObservation') == names[-1],
                    'Pre-input readiness observation names/count differ')
    def menu(item, enabled, checkpoint):
        control(item, item.get('id', ''), ['AXMenuItem'], enabled)
        check(item.get('label') == 'Undo Last Writing Edit', 'Native menu command title differs')
        check(item.get('kind') == 'product-menu', 'Wrong product menu boundary')
        status = item.get('statusControl', {})
        control(status, status.get('id', ''), ['AXMenuBarItem', 'AXButton'])
        check(status.get('id') == 'undoControlHost.statusItem' or status.get('label') == 'RJT Undo check', 'Wrong actual status control')
        menu_identity(item.get('nativeMenuIdentity'), item, status)
        click(item.get('statusClick'), status, 'undoControlHost.statusItem', ['AXMenuBarItem', 'AXButton'], 'menu.' + checkpoint + '.status', status=True)
    def notice(item, message):
        check(isinstance(item, dict) and item.get('id') == 'undoLastWritingEdit.notice'
            and item.get('expectedMessage') == message and message in (item.get('label'), item.get('value')),
            'Actual passive notice differs: ' + message)
    def dismissal(item):
        check(item.get('kind') == 'native-menu-dismissal' and item.get('contract') == 'same-status-owned-menu-not-displayed'
            and item.get('escapeEventsPosted') == 2 and item.get('inputRetries') == 0
            and type(item.get('polls')) is int and item['polls'] > 0 and item.get('statusRetainedFromOpen') is True,
            'Native menu dismissal transport/owner differs')
        closure = item.get('closure', {})
        check(closure.get('hostPID') == pid and closure.get('axErrorTreatedAsClosed') is False
            and closure.get('hitAXError') == 0 and type(closure.get('hitPID')) is int
            and closure['hitPID'] > 0 and closure.get('closed') is True and closure.get('reason') is None
            and closure.get('statusSelected') is not True, 'Native menu dismissal lacks successful read-only closure evidence')
        if closure.get('evidence') == 'hit-other-process':
            check(closure.get('hitPID') != pid, 'Menu closure claimed another process with host PID')
        else:
            chain = closure.get('hitAncestry', [])
            check(closure.get('evidence') == 'hit-host-non-menu-element' and closure.get('hitPID') == pid
                and isinstance(chain, list) and 1 <= len(chain) <= 11 and chain[-1] == 'AXApplication'
                and not any(role in ('AXMenu', 'AXMenuItem', 'AXMenuBarItem') for role in chain),
                'Menu closure ancestry still includes a native menu or lacks application owner')
    def recorder_capture(item):
        expected = {'kind': 'key', 'keyCode': 32, 'modifierFlagsRawValue': 1835008, 'displayString': item.get('displayString')}
        def own_state(state, phase, captured=False, fresh=False):
            check(state.get('phase') == phase and state.get('action') == 'undoLastWritingEdit'
                and state.get('clearedValueKind') == ('nil' if captured or fresh else 'true')
                and state.get('clearedValue') is (None if captured or fresh else True)
                and state.get('isShortcutCleared') is (not captured and not fresh)
                and state.get('dataPresent') is captured and state.get('effectiveEqualsExpected') is captured,
                'Recorder own stored state differs: ' + phase)
            if captured:
                check(state.get('effective') == state.get('decoded') == expected and state.get('decodeSucceeded') is True
                    and type(state.get('dataBytes')) is int and 0 < state['dataBytes'] <= 65536
                    and isinstance(state.get('dataSHA256'), str) and re.fullmatch('[a-f0-9]{64}', state['dataSHA256']) is not None,
                    'Recorder saved state lacks exact public decoded/effective chord')
            else:
                check(state.get('effective') is None and not any(key in state for key in ('dataBytes', 'dataSHA256', 'decodeSucceeded', 'decoded')),
                    'Recorder expected empty state contains hidden or stale data')
        def no_conflict(state):
            check(state.get('api') == 'ShortcutValidator.validationError' and state.get('action') == 'undoLastWritingEdit'
                and state.get('expected') == expected and state.get('conflictFree') is True and state.get('issue') is None,
                'Recorder expected chord conflicts per public validator')
        event = item.get('captureInput', {})
        check(event.get('contract') == 'focused-recorder-capture-postToPid' and event.get('route') == 'CGEvent.postToPid'
            and event.get('pattern') == 'LiveWritingEditor.key' and event.get('eventSource') == 'nil'
            and event.get('hostPID') == event.get('targetPID') == pid
            and event.get('eventTypes') == ['keyDown', 'keyUp'] and event.get('eventCount') == 2
            and event.get('events') == [{'type': kind, 'keyCode': 32, 'flagsRawValue': 1835008} for kind in ('keyDown', 'keyUp')]
            and event.get('eventsExact') is True and event.get('keyCode') == 32
            and event.get('modifierFlagsRawValue') == event.get('eventFlagsRawValue') == 1835008
            and event.get('fallbackUsed') is False and event.get('retryUsed') is False and event.get('physicalKeyboard') is False
            and event.get('laterGlobalInvocationRoute') == 'postChord-cghidEventTap-unchanged'
            and event.get('finalProofReady') is True and event.get('inputPosted') is True,
            'Recorder capture route/owner/events or no-retry contract differs')
        proof = item.get('captureProof', {})
        check(proof.get('schemaVersion') == 1 and proof.get('kind') == 'recorder-capture-proof'
            and proof.get('phase') == 'final-preinput' and proof.get('readOnly') is True and proof.get('inputPosted') is False
            and proof.get('hostPID') == pid and proof.get('ready') is True and proof.get('reasons') == []
            and proof.get('expectedPlaceholder') == 'Press shortcut' and type(proof.get('systemUptime')) in (int, float)
            and math.isfinite(proof['systemUptime']) and proof['systemUptime'] > 0,
            'Recorder final pre-input proof missing or not ready')
        target = proof.get('recorder', {})
        check(target.get('identifier') == 'shortcutRecorder.undoLastWritingEdit' and target.get('uniqueCount') == 1
            and target.get('sameReferenceAsLookup') is True and target.get('role') == 'AXButton' and target.get('pid') == pid
            and target.get('enabled') is True and target.get('description') == 'Press shortcut'
            and target.get('labelIsRecordingPlaceholder') is True, 'Recorder is not the same actual capture-mode control')
        window = proof.get('axWindow', {})
        check(window.get('axError') == window.get('windowsAXError') == window.get('focusedWindowAXError') == 0
            and window.get('present') is True and window.get('pid') == pid and window.get('role') == 'AXWindow'
            and window.get('title') == 'RJT Undo control check' and window.get('titledCount') == 1
            and window.get('uniqueSameReference') is True and window.get('focusedWindowIsSetupWindow') is True,
            'Recorder capture lacks the unique focused owned AXWindow')
        focus = proof.get('systemFocus', {})
        check(focus.get('focusedApplicationAXError') == 0 and focus.get('focusedApplicationPID') == focus.get('frontmostPID') == pid,
            'Recorder capture lacks actual system focused/foreground host')
        check(focus.get('focusedElementAXError') == 0 and focus.get('focusedElementPresent') is True and focus.get('focusedElementPID') == pid
            or focus.get('focusedElementAXError') == -25212 and focus.get('focusedElementPresent') is False and focus.get('focusedElementPID') is None,
            'Recorder focused element is foreign or has an unhandled AX error')
        appkit = proof.get('appKit', {})
        check(all(appkit.get(key) is True for key in ('isActive', 'isKeyWindow', 'isVisible', 'appKeyWindowIsSetup', 'uniqueSameWindow'))
            and appkit.get('titledWindowCount') == 1 and type(appkit.get('windowNumber')) is int and appkit['windowNumber'] > 0,
            'Recorder capture lacks actual active/key/unique native setup window')
        states = item.get('ownShortcutState', {})
        # A fresh empty action prevents this QA route from concealing a stale
        # already-registered copy of the same global chord during capture.
        own_state(states.get('beforeClick', {}), 'before-click', fresh=True)
        own_state(states.get('beforeInput', {}), 'before-input')
        own_state(states.get('afterReadback', {}), 'after-readback', captured=True)
        own_state(proof.get('ownShortcut', {}), 'final-preinput')
        no_conflict(item.get('conflictBeforeClick', {}))
        no_conflict(proof.get('conflictCheck', {}))
        readback = item.get('readback', {})
        check(readback.get('storeEqualsExpected') is True and readback.get('recorderIdleDisplayMatches') is True
            and readback.get('recorderDescription') == item.get('displayString')
            and item.get('capturePreInputFile') == 'shortcut-capture-preinput.json',
            'Recorder exact store/idle-display readback or retained pre-input file differs')
        check(readback.get('displaySource') == 'current-control' and type(readback.get('currentReadbackPolls')) is int
            and readback['currentReadbackPolls'] > 0, 'Recorder idle display did not come from a fresh read-only lookup')
        current = readback.get('currentControlReadback', {})
        check(current.get('schemaVersion') == 1 and current.get('kind') == 'recorder-post-capture-readback'
            and current.get('readOnly') is True and current.get('postsInput') is False and current.get('hostPID') == pid
            and current.get('identityAuthority') == 'current-exact-id-host-pid-same-verified-setup-axwindow'
            and current.get('retainedReferenceUsedForIdentity') is False and current.get('globalTitleFallbackUsed') is False
            and current.get('expectedDisplay') == item.get('displayString') and current.get('ready') is True
            and current.get('reasons') == [] and type(current.get('systemUptime')) in (int, float)
            and math.isfinite(current['systemUptime']) and current['systemUptime'] >= proof['systemUptime'],
            'Current recorder readback authority/source differs')
        node = current.get('currentControl', {})
        check(type(node.get('exactIDCount')) is int and type(node.get('visibleExactIDCount')) is int
            and node['exactIDCount'] == node['visibleExactIDCount'] == 1 and node.get('present') is True
            and node.get('identifier') == 'shortcutRecorder.undoLastWritingEdit' and node.get('identifierAXError') == 0
            and node.get('role') == 'AXButton' and node.get('roleAXError') == 0 and type(node.get('pid')) is int and node['pid'] == pid
            and node.get('enabled') is True and node.get('enabledAXError') == 0
            and node.get('description') == item.get('displayString') and node.get('descriptionAXError') == 0
            and node.get('idleDisplayMatches') is True and node.get('windowAXError') == 0
            and node.get('windowPresent') is True and node.get('windowSameAsVerifiedSetupAXWindow') is True
            and type(node.get('currentDiffersFromRetained')) is bool,
            'Fresh recorder is not the unique owned button/display in the verified pre-input window')
        window = current.get('verifiedSetupAXWindow', {})
        check(window.get('role') == 'AXWindow' and window.get('roleAXError') == 0
            and window.get('title') == 'RJT Undo control check' and window.get('titleAXError') == 0
            and type(window.get('pid')) is int and window['pid'] == pid and window.get('windowsAXError') == 0
            and type(window.get('titledCount')) is int and window['titledCount'] == 1
            and window.get('uniqueSameReference') is True and window.get('focusedWindowAXError') == 0
            and window.get('focusedWindowIsSetupWindow') is True, 'Verified setup AXWindow changed after capture')
        appkit = current.get('appKit', {})
        check(all(appkit.get(key) is True for key in ('isActive', 'isKeyWindow', 'isVisible', 'appKeyWindowIsSetup', 'uniqueSameWindow'))
            and appkit.get('titledWindowCount') == 1 and appkit.get('frontmostPID') == pid
            and appkit.get('windowNumber') == appkit.get('expectedWindowNumber') == proof['appKit']['windowNumber'],
            'Fresh recorder readback is not in the same active native setup window')
        store = current.get('store', {})
        check(store.get('effectiveEqualsExpected') is True and store.get('decodedEqualsExpected') is True
            and store.get('isShortcutCleared') is False, 'Post-capture stored chord changed during fresh lookup')
        own_state(store.get('ownShortcut', {}), 'post-capture-readback', captured=True)
        check({key: value for key, value in store.get('ownShortcut', {}).items() if key != 'phase'}
            == {key: value for key, value in states.get('afterReadback', {}).items() if key != 'phase'},
            'Fresh lookup and final readback observed different stored bytes')
        # The old AX object may survive or expire across SwiftUI rendering. Its
        # raw state describes the transition and never grants current identity.
        retained = readback.get('retainedReferenceAfterCapture', {})
        check('getPidPID' in retained and (retained['getPidPID'] is None
            or type(retained['getPidPID']) is int and retained['getPidPID'] > 0),
            'Malformed retained-reference PID diagnostic')
        for key in ('role', 'identifier', 'description', 'window'):
            observation = retained.get(key, {})
            check(set(observation) == {'axError', 'present', 'string'}
                and type(observation.get('axError')) is int and type(observation.get('present')) is bool
                and (observation.get('string') is None or isinstance(observation['string'], str)),
                'Malformed retained-reference raw diagnostic: ' + key)
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
    def policy_snapshot(item):
        keys = {'restoreClipboardAfterPaste', 'clipboardRestoreDelay'}
        check(isinstance(item, dict) and set(item) == {'effective', 'persistent', 'registered'}, 'Policy snapshot must contain only the three bounded observations')
        if not isinstance(item, dict):
            return
        effective = item.get('effective', {})
        check(set(effective) == keys and type(effective.get('restoreClipboardAfterPaste')) is bool
            and type(effective.get('clipboardRestoreDelay')) in (int, float) and math.isfinite(effective['clipboardRestoreDelay']),
            'Effective policy observation must contain exactly two typed finite values')
        for domain in ('persistent', 'registered'):
            values = item.get(domain, {})
            check(isinstance(values, dict) and set(values) == keys, 'Policy domain must contain only the two nonsecret policy keys')
            for observation in values.values():
                kind = observation.get('type')
                if kind in ('missing', 'unsupported', 'nonfinite'):
                    check(set(observation) == {'type'}, 'Unexpected value in missing/unsupported/nonfinite policy observation')
                elif kind == 'boolean':
                    check(set(observation) == {'type', 'value'} and type(observation.get('value')) is bool, 'Malformed typed policy boolean')
                elif kind == 'number':
                    check(set(observation) == {'type', 'value'} and type(observation.get('value')) in (int, float)
                        and math.isfinite(observation['value']), 'Malformed typed policy number')
                else:
                    check(False, 'Unknown typed policy observation')
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
        bootstrap = value.get('policyBootstrap', {})
        check(set(bootstrap) == {'bundleIdentifier', 'expectedUserHome', 'observedUserHome', 'homeMatchesExpected',
            'publicPreferenceAPIsUsed', 'synchronizeSucceeded', 'hasArgumentOverrides', 'before', 'after'}, 'Policy bootstrap schema differs')
        check(bootstrap.get('bundleIdentifier') == bundle_id and bootstrap.get('publicPreferenceAPIsUsed') is True
            and bootstrap.get('synchronizeSucceeded') is True and bootstrap.get('hasArgumentOverrides') is False,
            'Public preference bootstrap identity/write/readback failed')
        for key in ('expectedUserHome', 'observedUserHome'):
            check(isinstance(bootstrap.get(key), str) and Path(bootstrap[key]).is_absolute(), 'Actual policy home observation missing')
        check(type(bootstrap.get('homeMatchesExpected')) is bool, 'Home-match observation must be boolean')
        check(bootstrap.get('expectedUserHome') == expected_home, 'Policy bootstrap expected home differs from actual launch environment')
        for key in ('before', 'after'):
            policy_snapshot(bootstrap.get(key))
        after = bootstrap.get('after', {})
        check(after.get('effective') == {'restoreClipboardAfterPaste': True, 'clipboardRestoreDelay': 2.0}
            and after.get('effective', {}).get('restoreClipboardAfterPaste') is True, 'Public preference APIs did not establish effective policy')
        expected_policy = {'restoreClipboardAfterPaste': {'type': 'boolean', 'value': True},
            'clipboardRestoreDelay': {'type': 'number', 'value': 2.0}}
        for domain in ('persistent', 'registered'):
            check(after.get(domain) == expected_policy and after.get(domain, {}).get('restoreClipboardAfterPaste', {}).get('value') is True,
                'Actual typed ' + domain + ' policy differs after public setter readback')
        shortcut = value.get('shortcut', {})
        check(shortcut.get('recordedViaActualRecorder') is True and shortcut.get('keyCode') == 32
            and shortcut.get('modifierFlagsRawValue') == 1835008 and bool(shortcut.get('displayString')), 'Actual configured recorder chord differs')
        control(shortcut.get('recorderControl'), 'shortcutRecorder.undoLastWritingEdit', ['AXButton'])
        recorder = shortcut.get('recorderControl', {})
        click(recorder.get('click'), recorder, 'shortcutRecorder.undoLastWritingEdit', ['AXButton'], 'shortcut.recorder')
        recorder_capture(shortcut)
        records = value.get('cases', [])
        check(isinstance(records, list) and [item.get('id') for item in records] == cases, 'Four exact ordered case records required')
        selected = exact_range(len(units(prefix)), len(units(passage)))
        for item in records:
            name = item['id']
            is_menu = name.endswith('-menu')
            editor = 'textedit' if name.startswith('textedit-') else 'safari'
            bundle = 'com.apple.TextEdit' if editor == 'textedit' else 'com.apple.Safari'
            case_original, replacement, case_selected = case_text_fixture(name)
            result = prefix + replacement + suffix
            caret = exact_range(len(units(prefix + replacement)), 0)
            check(item.get('editor') == editor and item.get('commandKind') == ('menu' if is_menu else 'shortcut'), 'Wrong editor/command case')
            check(type(item.get('forwardAttempts')) is int and item['forwardAttempts'] == 1
                and type(item.get('forwardConfirmations')) is int and item['forwardConfirmations'] == 1, 'Forward was not confirmed once')
            check(item.get('originalUTF16') == units(case_original) and item.get('resultUTF16') == units(result)
                and item.get('originalRange') == case_selected, 'Claimed before/result oracle differs')
            snapshot(item.get('before'), case_original, case_selected, bundle)
            snapshot(item.get('forward'), result, caret, bundle)
            snapshot(item.get('restored'), case_original, case_selected, bundle)
            check(len({(item[key]['pid'], item[key]['token']) for key in ('before', 'forward', 'restored')}) == 1,
                'Product command switched captured process/document')
            if is_menu:
                menu(item.get('command', {}), True, name + '-menu')
                click(item['command'].get('activationClick'), item['command'], 'undoLastWritingEdit.menuCommand', ['AXMenuItem'], 'case.' + name + '.menu-command')
            else:
                check(item.get('command') == {'kind': 'configured-global-shortcut', 'keyCode': 32,
                    'modifierFlagsRawValue': 1835008, 'nativeEventsPosted': 2}, 'Actual registered shortcut invocation differs')
            notice(item.get('notice'), restored_message)
            check(item.get('noticeWasAbsentBeforeCommand') is True, 'A stale product notice could satisfy the new command')
            check(item.get('capabilityConsumed') is True and item.get('screenshots') == [name + '-forward.png', name + '-restored.png'],
                'Capability consumption or exact capture names differ')
        states = value.get('stateChecks', {})
        check(set(states) == {'unavailable', 'busy', 'focusRefusal'} and all(item.get('passed') is True for item in states.values()), 'Three exact control states must pass')
        menu(states['unavailable']['menu'], False, 'unavailable-menu')
        dismissal(states['unavailable'].get('dismissal', {}))
        busy = states['busy']
        menu(busy['menu'], False, 'busy-menu')
        dismissal(busy.get('dismissal', {}))
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


def verify_readiness_observations(click, checkpoint, pid):
    summary = click['readiness']
    names = summary['observations']
    expected_names = ['click-readiness-' + checkpoint + '-attempt-' + str(n) + '.json'
        for n in range(1, summary['attemptCount'] + 1)]
    require(names == expected_names and summary['finalObservation'] == names[-1], 'Readiness file inventory differs')
    hashes, observed = {}, []
    for index, name in enumerate(names, 1):
        path = native / name
        require(path.is_file() and not path.is_symlink(), 'Readiness observation missing or symlinked')
        raw = path.read_bytes()
        item = json.loads(raw)
        require(item['schemaVersion'] == 1 and item['kind'] == 'native-click-preinput-readiness-observation'
            and item['diagnosticOnly'] is True and item['experiment'] == 'preinput-readiness-calibration'
            and item['checkpoint'] == 'click.' + checkpoint and type(item['attempt']) is int and item['attempt'] == index
            and item['maxAttempts'] == 6 and item['inputPosted'] is False and type(item['hostPID']) is int and item['hostPID'] == pid
            and type(item['systemUptime']) in (int, float) and math.isfinite(item['systemUptime']),
            'Readiness observation source/attempt/input/host binding differs')
        require(item['ready'] is (index == len(names)), 'Input was retried after a ready observation')
        require(item['reason'] is None if item['ready'] else isinstance(item['reason'], str) and bool(item['reason']),
            'Readiness reason does not match its decision')
        hashes[name] = digest(raw)
        observed.append(item)
    final = observed[-1]
    identity = final['identity']
    menu_identity = click['identityContract'] == 'status-owned-native-menu-item-title'
    require(identity.get('attempted') is True and identity.get('uniqueCount') == 1 and identity.get('sameReferenceAsLookup') is True
        and identity.get('scope') == ('retained-status-subtree' if menu_identity else 'host-owned-nodes'), 'Readiness target identity differs')
    require(final['nativeMenuIdentity'] == click['nativeMenuIdentity'] if menu_identity
        else final['nativeMenuIdentity'] == {'attempted': False}, 'Ready native-menu proof differs from actual activation')
    target, frame, display, hit = (final[k] for k in ('target', 'frame', 'displays', 'hitTest'))
    require(target['attempted'] is True and target['enabled'] is True and target['pid'] == pid
        and target['identifier'] == click['targetID'] and target['role'] == click['targetRole']
        and target['identityContract'] == click['identityContract'], 'Ready target differs from clicked control')
    require(all(frame[k] is True for k in ('attempted', 'finitePositive', 'positionRead', 'sizeRead', 'positionDecoded', 'sizeDecoded'))
        and {k: frame[k] for k in ('x', 'y', 'width', 'height')} == click['targetFrame']
        and frame['center'] == click['point'], 'Ready AX geometry differs from click')
    require(display['attempted'] is True and display['apiError'] == 0
        and type(display['count']) is int and 1 <= display['count'] <= 32
        and display['count'] == len(display['displays']), 'Ready display API facts invalid')
    containing = []
    for candidate_display in display['displays']:
        bounds = candidate_display['bounds']
        require(set(bounds) == {'x', 'y', 'width', 'height'} and all(type(v) in (int, float) and math.isfinite(v) for v in bounds.values()),
            'Retained display rectangle is not finite')
        target_frame = click['targetFrame']
        contains = bounds['x'] <= target_frame['x'] and bounds['y'] <= target_frame['y'] \
            and target_frame['x'] + target_frame['width'] <= bounds['x'] + bounds['width'] \
            and target_frame['y'] + target_frame['height'] <= bounds['y'] + bounds['height']
        require(candidate_display['containsTarget'] is contains, 'Display containment observation differs from raw rectangles')
        if contains:
            containing.append(candidate_display)
    require(display['containingCount'] == 1 and len(containing) == 1
        and containing[0]['id'] == click['activeDisplayID'] and containing[0]['bounds'] == click['activeDisplayBounds'],
        'Ready control is not contained in exactly the clicked display')
    require(hit['attempted'] is True and hit['axError'] == 0 and hit['elementPresent'] is True
        and hit['pid'] == pid and hit['reachedTarget'] is True and hit['depth'] == click['hitDepth'] and hit['point'] == click['point'],
        'Ready owned hit differs from click')
    window, recheck = final['window'], final['frameRecheck']
    require(window['attempted'] is True and window['policy'] == click['windowPolicy']
        and window['targetWindowPresent'] is click['targetWindowPresent'] and window['hitWindowPresent'] is click['hitWindowPresent']
        and recheck['attempted'] is True and recheck['finitePositive'] is True and recheck['stable'] is True
        and {k: recheck[k] for k in ('x', 'y', 'width', 'height')} == click['targetFrame'], 'Ready window/frame recheck differs')
    require(window.get('windowOwnedByHost') is True if click['windowPolicy'] == 'same-window'
        else window.get('menuAncestorRole') == click['menuAncestorRole'], 'Ready window/menu ancestry proof differs')
    stages = [json.loads((native / name).read_text()) for name in progress_files()]
    def sequence(stage):
        matches = [item['sequence'] for item in stages if item['stage'] == stage]
        require(len(matches) == 1, 'Missing/duplicate input or final observation progress marker: ' + stage)
        return matches[0]
    require(sequence('click.' + checkpoint + '.a' + str(len(names)) + '.observation-write.after')
        < sequence('click.' + checkpoint + '.post.before') < sequence('click.' + checkpoint + '.post.after'),
        'Input was not posted once after its final immutable readiness observation')
    return hashes


def verify_recorder_capture_preinput(shortcut, pid):
    name = 'shortcut-capture-preinput.json'
    require(shortcut['capturePreInputFile'] == name, 'Recorder pre-input file differs')
    path = native / name
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 65536, 'Recorder pre-input evidence missing or unsafe')
    raw = path.read_bytes()
    value = json.loads(raw)
    expected_input = dict(shortcut['captureInput'], inputPosted=False)
    require(value == {'schemaVersion': 1, 'kind': 'recorder-capture-preinput', 'input': expected_input,
        'finalProof': shortcut['captureProof'], 'ownShortcutBeforeInput': shortcut['ownShortcutState']['beforeInput']},
        'Recorder immutable pre-input proof differs from observed capture/readback')
    progress = [json.loads(p.read_text()) for p in sorted((native / 'progress').glob('*.json'))]
    def sequence(stage):
        found = [item for item in progress if item.get('stage') == stage]
        require(len(found) == 1 and found[0].get('pid') == pid, 'Missing, duplicate or foreign recorder input marker')
        return found[0]['sequence']
    require(sequence('shortcut.capture-preinput-write.after') < sequence('shortcut.capture-post.before')
        < sequence('shortcut.capture-post.after'), 'Recorder input was not posted once after immutable pre-input proof')
    return {name: digest(raw)}


def recorder_capture_binding_self_test(shortcut):
    global native
    saved = native
    try:
        with tempfile.TemporaryDirectory(prefix='rjt-recorder-capture-binding-') as directory:
            for scenario in ('positive', 'posted-early', 'foreign-focus', 'changed-state', 'foreign-marker', 'duplicate-post'):
                native = Path(directory) / scenario
                native.mkdir()
                (native / 'progress').mkdir()
                value = {'schemaVersion': 1, 'kind': 'recorder-capture-preinput',
                    'input': dict(copy.deepcopy(shortcut['captureInput']), inputPosted=False),
                    'finalProof': copy.deepcopy(shortcut['captureProof']),
                    'ownShortcutBeforeInput': copy.deepcopy(shortcut['ownShortcutState']['beforeInput'])}
                if scenario == 'posted-early':
                    value['input']['inputPosted'] = True
                elif scenario == 'foreign-focus':
                    value['finalProof']['systemFocus']['focusedApplicationPID'] = 43
                elif scenario == 'changed-state':
                    value['ownShortcutBeforeInput']['dataPresent'] = True
                (native / 'shortcut-capture-preinput.json').write_text(json.dumps(value))
                stages = ['shortcut.capture-preinput-write.after', 'shortcut.capture-post.before', 'shortcut.capture-post.after']
                if scenario == 'duplicate-post':
                    stages.append(stages[-1])
                for number, stage in enumerate(stages, 1):
                    (native / 'progress' / (str(number) + '.json')).write_text(json.dumps(
                        {'stage': stage, 'sequence': number, 'pid': 43 if scenario == 'foreign-marker' else 42}))
                try:
                    result = verify_recorder_capture_preinput(shortcut, 42)
                except RuntimeError:
                    require(scenario != 'positive', 'Valid recorder pre-input binding rejected')
                else:
                    require(scenario == 'positive' and len(result) == 1, 'Unsafe recorder pre-input binding accepted')
        print('Recorder capture file bindings passed: one owned-PID input positive and five early/foreign/changed/duplicate controls. Metadata only; no keyboard input executed.')
    finally:
        native = saved


def classify_native(host, live):
    value = json.loads((native / 'result.json').read_text())
    configuration = json.loads((output / 'configuration.json').read_text())
    verify_profile_configuration(configuration)
    errors = receipt_errors(value, host['executable_path'], live['pid'], configuration['CFFIXED_USER_HOME'])
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
        try:
            hashes.update(verify_recorder_capture_preinput(value['shortcut'], live['pid']))
        except (RuntimeError, OSError, KeyError, TypeError, ValueError) as error:
            errors.append('Recorder capture evidence failed: ' + str(error))
        clicks = [('shortcut.recorder', value['shortcut']['recorderControl']['click']),
            ('menu.unavailable-menu.status', value['stateChecks']['unavailable']['menu']['statusClick']),
            ('menu.busy-menu.status', value['stateChecks']['busy']['menu']['statusClick'])]
        for item in value['cases']:
            if item['commandKind'] == 'menu':
                clicks += [('menu.' + item['id'] + '-menu.status', item['command']['statusClick']),
                    ('case.' + item['id'] + '.menu-command', item['command']['activationClick'])]
        for checkpoint, click in clicks:
            try:
                hashes.update(verify_readiness_observations(click, checkpoint, live['pid']))
            except (RuntimeError, OSError, KeyError, TypeError, ValueError) as error:
                errors.append('Readiness evidence failed: ' + str(error))
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
    def click_fixture(target, checkpoint):
        windowless = target['role'] in ('AXMenuItem', 'AXMenuBarItem')
        name = 'click-readiness-' + checkpoint + '-attempt-1.json'
        return {'kind': 'native-mouse-click', 'eventTypes': ['leftMouseDown', 'leftMouseUp'], 'eventCount': 2,
            'tap': 'cghidEventTap', 'clickState': 1, 'flagsRawValue': 0, 'hostPID': 42, 'hitPID': 42,
            'targetID': target['id'], 'targetRole': target['role'], 'identityContract': 'identifier',
            'targetFrame': copy.deepcopy(target['frame']), 'point': {'x': 51, 'y': 13},
            'activeDisplayID': 1, 'activeDisplayBounds': {'x': 0, 'y': 0, 'width': 1024, 'height': 768},
            'hitDepth': 0, 'sameTargetOrDescendant': True, 'uniqueTarget': True, 'frameStable': True,
            'targetOwnedByHost': True, 'hitOwnedByHost': True,
            'windowPolicy': 'windowless-native-menu' if windowless else 'same-window',
            'targetWindowPresent': not windowless, 'hitWindowPresent': not windowless,
            'sameWindow': not windowless, 'windowOwnedByHost': not windowless, 'nativeMenuAncestry': windowless,
            'menuAncestorRole': 'AXMenuBar' if windowless else '',
            'readiness': {'experiment': 'preinput-readiness-calibration', 'attemptCount': 1, 'maxAttempts': 6,
                'deadlineSeconds': 6, 'intervalMilliseconds': 1000, 'elapsedSeconds': 0.1,
                'noInputBeforeReady': True, 'finalObservationReady': True, 'observations': [name], 'finalObservation': name}}
    def menu(checkpoint, enabled=True):
        target = dict(control('', 'AXMenuItem', enabled), label='Undo Last Writing Edit')
        status = control('undoControlHost.statusItem', 'AXMenuBarItem')
        result = dict(target, kind='product-menu', statusControl=status, statusClick=click_fixture(status, 'menu.' + checkpoint + '.status'))
        result['nativeMenuIdentity'] = menu_proof_fixture(target)
        if enabled:
            case = checkpoint.removesuffix('-menu')
            result['activationClick'] = click_fixture(target, 'case.' + case + '.menu-command')
            result['activationClick'].update(identityContract='status-owned-native-menu-item-title', nativeMenuIdentity=menu_proof_fixture(target))
        return result
    def menu_proof_fixture(target):
        owner = {'role': 'AXMenuBarItem', 'identifier': 'undoControlHost.statusItem', 'pid': 42,
            'identityContract': 'identifier', 'sameRetainedReference': True, 'parentAXError': 0,
            'parentRole': 'AXMenuBar', 'extrasMenuBarPresent': True, 'extrasMenuBarPID': 42, 'parentIsHostExtrasMenuBar': True}
        path = [{'role': 'AXMenu', 'identifier': '', 'title': '', 'pid': 42, 'depth': 1},
            {'role': 'AXMenuItem', 'identifier': target['id'], 'title': 'Undo Last Writing Edit', 'pid': 42, 'depth': 2}]
        return {'schemaVersion': 2, 'kind': 'native-menu-bridge-identity', 'contract': 'status-owned-native-menu-item-title',
            'identityAuthority': 'retained-status-downward-subtree', 'upwardParentAuthorizes': False,
            'expectedTitle': 'Undo Last Writing Edit', 'expectedRole': 'AXMenuItem', 'hostPID': 42,
            'identifierRequired': False, 'globalSearchUsed': False, 'textFallbackUsed': False, 'maxDepth': 4, 'maxNodes': 64,
            'status': owner, 'traversal': {'discoveredCount': 3, 'expandedCount': 3, 'truncated': False,
                'unreadableChildren': [], 'exactMatchCount': 1, 'otherRoleTitleMatches': 0}, 'uniqueMatch': True,
            'downwardPath': path,
            'downwardProof': {'rootIsRetainedStatus': True, 'statusParentIsHostExtrasMenuBar': True,
                'fullyReadable': True, 'truncated': False, 'uniqueExactMatch': True, 'pathLength': 2,
                'allHostPID': True, 'menuRole': 'AXMenu', 'commandRole': 'AXMenuItem', 'exactTitle': 'Undo Last Writing Edit'},
            'upwardParentDiagnostics': {'diagnosticOnly': True, 'authorizationCondition': False, 'maxLevels': 2,
                'observations': [dict(path[0], level=1, axError=0, elementPresent=True, expectedDownwardRole='AXMenu',
                    matchesDownwardPath=True, isRetainedStatus=False),
                    {'role': 'AXMenuBar', 'identifier': '', 'title': None, 'pid': 42, 'depth': 0, 'level': 2,
                        'axError': 0, 'elementPresent': True, 'expectedDownwardRole': 'AXMenuBarItem',
                        'matchesDownwardPath': False, 'isRetainedStatus': False}],
                'reciprocalToDownwardPath': False, 'reachesRetainedStatus': False},
            'command': {'role': 'AXMenuItem', 'title': 'Undo Last Writing Edit',
                'pid': 42, 'identifier': target['id'], 'identifierEmpty': target['id'] == '', 'enabled': target['enabled'],
                'frame': copy.deepcopy(target['frame'])}, 'proven': True, 'reason': None}
    def dismissal_fixture():
        return {'kind': 'native-menu-dismissal', 'contract': 'same-status-owned-menu-not-displayed',
            'escapeEventsPosted': 2, 'inputRetries': 0, 'polls': 1, 'statusRetainedFromOpen': True,
            'closure': {'hostPID': 42, 'axErrorTreatedAsClosed': False, 'hitAXError': 0, 'hitPID': 99,
                'closed': True, 'reason': None, 'statusSelected': False, 'evidence': 'hit-other-process'}}
    def capture_fixture():
        expected = {'kind': 'key', 'keyCode': 32, 'modifierFlagsRawValue': 1835008, 'displayString': 'fixture'}
        def state(phase, captured=False, fresh=False):
            result = {'phase': phase, 'action': 'undoLastWritingEdit', 'clearedValue': None if captured or fresh else True,
                'clearedValueKind': 'nil' if captured or fresh else 'true', 'isShortcutCleared': not captured and not fresh,
                'dataPresent': captured, 'effective': expected if captured else None, 'effectiveEqualsExpected': captured}
            if captured:
                result.update(dataBytes=100, dataSHA256='1' * 64, decodeSucceeded=True, decoded=expected)
            return result
        conflict = {'api': 'ShortcutValidator.validationError', 'action': 'undoLastWritingEdit', 'expected': expected,
            'conflictFree': True, 'issue': None}
        proof = {'schemaVersion': 1, 'kind': 'recorder-capture-proof', 'phase': 'final-preinput', 'readOnly': True,
            'inputPosted': False, 'hostPID': 42, 'systemUptime': 100.0, 'expectedPlaceholder': 'Press shortcut',
            'ready': True, 'reasons': [], 'ownShortcut': state('final-preinput'), 'conflictCheck': conflict,
            'recorder': {'identifier': 'shortcutRecorder.undoLastWritingEdit', 'uniqueCount': 1,
                'sameReferenceAsLookup': True, 'role': 'AXButton', 'pid': 42, 'enabled': True,
                'description': 'Press shortcut', 'labelIsRecordingPlaceholder': True},
            'axWindow': {'axError': 0, 'windowsAXError': 0, 'focusedWindowAXError': 0, 'present': True, 'pid': 42,
                'role': 'AXWindow', 'title': 'RJT Undo control check', 'titledCount': 1, 'uniqueSameReference': True,
                'focusedWindowIsSetupWindow': True},
            'systemFocus': {'focusedApplicationAXError': 0, 'focusedApplicationPID': 42, 'frontmostPID': 42,
                'focusedElementAXError': 0, 'focusedElementPresent': True, 'focusedElementPID': 42},
            'appKit': {'isActive': True, 'isKeyWindow': True, 'isVisible': True, 'appKeyWindowIsSetup': True,
                'uniqueSameWindow': True, 'titledWindowCount': 1, 'windowNumber': 1}}
        current = {'schemaVersion': 1, 'kind': 'recorder-post-capture-readback', 'readOnly': True, 'postsInput': False,
            'hostPID': 42, 'systemUptime': 101.0, 'identityAuthority': 'current-exact-id-host-pid-same-verified-setup-axwindow',
            'retainedReferenceUsedForIdentity': False, 'globalTitleFallbackUsed': False, 'expectedDisplay': 'fixture',
            'ready': True, 'reasons': [],
            'currentControl': {'exactIDCount': 1, 'visibleExactIDCount': 1, 'present': True,
                'identifier': 'shortcutRecorder.undoLastWritingEdit', 'identifierAXError': 0,
                'role': 'AXButton', 'roleAXError': 0, 'pid': 42, 'enabled': True, 'enabledAXError': 0,
                'description': 'fixture', 'descriptionAXError': 0, 'idleDisplayMatches': True,
                'windowAXError': 0, 'windowPresent': True, 'windowSameAsVerifiedSetupAXWindow': True,
                'currentDiffersFromRetained': True},
            'verifiedSetupAXWindow': {'role': 'AXWindow', 'roleAXError': 0, 'title': 'RJT Undo control check',
                'titleAXError': 0, 'pid': 42, 'windowsAXError': 0, 'titledCount': 1, 'uniqueSameReference': True,
                'focusedWindowAXError': 0, 'focusedWindowIsSetupWindow': True},
            'appKit': {'isActive': True, 'isKeyWindow': True, 'isVisible': True, 'appKeyWindowIsSetup': True,
                'uniqueSameWindow': True, 'titledWindowCount': 1, 'windowNumber': 1, 'expectedWindowNumber': 1, 'frontmostPID': 42},
            'store': {'effectiveEqualsExpected': True, 'decodedEqualsExpected': True, 'isShortcutCleared': False,
                'ownShortcut': state('post-capture-readback', captured=True)}}
        retained = {'getPidPID': 42, **{key: {'axError': -25202, 'present': False, 'string': None}
            for key in ('role', 'identifier', 'description', 'window')}}
        return {'captureInput': {'contract': 'focused-recorder-capture-postToPid', 'route': 'CGEvent.postToPid',
            'pattern': 'LiveWritingEditor.key', 'eventSource': 'nil', 'hostPID': 42, 'targetPID': 42,
            'eventTypes': ['keyDown', 'keyUp'], 'eventCount': 2,
            'events': [{'type': kind, 'keyCode': 32, 'flagsRawValue': 1835008} for kind in ('keyDown', 'keyUp')],
            'eventsExact': True, 'keyCode': 32, 'modifierFlagsRawValue': 1835008, 'eventFlagsRawValue': 1835008,
            'fallbackUsed': False, 'retryUsed': False, 'physicalKeyboard': False,
            'laterGlobalInvocationRoute': 'postChord-cghidEventTap-unchanged', 'finalProofReady': True, 'inputPosted': True},
            'captureProof': proof, 'capturePreInputFile': 'shortcut-capture-preinput.json', 'conflictBeforeClick': conflict,
            'ownShortcutState': {'beforeClick': state('before-click', fresh=True), 'beforeInput': state('before-input'),
                'afterReadback': state('after-readback', captured=True)},
            'readback': {'storeEqualsExpected': True, 'recorderIdleDisplayMatches': True, 'recorderDescription': 'fixture',
                'displaySource': 'current-control', 'currentReadbackPolls': 1,
                'currentControlReadback': current, 'retainedReferenceAfterCapture': retained}}
    def notice(message):
        return dict(control('undoLastWritingEdit.notice'), expectedMessage=message, label=message)
    def snapshot(text, selected, bundle, token='RJT-Writing-Live-00000000-0000-4000-8000-000000000001', focused=True):
        data = units(text)
        return {'valueUTF16': data, 'range': selected, 'selectedTextUTF16': data[selected['location']:selected['location'] + selected['length']],
            'sameProcess': True, 'sameFocusedEditor': focused, 'sameWindow': True, 'windowPresent': True, 'targetAlive': True,
            'pid': 100, 'bundleIdentifier': bundle, 'token': token, 'usesSystemPaste': bundle == 'com.apple.Safari'}
    selected = exact_range(len(units(prefix)), len(units(passage)))
    recorder = control('shortcutRecorder.undoLastWritingEdit')
    recorder['click'] = click_fixture(recorder, 'shortcut.recorder')
    value = {'schemaVersion': 1, 'completed': True, 'selectedCases': cases, 'executedCases': cases,
        'host': {'pid': 42, 'bundleIdentifier': bundle_id, 'executablePath': '/fixture/app'},
        'runtimeBounds': {'productMenuOrShortcut': True, 'normalAppComposition': False, 'fullPipeline': False, 'ASR': False, 'provider': False},
        'forwardBoundary': 'Real WritingTarget delivery into the sole engine-owned controller',
        'pastePreferences': {'restoreClipboardAfterPaste': True, 'clipboardRestoreDelay': 2.0, 'hasArgumentOverrides': False},
        'issues': [], 'failure': None, 'shortcut': {'recordedViaActualRecorder': True, 'keyCode': 32, 'modifierFlagsRawValue': 1835008,
            'displayString': 'fixture', 'recorderControl': recorder}, 'cases': []}
    value['shortcut'].update(capture_fixture())
    for name in cases:
        is_menu = name.endswith('-menu')
        case_original, replacement, case_selected = case_text_fixture(name)
        bundle = 'com.apple.TextEdit' if name.startswith('textedit') else 'com.apple.Safari'
        result = prefix + replacement + suffix
        token = 'RJT-Writing-Live-00000000-0000-4000-8000-' + str(len(value['cases']) + 1).zfill(12)
        value['cases'].append({'id': name, 'editor': 'textedit' if name.startswith('textedit') else 'safari',
            'commandKind': 'menu' if is_menu else 'shortcut', 'forwardAttempts': 1, 'forwardConfirmations': 1,
            'originalUTF16': units(case_original), 'resultUTF16': units(result), 'originalRange': case_selected,
            'before': snapshot(case_original, case_selected, bundle, token), 'forward': snapshot(result, exact_range(len(units(prefix + replacement)), 0), bundle, token),
            'restored': snapshot(case_original, case_selected, bundle, token), 'command': menu(name + '-menu') if is_menu else {'kind': 'configured-global-shortcut',
                'keyCode': 32, 'modifierFlagsRawValue': 1835008, 'nativeEventsPosted': 2}, 'notice': notice(restored_message),
            'capabilityConsumed': True, 'noticeWasAbsentBeforeCommand': True,
            'screenshots': [name + '-forward.png', name + '-restored.png']})
    value['stateChecks'] = {'unavailable': {'passed': True, 'menu': menu('unavailable-menu', False), 'dismissal': dismissal_fixture()},
        'busy': {'passed': True, 'recordingStateFixture': 'busy', 'menu': menu('busy-menu', False), 'notice': notice(busy_message),
            'observed': copy.deepcopy(value['cases'][1]['forward']), 'capabilityRetained': True, 'dismissal': dismissal_fixture()},
        'focusRefusal': {'passed': True, 'capabilityRetired': True, 'differentWindow': True, 'notice': notice(refused_message),
            'sourceAfter': snapshot(prefix + 'Source remains e\u0301 🧪' + suffix, exact_range(len(units(prefix + 'Source remains e\u0301 🧪')), 0), 'com.apple.TextEdit', 'RJT-Writing-Live-00000000-0000-4000-8000-000000000005', focused=False),
            'otherBefore': snapshot(original, selected, 'com.apple.TextEdit', 'RJT-Writing-Live-00000000-0000-4000-8000-000000000006'),
            'otherAfter': snapshot(original, selected, 'com.apple.TextEdit', 'RJT-Writing-Live-00000000-0000-4000-8000-000000000006')}}
    policy = {'restoreClipboardAfterPaste': {'type': 'boolean', 'value': True}, 'clipboardRestoreDelay': {'type': 'number', 'value': 2.0}}
    value['policyBootstrap'] = {'bundleIdentifier': bundle_id, 'expectedUserHome': '/fixture/isolated-user',
        'observedUserHome': '/Users/fixture', 'homeMatchesExpected': False, 'publicPreferenceAPIsUsed': True,
        'synchronizeSucceeded': True, 'hasArgumentOverrides': False,
        'before': {'effective': {'restoreClipboardAfterPaste': True, 'clipboardRestoreDelay': 2.0},
            'persistent': {key: {'type': 'missing'} for key in policy}, 'registered': copy.deepcopy(policy)},
        'after': {'effective': {'restoreClipboardAfterPaste': True, 'clipboardRestoreDelay': 2.0},
            'persistent': copy.deepcopy(policy), 'registered': copy.deepcopy(policy)}}
    for name in cases:
        case_original, case_replacement, case_range = case_text_fixture(name)
        safari = name.startswith('safari-')
        source_utf8 = b'target \xc3\xa9' if safari else b'target e\xcc\x81'
        source_utf16 = [116, 97, 114, 103, 101, 116, 32, 233] if safari else [116, 97, 114, 103, 101, 116, 32, 101, 769]
        require(case_original.encode('utf-8') == prefix.encode('utf-8') + source_utf8 + suffix.encode('utf-8')
            and units(case_original)[case_range['location']:case_range['location'] + case_range['length']] == source_utf16,
            'Positive per-editor fixture source differs from known exact UTF-8/UTF-16 scalar bytes')
        accent = b'\xc3\xa9' if safari else b'e\xcc\x81'
        require(accent in case_replacement.encode('utf-8') and (769 not in units(case_replacement) if safari else 769 in units(case_replacement)),
            'Positive per-editor fixture output uses the wrong scalar bytes')
    require(not receipt_errors(value, '/fixture/app', 42, '/fixture/isolated-user'), 'Valid classifier fixture rejected')
    retained_still_valid = copy.deepcopy(value)
    readback = retained_still_valid['shortcut']['readback']
    readback['currentControlReadback']['currentControl']['currentDiffersFromRetained'] = False
    readback['retainedReferenceAfterCapture'] = {'getPidPID': 42, **{key: {'axError': 0, 'present': True, 'string': text}
        for key, text in [('role', 'AXButton'), ('identifier', 'shortcutRecorder.undoLastWritingEdit'),
            ('description', 'fixture'), ('window', None)]}}
    require(not receipt_errors(retained_still_valid, '/fixture/app', 42, '/fixture/isolated-user'),
        'Current owned recorder readback incorrectly requires the old AX reference to expire')
    recorder_capture_binding_self_test(value['shortcut'])
    no_focused_element = copy.deepcopy(value)
    no_focused_element['shortcut']['captureProof']['systemFocus'].update(
        focusedElementAXError=-25212, focusedElementPresent=False, focusedElementPID=None)
    require(not receipt_errors(no_focused_element, '/fixture/app', 42, '/fixture/isolated-user'),
        'An app-wide local recorder incorrectly required the focused element to be the recorder itself')
    parent_read_error = copy.deepcopy(value)
    diagnostic = parent_read_error['cases'][0]['command']['nativeMenuIdentity']['upwardParentDiagnostics']
    diagnostic['observations'] = [{'level': 1, 'axError': -25212, 'elementPresent': False,
        'expectedDownwardRole': 'AXMenu', 'matchesDownwardPath': False, 'isRetainedStatus': False}]
    require(not receipt_errors(parent_read_error, '/fixture/app', 42, '/fixture/isolated-user'),
        'Diagnostic parent-read error was incorrectly used as identity authority')
    unsupported_actions = copy.deepcopy(value)
    for target in [unsupported_actions['shortcut']['recorderControl'],
        *[item['command'] for item in unsupported_actions['cases'] if item['commandKind'] == 'menu'],
        *[item['menu'] for item in unsupported_actions['stateChecks'].values() if 'menu' in item]]:
        target.update(actions=[], actionsAXError=-25212)
        if 'statusControl' in target:
            target['statusControl'].update(actions=[], actionsAXError=-25212)
    require(not receipt_errors(unsupported_actions, '/fixture/app', 42, '/fixture/isolated-user'),
        'Native mouse receipt incorrectly depends on AXPress action-name support')
    def substitute_source(record, index, text):
        # Keep the mutated receipt internally coherent, so rejection tests the
        # known editor fixture boundary rather than contradictory metadata.
        item = record['cases'][index]
        source = prefix + text + suffix
        source_range = exact_range(len(units(prefix)), len(units(text)))
        item.update(originalUTF16=units(source), originalRange=source_range)
        for key in ('before', 'restored'):
            item[key].update(valueUTF16=units(source), range=source_range, selectedTextUTF16=units(text))
    def substitute_output(record, index, text):
        item = record['cases'][index]
        result = prefix + text + suffix
        item['resultUTF16'] = units(result)
        item['forward'].update(valueUTF16=units(result), range=exact_range(len(units(prefix + text)), 0), selectedTextUTF16=[])
    mutations = [lambda v: v.update(completed=False), lambda v: v['selectedCases'].pop(), lambda v: v['cases'].pop(),
        lambda v: v['host'].update(pid=99), lambda v: v['runtimeBounds'].update(normalAppComposition=True),
        lambda v: v['shortcut'].update(recordedViaActualRecorder=False), lambda v: v['shortcut']['recorderControl']['click'].update(eventCount=1),
        lambda v: v['cases'][0]['command'].update(role='AXGroup'), lambda v: v['cases'][0]['command'].update(enabled=False),
        lambda v: v['cases'][0].update(forwardAttempts=2), lambda v: v['cases'][0]['restored'].update(valueUTF16=units('wrong')),
        lambda v: v['cases'][1]['forward'].update(valueUTF16=units(prefix + 'Short é 😀' + suffix)),
        lambda v: v['cases'][0]['restored'].update(sameFocusedEditor=False), lambda v: v['cases'][0]['restored'].update(token='foreign'),
        lambda v: v['cases'][2]['forward'].update(usesSystemPaste=False),
        lambda v: v['cases'][0].update(noticeWasAbsentBeforeCommand=False),
        lambda v: v['pastePreferences'].update(hasArgumentOverrides=True),
        lambda v: v['policyBootstrap'].update(publicPreferenceAPIsUsed=False),
        lambda v: v['policyBootstrap']['after']['persistent']['restoreClipboardAfterPaste'].update(type='number'),
        lambda v: v['policyBootstrap']['after']['persistent'].update(clipboardRestoreDelay={'type': 'missing'}),
        lambda v: v['policyBootstrap'].update(hasArgumentOverrides=True),
        lambda v: v['policyBootstrap'].update(expectedUserHome='/different/isolated-user'),
        lambda v: v['policyBootstrap']['after']['registered'].update(clipboardRestoreDelay={'type': 'number', 'value': 0}),
        lambda v: v['cases'][0]['notice'].update(label='invented'), lambda v: v['stateChecks']['busy'].update(capabilityRetained=False),
        lambda v: v['stateChecks']['focusRefusal'].update(differentWindow=False), lambda v: v['issues'].append('cleanup failed'),
        lambda v: v.update(failure='setup failure'),
        lambda v: substitute_source(v, 2, 'target e\u0301'),
        lambda v: substitute_source(v, 0, 'target \u00e9'),
        lambda v: substitute_output(v, 2, replacement_menu),
        lambda v: substitute_output(v, 0, 'Longer 👩🏽‍💻 \u00e9\nRJT, 台灣, 🧑‍🚀.'),
        lambda v: v['cases'][2]['before']['range'].update(length=9),
        lambda v: v['cases'][0]['command']['statusClick'].update(hostPID=43),
        lambda v: v['cases'][0]['command']['statusClick'].update(hitPID=43),
        lambda v: v['cases'][0]['command']['statusClick'].update(sameTargetOrDescendant=False),
        lambda v: v['cases'][0]['command']['statusClick']['point'].update(x=52),
        lambda v: v['cases'][0]['command']['statusClick']['point'].update(x=float('nan')),
        lambda v: v['cases'][0]['command']['statusClick']['activeDisplayBounds'].update(width=10),
        lambda v: v['cases'][0]['command']['statusClick'].update(targetID='foreign'),
        lambda v: v['cases'][0]['command']['statusClick'].update(uniqueTarget=False),
        lambda v: v['cases'][0]['command']['statusClick'].update(frameStable=False),
        lambda v: v['cases'][0]['command']['statusClick'].update(windowPolicy='unknown'),
        lambda v: v['cases'][0]['command']['activationClick'].update(hitDepth=9),
        lambda v: v['cases'][0]['command']['activationClick'].update(eventTypes=['leftMouseDown']),
        lambda v: v['cases'][0]['command']['activationClick'].update(nativeMenuAncestry=False),
        lambda v: v['cases'][0]['command'].pop('activationClick'),
        lambda v: v['stateChecks']['unavailable']['menu'].pop('statusClick'),
        lambda v: v['shortcut']['recorderControl']['click'].update(sameWindow=False),
        lambda v: v['shortcut']['recorderControl']['click']['readiness'].update(noInputBeforeReady=False),
        lambda v: v['shortcut']['recorderControl']['click']['readiness'].update(attemptCount=7),
        lambda v: v['shortcut']['recorderControl']['click']['readiness'].update(finalObservation='../foreign.json'),
        lambda v: v['shortcut']['recorderControl']['click']['readiness'].update(finalObservationReady=False),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity'].update(globalSearchUsed=True),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['status'].update(pid=43),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['status'].update(parentIsHostExtrasMenuBar=False),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['traversal'].update(exactMatchCount=2),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['traversal'].update(truncated=True),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['traversal'].update(unreadableChildren=[{'axError': -1}]),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity'].update(upwardParentAuthorizes=True),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity'].update(schemaVersion=1),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity'].update(identityAuthority='global-title'),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['downwardProof'].update(rootIsRetainedStatus=False),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['downwardProof'].update(allHostPID=False),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['upwardParentDiagnostics'].update(authorizationCondition=True),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['upwardParentDiagnostics'].update(reciprocalToDownwardPath=True),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['upwardParentDiagnostics']['observations'][0].update(level=9),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['downwardPath'][0].update(pid=43),
        lambda v: v['cases'][0]['command']['nativeMenuIdentity']['command'].update(title='Undo'),
        lambda v: v['stateChecks']['unavailable']['dismissal']['closure'].update(hitAXError=-1),
        lambda v: v['stateChecks']['unavailable']['dismissal']['closure'].update(statusSelected=True),
        lambda v: v['stateChecks']['busy']['dismissal'].update(inputRetries=1),
        lambda v: v['shortcut']['captureInput'].update(route='cghidEventTap'),
        lambda v: v['shortcut']['captureInput'].update(targetPID=43),
        lambda v: v['shortcut']['captureInput'].update(eventCount=1),
        lambda v: v['shortcut']['captureInput'].update(retryUsed=True),
        lambda v: v['shortcut']['captureProof']['recorder'].update(labelIsRecordingPlaceholder=False),
        lambda v: v['shortcut']['captureProof']['axWindow'].update(focusedWindowIsSetupWindow=False),
        lambda v: v['shortcut']['captureProof']['systemFocus'].update(focusedApplicationPID=43),
        lambda v: v['shortcut']['captureProof']['systemFocus'].update(focusedElementPID=43),
        lambda v: v['shortcut']['captureProof']['appKit'].update(isKeyWindow=False),
        lambda v: v['shortcut']['ownShortcutState']['beforeClick'].update(dataPresent=True),
        lambda v: v['shortcut']['ownShortcutState']['afterReadback']['effective'].update(keyCode=31),
        lambda v: v['shortcut']['readback'].update(storeEqualsExpected=False),
        lambda v: v['shortcut']['conflictBeforeClick'].update(conflictFree=False),
        lambda v: v['shortcut']['readback'].pop('currentControlReadback'),
        lambda v: v['shortcut']['readback'].update(displaySource='retained-control'),
        lambda v: v['shortcut']['readback']['currentControlReadback'].update(retainedReferenceUsedForIdentity=True),
        lambda v: v['shortcut']['readback']['currentControlReadback'].update(globalTitleFallbackUsed=True),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(exactIDCount=2),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(visibleExactIDCount=True),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(role='AXStaticText'),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(pid=43),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(windowSameAsVerifiedSetupAXWindow=False),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(windowAXError=-25202),
        lambda v: v['shortcut']['readback']['currentControlReadback']['currentControl'].update(description='stale label'),
        lambda v: v['shortcut']['readback']['currentControlReadback']['verifiedSetupAXWindow'].update(pid=43),
        lambda v: v['shortcut']['readback']['currentControlReadback']['verifiedSetupAXWindow'].update(focusedWindowIsSetupWindow=False),
        lambda v: v['shortcut']['readback']['currentControlReadback']['appKit'].update(windowNumber=2, expectedWindowNumber=2),
        lambda v: v['shortcut']['readback']['currentControlReadback']['store'].update(decodedEqualsExpected=False),
        lambda v: v['shortcut']['readback']['currentControlReadback']['store']['ownShortcut'].update(dataSHA256='2' * 64),
        lambda v: v['cases'][3]['forward']['range'].update(location=v['cases'][3]['forward']['range']['location'] + 1)]
    for mutation in mutations:
        invalid = copy.deepcopy(value)
        mutation(invalid)
        require(receipt_errors(invalid, '/fixture/app', 42, '/fixture/isolated-user'), 'Malformed acceptance fixture incorrectly passed')
    print('Undo controls classifier passed: four exact cases and three states; ' + str(len(mutations))
        + ' malformed receipts rejected. No app, clipboard or native interaction executed.')
    compiler_inputs_self_test()
    host_failure_self_test()
    profile_and_sampling_self_test()
    diagnostic_screen_self_test()
    readiness_observation_self_test()


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


def host_failure_self_test():
    # Execute the actual transport loop with process/OS calls replaced, including
    # the poll→ps→nonzero-exit race observed after the failed setup-policy check.
    globals_before = {key: globals()[key] for key in ('output', 'native', 'candidate', 'derived', 'process_identity', 'host_census')}
    popen_before, run_before, sleep_before = subprocess.Popen, subprocess.run, time.sleep
    policy_failure = 'The controls check requires the actual persistent default clipboard restoration policy.'
    with tempfile.TemporaryDirectory(prefix='rjt-undo-host-failure-') as directory:
        base = Path(directory).resolve()
        try:
            for changed in (False, True):
                lane = base / ('changed' if changed else 'unchanged')
                lane.mkdir()
                globals().update(output=lane, native=lane / 'native', candidate=lane / 'candidate', derived=lane / 'derived')
                candidate.mkdir()
                source = candidate / 'owned.swift'
                source.write_text('// before\n')
                removed = candidate / 'removed.swift'
                removed.write_text('// removed\n')
                write_json(output / 'candidate-source.json', candidate_manifest())
                executable = str(lane / 'app/Contents/MacOS/roma just talk')
                identity = {'started_at': 'Wed Oct 28 00:00:00 2026', 'executable_path': executable}
                state = {'mapped': False, 'ps_reads': 0}
                class SimulatedHost:
                    pid = 12345
                    returncode = None
                    def __init__(self, *args, **kwargs):
                        write_json(native / 'result.json', {'completed': False, 'failure': policy_failure, 'issues': [], 'executedCases': []})
                    def poll(self):
                        if state['ps_reads'] >= 2:
                            self.returncode = 1
                        return self.returncode
                    def terminate(self):
                        raise RuntimeError('The completed process must not be terminated')
                def fake_identity(_pid):
                    state['ps_reads'] += 1
                    if state['ps_reads'] == 1:
                        return identity
                    if changed:
                        source.write_text('// changed\n')
                        removed.unlink()
                        (candidate / 'added.json').write_text('{}\n')
                    return None
                def fake_run(command, **kwargs):
                    class Result:
                        returncode, stderr = 0, ''
                        stdout = 'n' + executable + '\n' if '-d' in command else ''
                    return Result()
                globals().update(process_identity=fake_identity, host_census=lambda _executable: [])
                subprocess.Popen, subprocess.run, time.sleep = SimulatedHost, fake_run, lambda _seconds: None
                try:
                    run_host({'executable_path': executable})
                except RuntimeError as error:
                    require(policy_failure in str(error) and 'Host process identity changed' not in str(error), 'Transport masked the actual native setup failure')
                else:
                    raise RuntimeError('Nonzero native setup failure incorrectly passed')
                live = json.loads((output / 'host-live.json').read_text())
                closed = json.loads((output / 'host-closed.json').read_text())
                outcome = json.loads((output / 'host-outcome.json').read_text())
                require(live['exit_code'] == 1 and live['host']['pid'] == 12345 and closed['valid'] is True,
                    'Failed native host lost mapped launch/strict closure evidence')
                require(outcome['native_failure'] == policy_failure and outcome['monitor_error'] is None
                    and outcome['observed_completed_cases'] == [], 'Wrong native failure/zero-execution diagnostics')
                mismatch_paths = list(output.glob('candidate-source-mismatch-*.json'))
                require(bool(mismatch_paths) == changed and bool(outcome['candidate_error']) == changed, 'Candidate mismatch was hidden or invented')
                if changed:
                    mismatch = json.loads(mismatch_paths[0].read_text())
                    require(set(mismatch['added']) == {'added.json'} and set(mismatch['removed']) == {'removed.swift'}
                        and set(mismatch['changed']) == {'owned.swift'} and mismatch['before'] != mismatch['after'],
                        'Candidate before/after hash/path census incomplete')
            print('Host failure transport controls passed: actual nonzero poll/ps race preserves setup failure, zero cases, mapped identity and strict closure; changed-candidate path/hash census records added/removed/changed (2 simulated transport cases). No native process executed.')
        finally:
            globals().update(globals_before)
            subprocess.Popen, subprocess.run, time.sleep = popen_before, run_before, sleep_before


def profile_and_sampling_self_test():
    historical = git('show', '794fa2595f943ae501bbe3407a9dd1120c678f76:scripts/verify-writing-undo-controls.py').decode()
    functions = [node for node in ast.parse(historical).body if isinstance(node, ast.FunctionDef) and node.name == 'run_host']
    require(len(functions) == 1, 'Known-bad source-CWD host transport missing')
    old_namespace = dict(globals())
    exec(compile(ast.Module(body=functions, type_ignores=[]), '<794fa259 run_host>', 'exec'), old_namespace)
    saved = {key: globals()[key] for key in ('output', 'native', 'candidate', 'derived', 'process_identity', 'host_census')}
    popen_before, run_before, sleep_before = subprocess.Popen, subprocess.run, time.sleep
    with tempfile.TemporaryDirectory(prefix='rjt-undo-profile-sample-') as directory:
        base = Path(directory).resolve()
        try:
            for historical_lane in (True, False):
                lane = base / ('known-bad' if historical_lane else 'candidate')
                lane.mkdir()
                globals().update(output=lane, native=lane / 'native', candidate=lane / 'candidate', derived=lane / 'derived')
                candidate.mkdir()
                (candidate / 'owned.swift').write_text('// frozen compiler input\n')
                write_json(output / 'candidate-source.json', candidate_manifest())
                executable = str(lane / 'app/Contents/MacOS/roma just talk')
                identity = {'started_at': 'Wed Oct 28 01:23:51 2026', 'executable_path': executable}
                state = {'finished': False, 'spawn': None}
                class ProfileWriterFixture:
                    pid, returncode = 24716, None
                    def __init__(self, *args, **kwargs):
                        state['spawn'] = kwargs
                        pattern = kwargs['env'].get('LLVM_PROFILE_FILE') or str(Path(kwargs['cwd']) / 'default.profraw')
                        path = Path(pattern.replace('%p', str(self.pid)).replace('%m', 'fixture-binary'))
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(b'')
                        write_json(native / 'result.json', {'completed': True, 'failure': None, 'issues': [], 'executedCases': cases})
                    def poll(self):
                        if state['finished']:
                            self.returncode = 0
                        return self.returncode
                def fake_run(command, **kwargs):
                    class Result:
                        returncode, stderr = 0, ''
                        stdout = 'n' + executable + '\n' if '-d' in command else ''
                    return Result()
                globals().update(process_identity=lambda _pid: identity, host_census=lambda _executable: [])
                subprocess.Popen, subprocess.run = ProfileWriterFixture, fake_run
                time.sleep = lambda _seconds: state.update(finished=True)
                if historical_lane:
                    old_namespace.update({key: globals()[key] for key in saved})
                    # The matched fixture models the actual failed run's unset
                    # LLVM variable, independently of the developer's shell.
                    inherited = os.environ.get('LLVM_PROFILE_FILE')
                    os.environ.pop('LLVM_PROFILE_FILE', None)
                    try:
                        old_namespace['run_host']({'executable_path': executable})
                    finally:
                        if inherited is not None:
                            os.environ['LLVM_PROFILE_FILE'] = inherited
                    try:
                        verify_candidate()
                    except RuntimeError:
                        require((candidate / 'default.profraw').is_file(), 'Known-bad source pollution was not the observed profile filename')
                        print('RED actual 794fa259 run_host: source CWD plus unset LLVM profile destination adds default.profraw to frozen candidate.')
                    else:
                        raise RuntimeError('Known-bad source-CWD profile fixture did not fail source integrity')
                else:
                    run_host({'executable_path': executable})
                    verify_candidate()
                    config = json.loads((output / 'configuration.json').read_text())
                    require(state['spawn']['cwd'] == native and state['spawn']['env']['LLVM_PROFILE_FILE'] == config['LLVM_PROFILE_FILE']
                        and not (candidate / 'default.profraw').exists(), 'Candidate did not control actual Popen working directory/profile environment')
                    for invalid in [dict(config, LLVM_PROFILE_FILE=str(candidate / 'unsafe.profraw')), dict(config, working_directory=str(candidate))]:
                        try:
                            verify_profile_configuration(invalid)
                        except RuntimeError:
                            pass
                        else:
                            raise RuntimeError('Unsafe source-CWD/profile path accepted')
                    (candidate / 'owned.swift').write_text('// changed\n')
                    try:
                        verify_candidate()
                    except RuntimeError:
                        pass
                    else:
                        raise RuntimeError('Profile relocation weakened the source integrity guard')
                    print('GREEN candidate run_host: owned external working directory/profile destination; wrong destination, source CWD and actual source mutation remain rejected.')
            globals().update(native=base / 'samples')
            native.mkdir()
            expected = {'started_at': 'Wed Oct 28 01:23:51 2026', 'executable_path': '/fixture/executable'}
            host = dict(expected, pid=24716, mapped_text_paths=['/fixture/executable'])
            for scenario in ('captured', 'missing', 'reused', 'changed-during', 'timeout'):
                reads, calls = [], []
                def fake_identity(_pid):
                    reads.append(True)
                    return None if scenario == 'missing' else dict(expected, started_at='different launch') if scenario == 'reused' or scenario == 'changed-during' and len(reads) > 1 else expected
                def fake_sample(command, **kwargs):
                    calls.append(command)
                    if scenario == 'timeout':
                        raise subprocess.TimeoutExpired(command, kwargs['timeout'], output=b'', stderr=b'timeout fixture')
                    Path(command[-1]).write_text('sample fixture only\n')
                    class Result:
                        returncode, stdout, stderr = 0, b'', b''
                    return Result()
                globals()['process_identity'], subprocess.run = fake_identity, fake_sample
                result = sample_host(host, scenario, 15.0)
                require(result['valid'] is (scenario == 'captured'), 'Invalid/missing/foreign/timed-out sample was labeled valid')
                require(bool(calls) == (scenario in ('captured', 'changed-during', 'timeout')), 'Sampler invoked for missing/reused PID')
                if scenario == 'captured':
                    require(result['identity_before'] == result['identity_after'] == expected and bool(result.get('sample_sha256')),
                        'Positive sample lacks exact before/after process identity and retained trace')
            print('Profile-output and sampling fixtures passed: actual old source-CWD transport RED/current GREEN; exact live sample plus missing/reused/changed-during-sample PID and timeout controls. Simulated metadata only; no compiler/native process sampled or executed.')
        finally:
            globals().update(saved)
            subprocess.Popen, subprocess.run, time.sleep = popen_before, run_before, sleep_before


def diagnostic_screen_self_test():
    global native, process_identity
    saved_native, saved_identity, saved_run = native, process_identity, subprocess.run
    expected = {'started_at': 'Wed Oct 28 02:11:35 2026', 'executable_path': '/fixture/executable'}
    host = dict(expected, pid=20220, mapped_text_paths=['/fixture/executable'])
    # Synthetic image header exercises only tool-result classification, never visual proof.
    image = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 1, 1) + bytes(9)
    try:
        with tempfile.TemporaryDirectory(prefix='rjt-undo-diagnostic-screen-') as directory:
            for scenario in ('captured', 'foreign', 'changed-during', 'timeout', 'bad-image'):
                native = Path(directory) / scenario
                native.mkdir()
                reads, calls = [], []
                def identity(_pid):
                    reads.append(True)
                    return dict(expected, started_at='another process') if scenario == 'foreign' or scenario == 'changed-during' and len(reads) > 1 else expected
                def capture(command, **kwargs):
                    calls.append(command)
                    if scenario == 'timeout':
                        raise subprocess.TimeoutExpired(command, kwargs['timeout'], output=b'', stderr=b'fixture timeout')
                    Path(command[-1]).write_bytes(image if scenario != 'bad-image' else b'not PNG')
                    class Result:
                        returncode, stdout, stderr = 0, b'', b''
                    return Result()
                process_identity, subprocess.run = identity, capture
                result = capture_diagnostic_screen(host, '15s', 15.0)
                require(result['valid'] is (scenario == 'captured'), 'Diagnostic screen validity misclassified')
                require(bool(calls) is (scenario != 'foreign'), 'Diagnostic capture ran for a foreign PID')
                verify_diagnostic_screens({'diagnostic_screens': [result]}, host)
                if scenario == 'captured':
                    (native / 'diagnostic-screen-15s/screen.png').write_bytes(b'changed')
                    try:
                        verify_diagnostic_screens({'diagnostic_screens': [result]}, host)
                    except RuntimeError:
                        pass
                    else:
                        raise RuntimeError('Changed diagnostic PNG accepted')
        print('External diagnostic screenshot metadata controls passed: positive, foreign PID, changed identity, timeout, invalid image and changed PNG. No real capture or native process executed.')
    finally:
        native, process_identity, subprocess.run = saved_native, saved_identity, saved_run


def readiness_observation_self_test():
    global native
    saved_native = native
    checkpoint = 'shortcut.recorder'
    names = ['click-readiness-' + checkpoint + '-attempt-' + str(n) + '.json' for n in (1, 2)]
    frame = {'x': 10, 'y': 20, 'width': 100, 'height': 22}
    point = {'x': 60, 'y': 31}
    bounds = {'x': 0, 'y': 0, 'width': 1024, 'height': 768}
    click = {'targetID': 'shortcutRecorder.undoLastWritingEdit', 'targetRole': 'AXButton', 'identityContract': 'identifier',
        'targetFrame': frame, 'point': point, 'activeDisplayID': 1, 'activeDisplayBounds': bounds, 'hitDepth': 0,
        'windowPolicy': 'same-window', 'targetWindowPresent': True, 'hitWindowPresent': True,
        'readiness': {'attemptCount': 2, 'observations': names, 'finalObservation': names[-1]}}
    final = {'schemaVersion': 1, 'kind': 'native-click-preinput-readiness-observation', 'diagnosticOnly': True,
        'experiment': 'preinput-readiness-calibration', 'checkpoint': 'click.' + checkpoint,
        'attempt': 2, 'maxAttempts': 6, 'inputPosted': False, 'hostPID': 42, 'systemUptime': 102.0, 'ready': True, 'reason': None,
        'identity': {'attempted': True, 'uniqueCount': 1, 'sameReferenceAsLookup': True, 'scope': 'host-owned-nodes'},
        'nativeMenuIdentity': {'attempted': False},
        'target': {'attempted': True, 'enabled': True, 'pid': 42, 'identifier': click['targetID'],
            'role': 'AXButton', 'identityContract': 'identifier'},
        'frame': dict(frame, attempted=True, finitePositive=True, positionRead=True, sizeRead=True,
            positionDecoded=True, sizeDecoded=True, center=point),
        'displays': {'attempted': True, 'apiError': 0, 'count': 1, 'containingCount': 1,
            'displays': [{'id': 1, 'bounds': bounds, 'containsTarget': True}]},
        'hitTest': {'attempted': True, 'axError': 0, 'elementPresent': True, 'pid': 42,
            'reachedTarget': True, 'depth': 0, 'point': point},
        'window': {'attempted': True, 'policy': 'same-window', 'targetWindowPresent': True,
            'hitWindowPresent': True, 'windowOwnedByHost': True},
        'frameRecheck': dict(frame, attempted=True, finitePositive=True, stable=True)}
    first = dict(copy.deepcopy(final), attempt=1, systemUptime=100.0, ready=False, reason='frame not on display')
    mutations = [lambda items: items[0].update(ready=True, reason=None),
        lambda items: items[1].update(inputPosted=True), lambda items: items[1]['target'].update(pid=43),
        lambda items: items[1]['frame'].update(x=11), lambda items: items[1]['displays'].update(containingCount=2),
        lambda items: items[1]['hitTest'].update(reachedTarget=False),
        lambda items: items[1]['window'].update(windowOwnedByHost=False)]
    try:
        with tempfile.TemporaryDirectory(prefix='rjt-undo-readiness-observation-') as directory:
            native = Path(directory)
            (native / 'progress').mkdir()
            stages = ['click.' + checkpoint + '.a2.observation-write.after',
                'click.' + checkpoint + '.post.before', 'click.' + checkpoint + '.post.after']
            for index, stage in enumerate(stages, 1):
                (native / 'progress' / (str(index).zfill(4) + '.json')).write_text(json.dumps({'stage': stage, 'sequence': index}))
            def store(items):
                for name, item in zip(names, items):
                    (native / name).write_text(json.dumps(item))
            store([first, final])
            require(len(verify_readiness_observations(click, checkpoint, 42)) == 2, 'Failed-then-ready read-only observation fixture rejected')
            for mutate in mutations:
                items = copy.deepcopy([first, final])
                mutate(items)
                store(items)
                try:
                    verify_readiness_observations(click, checkpoint, 42)
                except RuntimeError:
                    pass
                else:
                    raise RuntimeError('Unsafe/readiness-mismatched observation accepted')
            store([first, final])
            (native / 'progress' / '0004.json').write_text(json.dumps({'stage': stages[-1], 'sequence': 4}))
            try:
                verify_readiness_observations(click, checkpoint, 42)
            except RuntimeError:
                pass
            else:
                raise RuntimeError('Duplicate mouse input completion accepted')
        print('Pre-input readiness file bindings passed: failed-then-ready positive, seven ownership/geometry/input negatives and duplicate post rejection. Metadata only; no mouse event or native UI executed.')
    finally:
        native = saved_native


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
    outcome = json.loads((output / 'host-outcome.json').read_text())
    require(live['exit_code'] == 0 and closed['valid'] is True and closed['host'] == live['host'], 'Host lifecycle evidence invalid')
    require(outcome['classification'] == 'passed' and outcome['exit_code'] == 0 and outcome['mapped_host_observed'] is True
        and outcome['observed_completed_cases'] == cases and outcome['native_issues'] == []
        and all(outcome[key] is None for key in ('native_failure', 'monitor_error', 'closure_error', 'candidate_error')),
        'Retained host outcome contains a failure or incomplete execution')
    require(outcome['progress_files'] == progress_files() and outcome['profile_files'] == profile_files(),
        'Retained progress/profile diagnostic inventory changed')
    verify_diagnostic_screens(outcome, live['host'])
    require(len(outcome['samples']) == len({item['checkpoint'] for item in outcome['samples']}), 'Duplicate diagnostic sampling checkpoint')
    for item in outcome['samples']:
        expected_identity = {key: live['host'][key] for key in ('started_at', 'executable_path')}
        require(item['checkpoint'] in ('15s', '60s') and item['pid'] == live['host']['pid']
            and item['expected_identity'] == expected_identity and item['tool'] == '/usr/bin/sample'
            and item['tool_timeout_seconds'] == 8 and type(item['valid']) is bool
            and item['observed_elapsed_seconds'] >= int(item['checkpoint'][:-1]),
            'Diagnostic sample is not bound to the actual host/checkpoint')
        require(item == json.loads((native / ('sample-' + item['checkpoint']) / 'receipt.json').read_text()),
            'Retained sampling status or exact process-identity evidence changed')
        if item['valid'] is True:
            trace = native / ('sample-' + item['checkpoint']) / 'sample.txt'
            require(item['status'] == 'captured' and item['tool_exit_code'] == 0
                and item['identity_before'] == item['identity_after'] == expected_identity and not trace.is_symlink()
                and item['sample_sha256'] == digest(trace.read_bytes()), 'Retained verified sample identity/trace changed')
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
