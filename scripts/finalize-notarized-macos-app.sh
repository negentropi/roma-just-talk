#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root" "$@" <<'PY'
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import fnmatch
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import zipfile
import zlib

ROOT = Path(sys.argv[1])
REPOSITORY = 'negentropi/roma-just-talk'
SOURCE_WORKFLOW = '.github/workflows/macos-production-compile-check.yml'
PRODUCER_WORKFLOW = '.github/workflows/qualify-macos-distribution.yml'
SOURCE_JOB = 'Compile Release without local behavior'
FINALIZER_JOB = 'Finalize notarized macOS app'
SOURCE_ARTIFACT = 'roma.macos.unsigned-production-archive'
APP_NAME = 'roma just talk.app'
BUNDLE_ID = 'com.negentropi.RomaJustTalk'
MACHO = {bytes.fromhex(value) for value in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
MAX_ARCHIVE = 3 * 1024 ** 3


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def decode(data):
    return json.loads(data, object_pairs_hook=unique_pairs)


def utc(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None, 'Missing UTC offset')
    return parsed.astimezone(timezone.utc)


def write(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


class Commands:
    def __init__(self, output):
        self.output = output
        self.records = []

    def run(self, name, argv, timeout=120, acceptable=(0,), binary=False):
        prefix = f'{len(self.records):03d}-{name}'
        streams = {channel: self.output / (prefix + '.' + channel) for channel in ('stdout', 'stderr')}
        record = {'name': name, 'argv': list(map(str, argv)), 'startedAt': datetime.now(timezone.utc).isoformat(), 'timedOut': False}
        with streams['stdout'].open('xb') as stdout, streams['stderr'].open('xb') as stderr:
            try:
                process = subprocess.Popen(record['argv'], stdout=stdout, stderr=stderr, start_new_session=True)
                try:
                    record['exitStatus'] = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    record['exitStatus'] = process.wait()
                    record['timedOut'] = True
            except OSError as error:
                record.update(exitStatus=None, error=type(error).__name__)
        record['endedAt'] = datetime.now(timezone.utc).isoformat()
        for channel, path in streams.items():
            record[channel] = {'path': path.name, 'size': path.stat().st_size, 'sha256': sha(path)}
        self.records.append(record)
        (self.output / 'commands.json').write_text(json.dumps(self.records, indent=2) + '\n')
        require(record['exitStatus'] in acceptable and not record['timedOut'], f'Command failed: {name}')
        path = streams['stdout']
        require(path.stat().st_size <= (MAX_ARCHIVE if binary else 16 * 1024 ** 2), f'Command output too large: {name}')
        return path if binary else path.read_bytes()

    def api(self, endpoint):
        data = self.run('github-api', ['gh', 'api', '--hostname', 'github.com', f'repos/{REPOSITORY}/{endpoint}'], timeout=30)
        require(len(data) <= 1024 ** 2, 'GitHub response too large')
        return decode(data)


def authenticated_job(commands, run_id, attempt, head, workflow, name, active=False):
    run = commands.api(f'actions/runs/{run_id}')
    require(run.get('id') == run_id and run.get('run_attempt') == attempt
            and run.get('repository', {}).get('full_name') == REPOSITORY
            and run.get('head_repository', {}).get('full_name') == REPOSITORY
            and run.get('head_sha') == head and run.get('path', '').split('@')[0] == workflow
            and run.get('event') in ('push', 'workflow_dispatch') and not run.get('pull_requests'), 'Run identity differs')
    require((run.get('status'), run.get('conclusion')) == (('in_progress', None) if active else ('completed', 'success')), 'Whole workflow is not in the required state')
    response = commands.api(f'actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100')
    jobs = response.get('jobs')
    require(isinstance(jobs, list) and type(response.get('total_count')) is int
            and len(jobs) == response['total_count'] <= 100, 'Job inventory absent or truncated')
    selected = [job for job in jobs if job.get('name') == name]
    require(len(selected) == 1, 'Required job missing or duplicated')
    job = selected[0]
    require(job.get('run_id') == run_id and job.get('run_attempt') == attempt
            and type(job.get('id')) is int and job['id'] > 0
            and type(job.get('runner_id')) is int and job['runner_id'] > 0
            and (job.get('status'), job.get('conclusion')) == (('in_progress', None) if active else ('completed', 'success')), 'Job attempt or state differs')
    return job


def reviewed_file(commands, relative, head):
    value = commands.api(f'contents/{relative}?ref={head}')
    require(value.get('encoding') == 'base64', 'Reviewed source unavailable')
    data = base64.b64decode(value['content'].replace('\n', ''), validate=True)
    require((ROOT / relative).read_bytes() == data, f'Local tooling differs: {relative}')
    return data


def unpack(archive_path, output, expected_root=None):
    with zipfile.ZipFile(archive_path) as archive:
        items = archive.infolist()
        require(len(items) <= 30000 and sum(item.file_size for item in items) <= MAX_ARCHIVE, 'Archive exceeds limits')
        names = set()
        for item in items:
            require(item.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'Unsupported archive compression')
            path = PurePosixPath(item.filename.rstrip('/'))
            require(item.filename and path.parts and '\\' not in item.filename and not path.is_absolute()
                    and '..' not in path.parts and str(path) == item.filename.rstrip('/')
                    and not any(ord(char) < 32 for char in item.filename)
                    and path not in names and not item.flag_bits & 1, 'Unsafe or duplicate archive member')
            names.add(path)
            if expected_root:
                require(path.parts[0] in (expected_root, '__MACOSX'), 'Archive root differs')
            mode = item.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), 'Unsupported archive member')
            if stat.S_ISLNK(mode):
                target = archive.read(item).decode()
                require(not Path(target).is_absolute() and not any(ord(char) < 32 for char in target), 'Unsafe symlink')
                resolved = (output / str(path)).parent.joinpath(target).resolve()
                require(resolved.is_relative_to(output.resolve()), 'Escaping symlink')
        output.mkdir()
        for item in items:
            if expected_root and PurePosixPath(item.filename).parts[0] == '__MACOSX':
                continue
            path = output / item.filename.rstrip('/')
            require(not any(parent.is_symlink() for parent in (path.parent, *path.parent.parents) if parent.is_relative_to(output)), 'Symlink ancestor in archive')
            mode = item.external_attr >> 16
            if item.is_dir():
                path.mkdir(parents=True, exist_ok=True)
                path.chmod(stat.S_IMODE(mode) or 0o755)
            elif stat.S_ISLNK(mode):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(archive.read(item).decode())
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as source, path.open('xb') as destination:
                    shutil.copyfileobj(source, destination)
                path.chmod(stat.S_IMODE(mode) or 0o644)


def inventory(app):
    result = {'.': {'directoryMode': stat.S_IMODE(app.stat().st_mode)}}
    for path in sorted(app.rglob('*')):
        relative = path.relative_to(app).as_posix()
        require(not any(ord(char) < 32 for char in relative), 'Control character in app path')
        if path.is_symlink():
            require(path.resolve().is_relative_to(app.resolve()), 'Escaping app symlink')
            result[relative] = {'symlink': os.readlink(path)}
        elif path.is_file():
            result[relative] = {'sha256': sha(path), 'mode': stat.S_IMODE(path.stat().st_mode)}
        else:
            require(path.is_dir(), 'Unsupported app member')
            result[relative] = {'directoryMode': stat.S_IMODE(path.stat().st_mode)}
    return result


def images(app):
    result = []
    for path in sorted(app.rglob('*')):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO:
                    result.append(path)
    return result


def unsigned_projection(commands, app, destination):
    shutil.copytree(app, destination, symlinks=True)
    for path in images(destination):
        details = commands.run('comparison-signature', ['codesign', '--display', '--verbose=4', path], acceptable=(0, 1))
        last = commands.records[-1]
        if last['exitStatus'] == 0:
            commands.run('comparison-remove-signature', ['codesign', '--remove-signature', path])
    result = inventory(destination)
    return {name: value for name, value in result.items()
            if '_CodeSignature' not in PurePosixPath(name).parts and name not in ('Contents/embedded.provisionprofile', 'Contents/CodeResources')}


def main(args):
    output = args.output_dir.resolve()
    output.mkdir(mode=0o700)
    commands_dir = output / 'command-receipts'
    commands_dir.mkdir()
    commands = Commands(commands_dir)
    try:
        require(sys.platform == 'darwin', 'Finalization requires macOS')
        require(os.environ.get('GITHUB_REPOSITORY') == REPOSITORY and os.environ.get('GITHUB_SHA') == args.expected_tooling_sha, 'Trusted producer environment required')
        producer_run, producer_attempt = int(os.environ.get('GITHUB_RUN_ID', '0')), int(os.environ.get('GITHUB_RUN_ATTEMPT', '0'))
        require(producer_run > 0 and producer_attempt > 0, 'Missing producer attempt')
        producer = authenticated_job(commands, producer_run, producer_attempt, args.expected_tooling_sha, PRODUCER_WORKFLOW, FINALIZER_JOB, active=True)
        require(commands.run('tooling-head', ['git', '-C', ROOT, 'rev-parse', 'HEAD']).decode().strip() == args.expected_tooling_sha, 'Tooling checkout head differs')
        for relative in ('scripts/finalize-notarized-macos-app.sh', 'scripts/verify-macos-notarized-app.sh', 'scripts/check-macos-deployment-target.py', 'scripts/verify-macos-release-instrumentation.sh', 'scripts/macos-bundle-manifest.sh'):
            reviewed_file(commands, relative, args.expected_tooling_sha)
        require(commands.run('xcode-version', ['xcodebuild', '-version']).decode().splitlines() == ['Xcode 26.6', 'Build version 17F113'], 'Unreviewed Xcode version')
        source_job = authenticated_job(commands, args.source_run_id, args.source_run_attempt, args.expected_source_sha, SOURCE_WORKFLOW, SOURCE_JOB)
        require('macos-26' in source_job.get('labels', []) and source_job.get('runner_group_name') == 'GitHub Actions'
                and re.fullmatch(r'GitHub Actions [0-9]+', source_job.get('runner_name', '')), 'Unreviewed production build provider')
        artifact = commands.api(f'actions/artifacts/{args.source_artifact_id}')
        require(artifact.get('id') == args.source_artifact_id and artifact.get('name') == SOURCE_ARTIFACT
                and artifact.get('expired') is False and artifact.get('workflow_run', {}).get('id') == args.source_run_id
                and artifact.get('workflow_run', {}).get('head_sha') == args.expected_source_sha
                and utc(source_job['started_at']) <= utc(artifact['created_at']) <= utc(source_job['completed_at']), 'Production source artifact differs')
        transport = commands.run('source-download', ['gh', 'api', '--hostname', 'github.com', f'repos/{REPOSITORY}/actions/artifacts/{args.source_artifact_id}/zip'], timeout=180, binary=True)
        require(artifact.get('size_in_bytes') == transport.stat().st_size and artifact.get('digest') == 'sha256:' + sha(transport), 'Source transport differs from live API')
        source = output / 'source'
        unpack(transport, source)
        expected_source_files = {'roma.production.xcarchive.zip', 'build-settings.json', 'source-sha.txt', 'xcode.txt', 'swift.txt', 'app-info.plist',
                                 'archive.log', 'BOUNDARY.txt', 'Package.resolved', 'whisper-source-sha.txt', 'unsigned-app-files.sha256'}
        require(set(path.name for path in source.iterdir()) == expected_source_files and all(path.is_file() and not path.is_symlink() for path in source.iterdir()), 'Production archive artifact layout differs')
        require((source / 'source-sha.txt').read_text().strip() == args.expected_source_sha
                and (source / 'xcode.txt').read_text().splitlines() == ['Xcode 26.6', 'Build version 17F113'], 'Production source or toolchain receipt differs')
        rows = decode((source / 'build-settings.json').read_bytes())
        selected = [row for row in rows if row.get('target') == 'VoiceInk']
        require(len(selected) == 1, 'Production settings target missing or duplicated')
        settings = selected[0]['buildSettings']
        require(settings.get('CONFIGURATION') == 'Release' and 'LOCAL_BUILD' not in settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split()
                and 'ENABLE_NATIVE_SPEECH_ANALYZER' in settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split()
                and settings.get('CODE_SIGN_ENTITLEMENTS') == 'VoiceInk/VoiceInk.entitlements'
                and settings.get('CODE_SIGNING_ALLOWED') == 'NO' and settings.get('ARCHS') == 'arm64'
                and settings.get('PRODUCT_BUNDLE_IDENTIFIER') == BUNDLE_ID and settings.get('MACOSX_DEPLOYMENT_TARGET') == '14.2.1', 'Not an unsigned production Release build')
        lock = commands.api(f'contents/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved?ref={args.expected_source_sha}')
        require(lock.get('encoding') == 'base64' and base64.b64decode(lock['content'].replace('\n', ''), validate=True) == (source / 'Package.resolved').read_bytes(), 'Production package lock differs from source')
        require((source / 'whisper-source-sha.txt').read_text().strip() == '60c0be6ac8fa71b1a2ae2dd938a31a34a508e774', 'Production Whisper revision differs')
        archive_root = output / 'archive'
        unpack(source / 'roma.production.xcarchive.zip', archive_root, 'roma.production.xcarchive')
        archive = archive_root / 'roma.production.xcarchive'
        app = archive / 'Products/Applications' / APP_NAME
        require(list((archive / 'Products/Applications').iterdir()) == [app], 'Archive must contain exactly the expected app')
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        require(info.get('CFBundleIdentifier') == BUNDLE_ID and info.get('LSMinimumSystemVersion') == '14.2.1'
                and re.fullmatch(r'[A-Za-z0-9 _.-]+', info.get('CFBundleExecutable', ''))
                and (app / 'Contents/MacOS' / info['CFBundleExecutable']).is_file(), 'Production app identity differs')
        inventory(app)
        require(plistlib.loads((source / 'app-info.plist').read_bytes()) == info, 'Source app plist receipt differs')
        manifest = output / 'source-app-files.sha256'
        commands.run('source-bundle-manifest', ['bash', '-c', 'source "$1"; write_macos_bundle_manifest "$2" "$3"', '_', ROOT / 'scripts/macos-bundle-manifest.sh', app, manifest])
        require(manifest.read_bytes() == (source / 'unsigned-app-files.sha256').read_bytes(), 'Source app manifest differs')
        commands.run('source-deployment', ['python3', ROOT / 'scripts/check-macos-deployment-target.py', app])
        commands.run('source-instrumentation', ['bash', ROOT / 'scripts/verify-macos-release-instrumentation.sh', app])
        identities = commands.run('available-identities', ['security', 'find-identity', '-v', '-p', 'codesigning']).decode()
        require(re.search(r'\b' + args.signing_identity_sha1 + r'\s+"Developer ID Application: [^\n"]+ \(' + args.developer_id_team + r'\)"', identities), 'Exact existing Developer ID identity and team unavailable')
        profile_bytes = commands.run('provisioning-profile', ['security', 'cms', '-D', '-i', args.provisioning_profile])
        profile = plistlib.loads(profile_bytes)
        require(profile.get('TeamIdentifier') == [args.developer_id_team] and profile.get('ProvisionsAllDevices') is True
                and 'OSX' in profile.get('Platform', []) and profile.get('ExpirationDate').replace(tzinfo=timezone.utc) > datetime.now(timezone.utc)
                and any(hashlib.sha1(certificate).hexdigest().upper() == args.signing_identity_sha1 for certificate in profile.get('DeveloperCertificates', [])), 'Developer ID provisioning profile differs or expired')
        prefix = profile['ApplicationIdentifierPrefix']
        require(isinstance(prefix, list) and len(prefix) == 1 and re.fullmatch(r'[A-Z0-9]{10}', prefix[0]), 'Profile application prefix differs')
        require(profile.get('Entitlements', {}).get('com.apple.application-identifier') == prefix[0] + '.' + BUNDLE_ID, 'Profile app identifier differs')
        profile_uuid = profile['UUID']
        require(re.fullmatch(r'[A-Fa-f0-9-]{36}', profile_uuid) and args.provisioning_profile.name == profile_uuid + '.provisionprofile', 'Use the installed UUID provisioning profile')
        options = output / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps({'method': 'developer-id', 'destination': 'export', 'signingStyle': 'manual', 'teamID': args.developer_id_team,
                                           'signingCertificate': args.signing_identity_sha1, 'provisioningProfiles': {BUNDLE_ID: profile_uuid}, 'iCloudContainerEnvironment': 'Production'}))
        export = output / 'export'
        commands.run('developer-id-export', ['xcodebuild', '-exportArchive', '-archivePath', archive, '-exportOptionsPlist', options, '-exportPath', export], timeout=1200)
        final_app = export / APP_NAME
        require(final_app.is_dir(), 'Xcode export produced no app')
        source_content = unsigned_projection(commands, app, output / 'source-comparison')
        require(source_content == unsigned_projection(commands, final_app, output / 'export-comparison'), 'Export changed unsigned bundle content')
        exported_info = plistlib.loads((final_app / 'Contents/Info.plist').read_bytes())
        require(exported_info == info, 'Export changed application metadata')
        embedded = commands.run('embedded-profile', ['security', 'cms', '-D', '-i', final_app / 'Contents/embedded.provisionprofile'])
        require(plistlib.loads(embedded) == profile, 'Export embedded a different provisioning profile')
        entitlement_source = commands.api(f'contents/VoiceInk/VoiceInk.entitlements?ref={args.expected_source_sha}')
        require(entitlement_source.get('encoding') == 'base64', 'Production entitlement policy unavailable')
        expected = plistlib.loads(base64.b64decode(entitlement_source['content'].replace('\n', ''), validate=True))
        expected = json.loads(json.dumps(expected).replace('$(PRODUCT_BUNDLE_IDENTIFIER)', BUNDLE_ID).replace('$(AppIdentifierPrefix)', prefix[0] + '.'))
        expected['com.apple.developer.aps-environment'] = 'production'
        expected.update({'com.apple.application-identifier': prefix[0] + '.' + BUNDLE_ID,
                         'com.apple.developer.team-identifier': args.developer_id_team, 'com.apple.developer.icloud-container-environment': 'Production'})
        claims = plistlib.loads(commands.run('app-entitlements', ['codesign', '--display', '--entitlements', ':-', final_app]))
        require(claims == expected and claims.get('com.apple.security.cs.disable-library-validation') is not True, 'Exported production entitlements differ')
        allowed = profile['Entitlements']
        for key, claim in claims.items():
            if key.startswith('com.apple.security.'):
                continue
            permission = allowed.get(key)
            if isinstance(claim, list):
                require(isinstance(permission, list) and all(any(fnmatch.fnmatchcase(value, pattern) for pattern in permission) for value in claim), 'Restricted entitlement is not authorized by the profile')
            else:
                require(isinstance(claim, str) and isinstance(permission, str) and fnmatch.fnmatchcase(claim, permission), 'Restricted entitlement is not authorized by the profile')
        for path in images(final_app):
            architectures = commands.run('code-architectures', ['lipo', '-archs', path]).decode().split()
            require('arm64' in architectures and set(architectures) <= {'arm64', 'x86_64'}, 'Nested code lacks the supported architecture')
            if path == final_app / 'Contents/MacOS' / info['CFBundleExecutable']:
                require(architectures == ['arm64'], 'Main executable architecture differs from the production build')
            commands.run('nested-code-verify', ['codesign', '--verify', '--strict', path])
            commands.run('nested-code-team', ['codesign', '--verify', '--test-requirement==anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "' + args.developer_id_team + '"', path])
        commands.run('export-deployment', ['python3', ROOT / 'scripts/check-macos-deployment-target.py', final_app])
        commands.run('export-instrumentation', ['bash', ROOT / 'scripts/verify-macos-release-instrumentation.sh', final_app])
        submission = output / 'notary-submission.zip'
        commands.run('notary-package', ['ditto', '-c', '-k', '--keepParent', final_app, submission])
        notary = decode(commands.run('notary-submit', ['xcrun', 'notarytool', 'submit', submission, '--keychain-profile', args.notary_keychain_profile, '--wait', '--output-format', 'json'], timeout=1800))
        require(notary.get('status') == 'Accepted' and re.fullmatch(r'[A-Fa-f0-9-]{36}', notary.get('id', '')), 'Notarization did not accept this submission')
        notary_log = decode(commands.run('notary-log', ['xcrun', 'notarytool', 'log', notary['id'], '--keychain-profile', args.notary_keychain_profile]))
        require(notary_log.get('jobId') == notary['id'] and notary_log.get('status') == 'Accepted'
                and notary_log.get('sha256') == sha(submission), 'Notary log is not bound to the submitted ZIP')
        commands.run('staple-ticket', ['xcrun', 'stapler', 'staple', final_app])
        trust = output / 'final-trust'
        commands.run('final-trust', ['bash', ROOT / 'scripts/verify-macos-notarized-app.sh', final_app, args.developer_id_team, BUNDLE_ID, trust], timeout=500)
        require((trust / 'trust-verdict.txt').read_text().startswith('trust_verdict=passed\n'), 'Final trust verifier produced no verdict')
        require(source_content == unsigned_projection(commands, final_app, output / 'stapled-comparison'), 'Notarization or stapling changed unsigned bundle content')
        require(authenticated_job(commands, producer_run, producer_attempt, args.expected_tooling_sha, PRODUCER_WORKFLOW, FINALIZER_JOB, active=True)['id'] == producer['id'], 'Finalizer job changed')
        frozen = inventory(final_app)
        write(output / 'final-bundle-inventory.json', frozen)
        pending_zip = output / 'final-pending.zip'
        commands.run('final-package', ['ditto', '-c', '-k', '--keepParent', final_app, pending_zip])
        require(inventory(final_app) == frozen, 'App mutated during final packaging')
        unpack(pending_zip, output / 'final-roundtrip', APP_NAME)
        require(inventory(output / 'final-roundtrip' / APP_NAME) == frozen, 'Final ZIP differs from the stapled verified app')
        restored = output / 'restored-final'
        commands.run('restore-final-package', ['ditto', '-x', '-k', pending_zip, restored])
        require(inventory(restored / APP_NAME) == frozen, 'Metadata-preserving extraction changed the final app')
        commands.run('restored-final-trust', ['bash', ROOT / 'scripts/verify-macos-notarized-app.sh', restored / APP_NAME,
                                             args.developer_id_team, BUNDLE_ID, output / 'restored-final-trust'], timeout=500)
        final_zip = output / 'roma.just.talk.app.zip'
        pending_zip.rename(final_zip)
        write(output / 'finalization-result.json', {'schemaVersion': 1, 'state': 'finalized', 'publicationEligible': False,
              'sourceBuild': {'runId': args.source_run_id, 'runAttempt': args.source_run_attempt, 'artifactId': args.source_artifact_id, 'sourceSha': args.expected_source_sha},
              'qualification': {'runId': producer_run, 'runAttempt': producer_attempt, 'toolingSha': args.expected_tooling_sha}, 'jobId': producer['id'],
              'developerIdTeam': args.developer_id_team, 'notarySubmissionId': notary['id'],
              'finalArchive': {'path': final_zip.name, 'sha256': sha(final_zip), 'size': final_zip.stat().st_size}})
        print(json.dumps({'state': 'finalized', 'publicationEligible': False, 'result': str(output / 'finalization-result.json')}))
        return 0
    except (OSError, ValueError, TypeError, KeyError, AttributeError, EOFError, plistlib.InvalidFileException, zipfile.BadZipFile, zlib.error) as error:
        write(output / 'finalization-result.json', {'schemaVersion': 1, 'state': 'blocked', 'publicationEligible': False, 'reason': str(error) if isinstance(error, ValueError) else type(error).__name__})
        print(json.dumps({'state': 'blocked', 'publicationEligible': False, 'result': str(output / 'finalization-result.json')}))
        return 1


parser = argparse.ArgumentParser(description='Finalize one API-authenticated unsigned production archive; never publish.')
for name in ('source-run-id', 'source-run-attempt', 'source-artifact-id'):
    parser.add_argument('--' + name, type=int, required=True)
for name in ('expected-source-sha', 'expected-tooling-sha', 'developer-id-team', 'signing-identity-sha1', 'notary-keychain-profile'):
    parser.add_argument('--' + name, required=True)
parser.add_argument('--provisioning-profile', type=Path, required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args(sys.argv[2:])
require(all(getattr(args, name) > 0 for name in ('source_run_id', 'source_run_attempt', 'source_artifact_id')), 'IDs must be positive')
require(re.fullmatch(r'[a-f0-9]{40}', args.expected_source_sha) and re.fullmatch(r'[a-f0-9]{40}', args.expected_tooling_sha), 'Expected SHAs must be lowercase full commit IDs')
require(re.fullmatch(r'[A-Z0-9]{10}', args.developer_id_team) and re.fullmatch(r'[A-F0-9]{40}', args.signing_identity_sha1), 'Explicit Developer ID team and certificate SHA-1 required')
require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', args.notary_keychain_profile), 'Existing notary profile name required')
os.umask(0o077)
sys.exit(main(args))
PY
