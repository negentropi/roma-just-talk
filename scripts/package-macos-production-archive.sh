#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root" "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(sys.argv[1])
LOCK = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
WHISPER_SHA = '60c0be6ac8fa71b1a2ae2dd938a31a34a508e774'
ARCHIVE_NAME = 'roma.production.xcarchive'
APP_NAME = 'roma just talk.app'
MAX_BYTES = 3 * 1024 ** 3
MAX_ENTRIES = 30000
RECEIPTS = ('source-sha.txt', 'xcode.txt', 'swift.txt', 'build-settings.json', 'app-info.plist', 'archive.log', 'BOUNDARY.txt')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(argv, timeout=120):
    result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=timeout)
    require(result.returncode == 0, f'Command failed: {argv[0]}: {result.stderr.decode(errors="replace")[:2048]}')
    require(len(result.stdout) <= 16 * 1024 ** 2, 'Command output exceeds limit')
    return result.stdout


def receipt(directory, name):
    path = directory / name
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= 16 * 1024 ** 2,
            f'Missing or invalid receipt: {name}')
    return path.read_bytes()


def inventory(directory):
    require(directory.is_dir() and not directory.is_symlink(), 'Archive directory missing or symlinked')
    paths = [directory]
    for path in directory.rglob('*'):
        paths.append(path)
        require(len(paths) <= MAX_ENTRIES, 'Archive entry count exceeds limit')
    paths.sort()
    size = 0
    result = {}
    for path in paths:
        relative = path.relative_to(directory.parent).as_posix()
        require('\\' not in relative and not any(ord(char) < 32 for char in relative), 'Unsafe archive path')
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            target = os.readlink(path)
            require(not Path(target).is_absolute() and not any(ord(char) < 32 for char in target)
                    and path.resolve(strict=True).is_relative_to(directory), 'Unsafe archive symlink')
            if path.is_relative_to(directory / 'Products/Applications' / APP_NAME):
                require(path.resolve().is_relative_to(directory / 'Products/Applications' / APP_NAME), 'Escaping app symlink')
            data = target.encode()
            size += len(data)
            result[relative] = (mode, data)
        elif stat.S_ISREG(mode):
            size += path.stat().st_size
            require(size <= MAX_BYTES, 'Archive expanded size exceeds limit')
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 ** 2), b''):
                    digest.update(block)
            result[relative] = (mode, digest.digest())
        else:
            require(stat.S_ISDIR(mode), 'Unsupported archive member')
            result[relative] = (mode, b'')
        require(size <= MAX_BYTES, 'Archive expanded size exceeds limit')
    return result


def bundle_manifest(app, output):
    command(['bash', '-c', 'source "$1"; write_macos_bundle_manifest "$2" "$3"', '_',
             ROOT / 'scripts/macos-bundle-manifest.sh', app, output])


def pack(archive, destination, entries):
    with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED, allowZip64=True) as output:
        for name, (mode, data) in entries.items():
            item = zipfile.ZipInfo(name + '/' if stat.S_ISDIR(mode) else name)
            item.create_system = 3
            item.external_attr = mode << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            if stat.S_ISREG(mode):
                with (archive.parent / name).open('rb') as source, output.open(item, 'w', force_zip64=True) as target:
                    shutil.copyfileobj(source, target, length=1024 ** 2)
            else:
                output.writestr(item, data)
    require(destination.stat().st_size <= MAX_BYTES, 'Archive ZIP exceeds limit')


def unpack(archive, destination):
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        require(len(entries) <= MAX_ENTRIES and sum(item.file_size for item in entries) <= MAX_BYTES, 'Archive ZIP exceeds limits')
        names = set()
        for item in entries:
            name = item.filename.rstrip('/')
            path = PurePosixPath(name)
            mode = item.external_attr >> 16
            require(name and not path.is_absolute() and '..' not in path.parts and str(path) == name
                    and path.parts[0] == ARCHIVE_NAME and '\\' not in name
                    and not any(ord(char) < 32 for char in name) and name not in names and not item.flag_bits & 1,
                    'Unsafe or duplicate ZIP member')
            names.add(name)
            require(stat.S_IFMT(mode) in (stat.S_IFDIR, stat.S_IFREG, stat.S_IFLNK), 'Unsupported ZIP member')
            if stat.S_ISLNK(mode):
                target = source.read(item).decode()
                require(not Path(target).is_absolute() and not any(ord(char) < 32 for char in target)
                        and (destination / name).parent.joinpath(target).resolve().is_relative_to(destination / ARCHIVE_NAME),
                        'Unsafe ZIP symlink')
        for item in entries:
            path = destination / item.filename.rstrip('/')
            mode = item.external_attr >> 16
            require(not any(parent.is_symlink() for parent in path.parents if parent.is_relative_to(destination)), 'ZIP symlink ancestor')
            if stat.S_ISDIR(mode):
                path.mkdir(parents=True, exist_ok=True)
                path.chmod(stat.S_IMODE(mode))
            elif stat.S_ISLNK(mode):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(source.read(item).decode())
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with source.open(item) as original, path.open('xb') as copied:
                    shutil.copyfileobj(original, copied, length=1024 ** 2)
                path.chmod(stat.S_IMODE(mode))


def main(args):
    require(re.fullmatch(r'[0-9a-f]{40}', args.expected_source_sha), 'Expected source SHA must be full lowercase Git SHA')
    require(not any(path.is_symlink() for path in (args.archive, args.evidence_directory, args.whisper_source)), 'Symlinked input directory')
    archive, evidence, whisper = (path.resolve(strict=True) for path in (args.archive, args.evidence_directory, args.whisper_source))
    output = args.output_directory
    require(archive.name == ARCHIVE_NAME, 'Archive name differs')
    require(not output.exists() and not output.is_symlink(), 'Output directory already exists')
    output = output.parent.resolve(strict=True) / output.name
    require(not any(output.is_relative_to(path) or path.is_relative_to(output) for path in (archive, evidence, whisper, ROOT)),
            'Output directory overlaps inputs or source checkout')
    require(command(['git', '-C', ROOT, 'rev-parse', 'HEAD']).decode().strip() == args.expected_source_sha, 'Source checkout SHA differs')
    command(['git', '-C', ROOT, 'diff', '--quiet', 'HEAD', '--'])
    data = {name: receipt(evidence, name) for name in RECEIPTS}
    require(data['source-sha.txt'] == (args.expected_source_sha + '\n').encode(), 'Source receipt differs')
    require(data['xcode.txt'].decode().splitlines() == ['Xcode 26.6', 'Build version 17F113'], 'Xcode receipt differs')
    require(re.search(r'\bApple Swift version 6\.3\.3\b', data['swift.txt'].decode()), 'Swift receipt differs')
    require(command(['xcodebuild', '-version']) == data['xcode.txt']
            and command(['swift', '--version']) == data['swift.txt']
            and command(['xcrun', '--sdk', 'macosx', '--show-sdk-version']).decode().strip() == '26.5', 'Actual toolchain differs from receipts')
    require(b'** ARCHIVE SUCCEEDED **' in data['archive.log'], 'Archive success receipt missing')
    rows = json.loads(data['build-settings.json'])
    selected = [row for row in rows if row.get('target') == 'VoiceInk']
    require(len(selected) == 1, 'Production settings target missing or duplicated')
    settings = selected[0]['buildSettings']
    expected = {'CONFIGURATION': 'Release', 'CODE_SIGN_ENTITLEMENTS': 'VoiceInk/VoiceInk.entitlements',
                'CODE_SIGNING_ALLOWED': 'NO', 'CODE_SIGNING_REQUIRED': 'NO', 'CODE_SIGN_IDENTITY': '',
                'ENABLE_CODE_COVERAGE': 'NO', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.negentropi.RomaJustTalk', 'MACOSX_DEPLOYMENT_TARGET': '14.2.1',
                'SDK_VERSION': '26.5'}
    require(all(settings.get(key) == value for key, value in expected.items())
            and 'ENABLE_NATIVE_SPEECH_ANALYZER' in settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split()
            and not any('LOCAL_BUILD' in value for key, value in settings.items()
                        if key in ('SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'OTHER_SWIFT_FLAGS', 'OTHER_CFLAGS', 'GCC_PREPROCESSOR_DEFINITIONS')),
            'Not the pinned unsigned production Release settings')
    lock = command(['git', '-C', ROOT, 'show', args.expected_source_sha + ':' + LOCK])
    require((ROOT / LOCK).read_bytes() == lock, 'Source package lock differs')
    pins = json.loads(lock)['pins']
    require(pins and len({pin['identity'] for pin in pins}) == len(pins)
            and all(re.fullmatch(r'[0-9a-f]{40}', pin['state']['revision']) for pin in pins), 'Invalid source package pins')
    require(command(['git', '-C', whisper, 'rev-parse', 'HEAD']).decode().strip() == WHISPER_SHA, 'Whisper revision differs')
    command(['git', '-C', whisper, 'diff', '--quiet', 'HEAD', '--'])
    entries = inventory(archive)
    applications = archive / 'Products/Applications'
    app = applications / APP_NAME
    require(list(applications.iterdir()) == [app] and app.is_dir() and not app.is_symlink(), 'Archive application layout differs')
    info_bytes = (app / 'Contents/Info.plist').read_bytes()
    info = plistlib.loads(info_bytes)
    require(data['app-info.plist'] == info_bytes and info.get('CFBundleIdentifier') == expected['PRODUCT_BUNDLE_IDENTIFIER']
            and info.get('LSMinimumSystemVersion') == '14.2.1'
            and re.fullmatch(r'[A-Za-z0-9 _.-]+', info.get('CFBundleExecutable', ''))
            and (app / 'Contents/MacOS' / info['CFBundleExecutable']).is_file(), 'Archive app identity or plist receipt differs')
    archive_info = plistlib.loads((archive / 'Info.plist').read_bytes())['ApplicationProperties']
    require(archive_info.get('ApplicationPath') == 'Applications/' + APP_NAME
            and archive_info.get('CFBundleIdentifier') == expected['PRODUCT_BUNDLE_IDENTIFIER']
            and archive_info.get('Architectures') == ['arm64'] and not archive_info.get('SigningIdentity'), 'Archive production identity differs')
    require(command(['lipo', '-archs', app / 'Contents/MacOS' / info['CFBundleExecutable']]).decode().split() == ['arm64'],
            'Archived main executable architecture differs')
    command(['bash', ROOT / 'scripts/verify-macos-release-instrumentation.sh', app])
    command(['python3', ROOT / 'scripts/check-macos-deployment-target.py', app])
    output.mkdir(mode=0o700)
    for name, content in data.items():
        with (output / name).open('xb') as stream:
            stream.write(content)
    (output / 'Package.resolved').write_bytes(lock)
    (output / 'whisper-source-sha.txt').write_text(WHISPER_SHA + '\n')
    bundle_manifest(app, output / 'unsigned-app-files.sha256')
    packed = output / (ARCHIVE_NAME + '.zip')
    pack(archive, packed, entries)
    with tempfile.TemporaryDirectory(prefix='roma-archive-roundtrip-', dir=output.parent) as scratch:
        roundtrip = Path(scratch)
        unpack(packed, roundtrip)
        require(inventory(roundtrip / ARCHIVE_NAME) == entries, 'Archive ZIP roundtrip changed content or modes')
        observed = roundtrip / 'app-files.sha256'
        bundle_manifest(roundtrip / ARCHIVE_NAME / 'Products/Applications' / APP_NAME, observed)
        require(observed.read_bytes() == (output / 'unsigned-app-files.sha256').read_bytes(), 'App ZIP roundtrip manifest differs')
    require(inventory(archive) == entries, 'Source archive changed during packaging')
    command(['git', '-C', ROOT, 'diff', '--quiet', 'HEAD', '--'])
    command(['git', '-C', whisper, 'diff', '--quiet', 'HEAD', '--'])
    require(set(path.name for path in output.iterdir()) == {*RECEIPTS, 'Package.resolved', 'whisper-source-sha.txt',
                                                         'unsigned-app-files.sha256', ARCHIVE_NAME + '.zip'}, 'Artifact layout differs')
    print(f'Packaged unsigned production archive for {args.expected_source_sha}; {len(pins)} source lock pins. Not distribution-qualified.')


parser = argparse.ArgumentParser(description='Retain one unsigned production archive with its source receipts; never sign or publish.')
for name in ('archive', 'evidence-directory', 'whisper-source', 'output-directory'):
    parser.add_argument('--' + name, type=Path, required=True)
parser.add_argument('--expected-source-sha', required=True)
try:
    main(parser.parse_args(sys.argv[2:]))
except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, plistlib.InvalidFileException,
        subprocess.TimeoutExpired, zipfile.BadZipFile) as error:
    print(f'Production archive packaging failed: {error}', file=sys.stderr)
    sys.exit(1)
PY
