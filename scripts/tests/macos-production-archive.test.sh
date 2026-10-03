#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$root" "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

root = Path(sys.argv[1])
parser = argparse.ArgumentParser()
parser.add_argument('--producer-workflow', type=Path, default=root / '.github/workflows/macos-production-compile-check.yml')
args = parser.parse_args(sys.argv[2:])
assert sys.platform == 'darwin', 'Native archive fixture requires macOS'
scratch_parent = Path(os.environ.get('RJT_TEST_TEMP_DIRECTORY', tempfile.gettempdir()))
scratch_parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='roma-production-archive-test-', dir=scratch_parent) as temporary:
    scratch = Path(temporary)
    fixture = scratch / 'repository'
    (fixture / 'scripts').mkdir(parents=True)
    for name in ('package-macos-production-archive.sh', 'macos-bundle-manifest.sh',
                 'verify-macos-release-instrumentation.sh', 'check-macos-deployment-target.py'):
        shutil.copyfile(root / 'scripts' / name, fixture / 'scripts' / name)
    lock_relative = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock = fixture / lock_relative
    lock.parent.mkdir(parents=True)
    lock_bytes = (root / lock_relative).read_bytes()
    lock.write_bytes(lock_bytes)
    (scratch / 'tracked-lock').write_bytes(lock_bytes)
    whisper = scratch / 'whisper'
    whisper.mkdir()
    sha = '1' * 40
    whisper_sha = '60c0be6ac8fa71b1a2ae2dd938a31a34a508e774'
    archive = scratch / 'roma.production.xcarchive'
    app = archive / 'Products/Applications/roma just talk.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    code = scratch / 'main.c'
    code.write_text('int main(void) { return 0; }\n')
    subprocess.run(['/usr/bin/clang', '-target', 'arm64-apple-macos14.2.1', '-Wl,-no_adhoc_codesign',
                    str(code), '-o', str(app / 'Contents/MacOS/roma just talk')], check=True, capture_output=True)
    unsigned = subprocess.run(['/usr/bin/codesign', '--display', '--verbose=4', str(app / 'Contents/MacOS/roma just talk')], capture_output=True)
    assert unsigned.returncode != 0 and b'not signed at all' in unsigned.stderr, unsigned.stderr
    info = {'CFBundleIdentifier': 'com.negentropi.RomaJustTalk', 'CFBundleExecutable': 'roma just talk',
            'LSMinimumSystemVersion': '14.2.1', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0'}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    (archive / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {
        'ApplicationPath': 'Applications/roma just talk.app', 'CFBundleIdentifier': info['CFBundleIdentifier'],
        'Architectures': ['arm64']}}))
    resources = app / 'Contents/Frameworks/Fixture.framework/Versions/A/Resources'
    resources.mkdir(parents=True)
    resources.chmod(0o750)
    (resources / 'fixture.txt').write_text('literal fixture resource\n')
    (resources / 'fixture.txt').chmod(0o640)
    framework = resources.parents[2]
    (framework / 'Versions/Current').symlink_to('A')
    (framework / 'Resources').symlink_to('Versions/Current/Resources')
    settings = {'CONFIGURATION': 'Release', 'CODE_SIGN_ENTITLEMENTS': 'VoiceInk/VoiceInk.entitlements',
                'CODE_SIGNING_ALLOWED': 'NO', 'CODE_SIGNING_REQUIRED': 'NO', 'CODE_SIGN_IDENTITY': '',
                'ENABLE_CODE_COVERAGE': 'NO', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'PRODUCT_BUNDLE_IDENTIFIER': info['CFBundleIdentifier'], 'MACOSX_DEPLOYMENT_TARGET': '14.2.1',
                'SDK_VERSION': '26.5', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'ENABLE_NATIVE_SPEECH_ANALYZER'}
    evidence = scratch / 'evidence'
    evidence.mkdir()
    xcode = b'Xcode 26.6\nBuild version 17F113\n'
    swift = b'Apple Swift version 6.3.3 (fixture)\nTarget: arm64-apple-macosx26.5\n'
    receipts = {'source-sha.txt': (sha + '\n').encode(), 'xcode.txt': xcode, 'swift.txt': swift,
                'build-settings.json': json.dumps([{'target': 'VoiceInk', 'buildSettings': settings}]).encode(),
                'app-info.plist': (app / 'Contents/Info.plist').read_bytes(),
                'archive.log': b'controlled archive output\n** ARCHIVE SUCCEEDED **\n',
                'BOUNDARY.txt': b'Unsigned production compile only; not qualified.\n'}
    for name, content in receipts.items():
        (evidence / name).write_bytes(content)
    bin_directory = scratch / 'bin'
    bin_directory.mkdir()
    stub = bin_directory / 'controlled-command.py'
    stub.write_text(r'''#!/usr/bin/env python3
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
case = os.environ['ARCHIVE_TEST_CASE']
args = sys.argv[1:]
if name == 'git':
    if 'rev-parse' in args:
        whisper = args[1] == os.environ['ARCHIVE_TEST_WHISPER']
        print(('f' * 40 if case == 'wrong-whisper' else '60c0be6ac8fa71b1a2ae2dd938a31a34a508e774') if whisper else ('f' * 40 if case == 'wrong-checkout' else '1' * 40))
    elif 'show' in args:
        sys.stdout.buffer.write(Path(os.environ['ARCHIVE_TEST_LOCK']).read_bytes())
    elif 'diff' in args:
        if case == 'dirty-source' and args[1] != os.environ['ARCHIVE_TEST_WHISPER']:
            sys.exit(1)
        if case == 'dirty-whisper' and args[1] == os.environ['ARCHIVE_TEST_WHISPER']:
            sys.exit(1)
    else:
        sys.exit(2)
elif name == 'xcodebuild':
    print('Xcode 26.5' if case == 'actual-xcode' else 'Xcode 26.6')
    print('Build version 17F113')
elif name == 'swift':
    print('Apple Swift version 6.3.2 (fixture)' if case == 'actual-swift' else 'Apple Swift version 6.3.3 (fixture)')
    print('Target: arm64-apple-macosx26.5')
elif name == 'xcrun':
    print('26.4' if case == 'actual-sdk' else '26.5')
else:
    sys.exit(2)
''')
    stub.chmod(0o755)
    for name in ('git', 'xcodebuild', 'swift', 'xcrun'):
        (bin_directory / name).symlink_to(stub.name)
    argv = ['bash', str(fixture / 'scripts/package-macos-production-archive.sh'), '--archive', str(archive),
            '--evidence-directory', str(evidence), '--whisper-source', str(whisper), '--expected-source-sha', sha]

    def run(case, success=False, output=None, expected=''):
        destination = output or scratch / ('output-' + case)
        environment = dict(os.environ, PATH=str(bin_directory) + os.pathsep + os.environ['PATH'], ARCHIVE_TEST_CASE=case,
                           ARCHIVE_TEST_WHISPER=str(whisper.resolve()), ARCHIVE_TEST_LOCK=str(scratch / 'tracked-lock'))
        completed = subprocess.run([*argv, '--output-directory', str(destination)], env=environment, capture_output=True, text=True)
        assert (completed.returncode == 0) == success, (case, completed.stdout, completed.stderr)
        if expected:
            assert expected in completed.stderr, (case, completed.stderr)
        print(('PASS' if success else 'REJECT') + ' ' + case)
        return destination

    accepted = run('accepted', True)
    expected_files = {*receipts, 'roma.production.xcarchive.zip', 'Package.resolved',
                      'whisper-source-sha.txt', 'unsigned-app-files.sha256'}
    assert {path.name for path in accepted.iterdir()} == expected_files
    assert (accepted / 'Package.resolved').read_bytes() == lock_bytes
    assert (accepted / 'whisper-source-sha.txt').read_text() == whisper_sha + '\n'
    manifest = (accepted / 'unsigned-app-files.sha256').read_text()
    assert 'directory  mode=750  Contents/Frameworks/Fixture.framework/Versions/A/Resources\n' in manifest
    assert 'mode=640  Contents/Frameworks/Fixture.framework/Versions/A/Resources/fixture.txt\n' in manifest
    assert 'symlink  Contents/Frameworks/Fixture.framework/Versions/Current -> A\n' in manifest
    with zipfile.ZipFile(accepted / 'roma.production.xcarchive.zip') as zipped:
        executable_name = 'roma.production.xcarchive/Products/Applications/roma just talk.app/Contents/MacOS/roma just talk'
        assert hashlib.sha256(zipped.read(executable_name)).digest() == hashlib.sha256((app / 'Contents/MacOS/roma just talk').read_bytes()).digest()
        assert {item.filename.split('/')[0] for item in zipped.infolist()} == {'roma.production.xcarchive'}
    run('existing-output', output=accepted, expected='already exists')
    for case, key, value in (
        ('local-build', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'LOCAL_BUILD ENABLE_NATIVE_SPEECH_ANALYZER'),
        ('local-flags', 'OTHER_SWIFT_FLAGS', '-DLOCAL_BUILD'),
        ('local-entitlements', 'CODE_SIGN_ENTITLEMENTS', 'VoiceInk/VoiceInk.local.entitlements'),
        ('sdk-settings', 'SDK_VERSION', '26.4'),
        ('signing', 'CODE_SIGNING_ALLOWED', 'YES'),
        ('coverage', 'ENABLE_CODE_COVERAGE', 'YES')):
        altered = dict(settings, **{key: value})
        (evidence / 'build-settings.json').write_text(json.dumps([{'target': 'VoiceInk', 'buildSettings': altered}]))
        run(case, expected='production Release settings')
    (evidence / 'build-settings.json').write_bytes(receipts['build-settings.json'])
    for case, name, value, rejection in (
        ('wrong-source', 'source-sha.txt', b'f' * 40 + b'\n', 'Source receipt differs'),
        ('wrong-xcode', 'xcode.txt', b'Xcode 26.5\nBuild version 17F113\n', 'Xcode receipt differs'),
        ('wrong-swift', 'swift.txt', b'Apple Swift version 6.3.2\n', 'Swift receipt differs'),
        ('failed-archive', 'archive.log', b'** ARCHIVE FAILED **\n', 'Archive success receipt missing'),
        ('wrong-plist', 'app-info.plist', plistlib.dumps(dict(info, CFBundleVersion='2')), 'identity or plist receipt differs')):
        (evidence / name).write_bytes(value)
        run(case, expected=rejection)
        (evidence / name).write_bytes(receipts[name])
    for case in ('actual-xcode', 'actual-swift', 'actual-sdk'):
        run(case, expected='Actual toolchain differs')
    lock.write_bytes(lock_bytes + b'\n')
    run('changed-lock', expected='Source package lock differs')
    lock.write_bytes(lock_bytes)
    run('wrong-checkout', expected='Source checkout SHA differs')
    run('wrong-whisper', expected='Whisper revision differs')
    run('dirty-source', expected='Command failed: git')
    run('dirty-whisper', expected='Command failed: git')
    unsafe = app / 'Contents/unsafe'
    unsafe.symlink_to('../../../../../evidence')
    run('escaping-symlink', expected='Unsafe archive symlink')
    unsafe.unlink()
    unsafe.symlink_to('/etc/hosts')
    run('absolute-symlink', expected='Unsafe archive symlink')
    unsafe.unlink()
    unsafe.symlink_to('missing')
    run('broken-symlink')
    unsafe.unlink()
    oversized = archive / 'oversized'
    with oversized.open('wb') as stream:
        stream.truncate(3 * 1024 ** 3 + 1)
    run('oversized-archive', expected='Archive expanded size exceeds limit')
    oversized.unlink()
    run('accepted-after-negatives', True)
    workflow = args.producer_workflow.read_text()
    assert 'name: roma.macos.unsigned-production-archive' in workflow, 'Producer does not retain the actual production archive'
    assert 'bash scripts/package-macos-production-archive.sh' in workflow, 'Producer bypasses archive packaging'
    assert '-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile' in workflow, 'Producer permits source package pin mutation'
    archive_step = workflow.split('- name: Retain unsigned production archive', 1)[1].split('- name: Retain compilation evidence', 1)[0]
    assert 'if: always()' not in archive_step and 'if: failure()' not in archive_step, 'Archive upload is not gated by success'
    assert 'if: always()' in workflow.split('- name: Retain compilation evidence', 1)[1], 'Failure evidence is not retained'
    print('PASS producer archive retention and always-on diagnostic evidence')
    print('Packaging fixture proof only; no full RJT build, signing, notarization, or runtime qualification.')
PY
