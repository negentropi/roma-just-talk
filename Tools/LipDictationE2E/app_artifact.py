"""Reuse an immutable app build only when the consumer changes proof tools alone."""
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile


REPOSITORY = 'negentropi/roma-just-talk'
REPOSITORY_ID = 1253985786
WORKFLOW = '.github/workflows/lip-dictation-app.yml'
LOCK = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
APP_NAME = 'roma just talk.app'
APP_ID = 'com.negentropi.RomaJustTalk'
PROOF_PATHS = frozenset({
    'Tools/LipDictationE2E/VisualCases.swift',
    'Tools/LipDictationE2E/README.md',
    'Tools/LipDictationE2E/run.py',
    'Tools/LipDictationE2E/app_artifact.py',
    'Tools/LipDictationE2E/test_app_artifact.py',
    '.github/workflows/lip-dictation-replay.yml',
})
REQUIRED_STEPS = (
    'Select Xcode and toolchain',
    'Verify runtime harness core checks',
    'Compile and load the actual runtime proof helper',
    'Prepare static Whisper',
    'Install BlackHole input',
    'Prove text-only Power Mode isolation and all shared core checks',
    'Build release app',
    'Debug unit tests',
    'Prove microphone, paste, auto-send, Power Mode, and permission regressions',
    'Package app',
)
VISUAL_STEP = 'Verify real voice and lip dictation through the app shortcut'


class ArtifactError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise ArtifactError(message)


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1_048_576), b''):
            digest.update(block)
    return digest.hexdigest()


def command(arguments, root=None, combine_output=False):
    result = subprocess.run([str(value) for value in arguments], cwd=root, capture_output=True, timeout=180)
    require(result.returncode == 0, 'Artifact verification command failed: ' + str(arguments[0]))
    return result.stdout + result.stderr if combine_output else result.stdout


def api(endpoint):
    raw = command(['gh', 'api', '--hostname', 'github.com', endpoint])
    require(len(raw) <= 8_000_000, 'GitHub metadata exceeds its bound')
    return json.loads(raw)


def check_host(root, destination, proof_head):
    environment = os.environ
    require(environment.get('GITHUB_ACTIONS') == 'true'
            and environment.get('RUNNER_ENVIRONMENT') == 'github-hosted'
            and environment.get('RUNNER_OS') == 'macOS'
            and sys.platform == 'darwin' and platform.machine() == 'arm64'
            and environment.get('GITHUB_REPOSITORY') == REPOSITORY
            and environment.get('GITHUB_SHA') == proof_head
            and environment.get('GITHUB_REF', '').startswith('refs/heads/ci/lip-dictation-replay-')
            and bool(environment.get('GH_TOKEN')),
            'App replay requires its dedicated fresh GitHub-hosted ARM64 workflow')
    require(os.getuid() != 0
            and command(['stat', '-f', '%u', '/dev/console']).decode().strip() == str(os.getuid()),
            'App replay requires the ordinary desktop owner')
    require(bool(environment.get('RUNNER_TEMP')) and bool(environment.get('GITHUB_WORKSPACE')), 'Missing runner paths')
    temporary = Path(environment['RUNNER_TEMP']).resolve()
    require(temporary.is_absolute() and temporary.is_dir() and temporary != Path('/'), 'Missing runner temporary directory')
    work = destination.parent.resolve()
    require(work != temporary and work.is_relative_to(temporary) and not work.exists()
            and destination.name == APP_NAME, 'Replay app destination must be a fresh owned runner temporary directory')
    require(root.resolve() == Path(environment.get('GITHUB_WORKSPACE', '')).resolve(), 'Unexpected replay checkout')


def validate_run(run, jobs, producer_run, build_head):
    require(type(producer_run) is int and producer_run > 0, 'Invalid producer run ID')
    require(re.fullmatch('[0-9a-f]{40}', build_head) is not None, 'Invalid app build revision')
    require(run.get('id') == producer_run and run.get('head_sha') == build_head
            and run.get('run_attempt') == 1 and run.get('path') == WORKFLOW
            and run.get('name') == 'Verify lip dictation app on macOS'
            and run.get('head_branch', '').startswith('ci/lip-dictation-app-')
            and run.get('event') == 'push' and run.get('status') == 'completed'
            and run.get('conclusion') in ('success', 'failure'), 'Producer run is incomplete or has different provenance')
    for field in ('repository', 'head_repository'):
        require(run.get(field, {}).get('id') == REPOSITORY_ID
                and run.get(field, {}).get('full_name') == REPOSITORY, 'Producer repository or fork differs')
    require(jobs.get('total_count') == 1 and len(jobs.get('jobs', [])) == 1, 'Ambiguous producer job')
    job = jobs['jobs'][0]
    require(job.get('name') == 'verify' and job.get('run_id') == producer_run
            and job.get('run_attempt') == 1 and job.get('status') == 'completed', 'Producer job identity differs')
    steps = job.get('steps', [])
    for name in REQUIRED_STEPS:
        selected = [step for step in steps if step.get('name') == name]
        require(len(selected) == 1 and selected[0].get('conclusion') == 'success', 'Required producer gate did not pass: ' + name)
    uploads = [step for step in steps if step.get('name', '').startswith('Run actions/upload-artifact@')]
    require(len(uploads) == 3 and all(step.get('conclusion') == 'success' for step in uploads), 'Producer artifact uploads did not all pass')
    failed = [step.get('name') for step in steps if step.get('conclusion') == 'failure']
    require(failed == [VISUAL_STEP] if run['conclusion'] == 'failure' else not failed,
            'A producer failure outside the replaced visual proof remains open')


def select_artifact(listing, name, producer_run, build_head):
    artifacts = listing.get('artifacts', [])
    require(listing.get('total_count') == len(artifacts) <= 100, 'Incomplete artifact listing')
    found = [artifact for artifact in artifacts if artifact.get('name') == name]
    require(len(found) == 1, 'Missing or ambiguous producer artifact: ' + name)
    artifact = found[0]
    identity = artifact.get('workflow_run', {})
    require(type(artifact.get('id')) is int and artifact['id'] > 0 and artifact.get('expired') is False
            and identity.get('id') == producer_run and identity.get('head_sha') == build_head
            and identity.get('repository_id') == REPOSITORY_ID
            and identity.get('head_repository_id') == REPOSITORY_ID, 'Artifact run, head, repository, or expiry differs')
    require(type(artifact.get('size_in_bytes')) is int and 0 < artifact['size_in_bytes'] <= 4_000_000_000
            and isinstance(artifact.get('digest'), str)
            and re.fullmatch('sha256:[0-9a-f]{64}', artifact['digest']) is not None,
            'Artifact size or API digest is missing')
    return artifact


def check_changed_paths(raw):
    paths = raw.decode('utf-8').split('\0')
    require(paths[-1] == '', 'Malformed Git path list')
    changed = paths[:-1]
    require(all(path in PROOF_PATHS for path in changed), 'App, dependencies, build inputs, or producer workflow changed')
    return changed


def check_sources(root, build_head, proof_head):
    require(re.fullmatch('[0-9a-f]{40}', proof_head) is not None, 'Invalid proof revision')
    require(command(['git', 'rev-parse', 'HEAD'], root).decode().strip() == proof_head, 'Proof revision differs from checkout')
    require(not command(['git', 'status', '--porcelain=v1', '-z', '--untracked-files=all'], root), 'Replay checkout is dirty')
    exists = subprocess.run(['git', 'cat-file', '-e', build_head + '^{commit}'], cwd=root, capture_output=True).returncode == 0
    if not exists:
        command(['git', 'fetch', '--no-tags', '--depth=1', 'https://github.com/' + REPOSITORY + '.git', build_head], root)
    changed = check_changed_paths(command(['git', 'diff', '--no-renames', '--name-only', '-z', build_head, proof_head], root))
    expected = command(['git', 'show', build_head + ':' + LOCK], root)
    require(expected == command(['git', 'show', proof_head + ':' + LOCK], root), 'Declared dependency locks differ')
    return changed, expected


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *arguments, **keywords):
        return None


def artifact_url(identifier):
    request = urllib.request.Request('https://api.github.com/repos/' + REPOSITORY + '/actions/artifacts/' + str(identifier) + '/zip',
                                     headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    try:
        urllib.request.build_opener(NoRedirect()).open(request, timeout=60)
    except urllib.error.HTTPError as error:
        require(error.code == 302, 'GitHub did not return an artifact download redirect')
        location = error.headers.get('Location', '')
        parsed = urllib.parse.urlsplit(location)
        require(parsed.scheme == 'https' and parsed.hostname and not parsed.username and not parsed.password,
                'Unsafe artifact download redirect')
        return location
    except Exception:
        raise ArtifactError('Artifact redirect request failed') from None
    raise ArtifactError('Artifact download redirect missing')


class RangeReader:
    def __init__(self, url, size):
        self.url, self.size, self.position, self.bytes_read = url, size, 0, 0

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        position = offset if whence == 0 else self.position + offset if whence == 1 else self.size + offset
        require(0 <= position <= self.size, 'ZIP range seek is outside the artifact')
        self.position = position
        return position

    def seekable(self):
        return True

    def read(self, count=-1):
        count = self.size - self.position if count < 0 else min(count, self.size - self.position)
        if count <= 0:
            return b''
        require(self.bytes_read + count <= 8_000_000, 'Dependency-lock range reads exceeded their bound')
        start, end = self.position, self.position + count - 1
        request = urllib.request.Request(self.url, headers={'Range': f'bytes={start}-{end}', 'Accept-Encoding': 'identity'})
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=60) as response:
                require(response.status == 206 and response.headers.get('Content-Range') == f'bytes {start}-{end}/{self.size}',
                        'Artifact server did not honor the exact bounded range')
                data = response.read(count + 1)
        except ArtifactError:
            raise
        except Exception:
            raise ArtifactError('Artifact range read failed') from None
        require(len(data) == count, 'Artifact range length differs')
        self.position += count
        self.bytes_read += count
        return data


def members(archive):
    items = archive.infolist()
    require(len(items) <= 100_000 and len(items) == len({item.filename for item in items}), 'Duplicate or excessive ZIP members')
    for item in items:
        path = PurePosixPath(item.filename)
        require(not path.is_absolute() and '..' not in path.parts and '\\' not in item.filename
                and '\0' not in item.filename and not item.flag_bits & 1, 'Unsafe ZIP member')
    return items


def archived_lock(artifact, expected):
    reader = RangeReader(artifact_url(artifact['id']), artifact['size_in_bytes'])
    with zipfile.ZipFile(reader) as archive:
        selected = [item for item in members(archive) if item.filename == LOCK or item.filename.endswith('/' + LOCK)]
        require(len(selected) == 1, 'Missing or ambiguous actual archived dependency lock')
        item = selected[0]
        require(not item.is_dir() and not stat.S_ISLNK(item.external_attr >> 16) and item.file_size <= 1_000_000,
                'Unsafe archived dependency lock')
        actual = archive.read(item)
    require(actual == expected, 'Actual producer dependency lock differs from both source revisions')
    return actual, {'member': item.filename, 'sha256': hashlib.sha256(actual).hexdigest(),
                    'rangeBytesRead': reader.bytes_read, 'memberCRCVerified': True,
                    'wholeEvidenceArchiveDigestVerified': False,
                    'authenticationBoundary': 'The consumed lock bytes equal both independent Git blobs; the large evidence archive was read in ranges.'}


def download(artifact, destination):
    require(artifact['size_in_bytes'] <= 2_000_000_000, 'App archive exceeds its bound')
    digest, total = hashlib.sha256(), 0
    try:
        request = urllib.request.Request(artifact_url(artifact['id']), headers={'Accept-Encoding': 'identity'})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=120) as response, destination.open('xb') as target:
            require(response.status == 200, 'App artifact download failed')
            for block in iter(lambda: response.read(1_048_576), b''):
                total += len(block)
                require(total <= artifact['size_in_bytes'], 'App archive exceeds its declared size')
                digest.update(block)
                target.write(block)
    except ArtifactError:
        raise
    except Exception:
        raise ArtifactError('App artifact download failed') from None
    require(total == artifact['size_in_bytes'] and 'sha256:' + digest.hexdigest() == artifact['digest'],
            'App artifact bytes differ from the GitHub API digest')


def validate_app_archive(archive):
    items = members(archive)
    links, paths, total = {}, set(), 0
    for item in items:
        path = PurePosixPath(item.filename)
        require(path.parts and path.parts[0] in (APP_NAME, '__MACOSX'), 'Unexpected app archive root')
        paths.add(str(path))
        kind = stat.S_IFMT(item.external_attr >> 16)
        require(kind in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), 'Unsupported app archive item type')
        total += item.file_size
        require(item.file_size <= 2_000_000_000 and total <= 6_000_000_000, 'App archive expansion exceeds its bound')
        if stat.S_ISLNK(item.external_attr >> 16):
            require(path.parts[0] == APP_NAME and item.file_size <= 4096, 'Unsafe app symlink')
            target = archive.read(item).decode('utf-8')
            require(target and not target.startswith('/') and '\\' not in target and '\0' not in target, 'Unsafe app symlink target')
            links[str(path)] = target
    require(APP_NAME + '/Contents/Info.plist' in paths, 'App archive bundle is missing')
    for path in paths:
        require(not any(str(parent) in links for parent in PurePosixPath(path).parents), 'Archive writes through a symlink')
    for link in links:
        pending, resolved, visited = list(PurePosixPath(link).parts), [], set()
        while pending:
            part = pending.pop(0)
            if part in ('', '.'):
                continue
            if part == '..':
                require(len(resolved) > 1, 'App symlink escapes its bundle')
                resolved.pop()
                continue
            resolved.append(part)
            current = '/'.join(resolved)
            if current in links:
                require(current not in visited and len(visited) < 50, 'App symlink cycle')
                visited.add(current)
                resolved.pop()
                pending = list(PurePosixPath(links[current]).parts) + pending
        require(resolved and resolved[0] == APP_NAME, 'App symlink escapes its bundle')


def bundle_fingerprint(app):
    records = []
    for path in sorted([app, *app.rglob('*')]):
        mode = path.lstat().st_mode
        record = {'path': '.' if path == app else path.relative_to(app).as_posix(), 'mode': stat.S_IMODE(mode)}
        if stat.S_ISLNK(mode):
            record['link'] = os.readlink(path)
            require(path.resolve().is_relative_to(app.resolve()), 'Extracted app symlink escapes its bundle')
        elif stat.S_ISREG(mode):
            record.update(bytes=path.stat().st_size, sha256=file_sha256(path))
        else:
            require(stat.S_ISDIR(mode), 'Unsupported extracted bundle item')
            record['directory'] = True
        records.append(record)
    raw = json.dumps(records, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(raw).hexdigest(), records


@dataclass
class VerifiedApp:
    app_path: Path
    provenance: dict
    fingerprint: str
    evidence: Path

    def verify_unchanged(self):
        self.provenance['appArtifactUnchanged'] = False
        try:
            fingerprint, records = bundle_fingerprint(self.app_path)
            (self.evidence / 'bundle-after.json').write_text(json.dumps(records, indent=2) + '\n')
            self.provenance['postRunBundleFingerprintSHA256'] = fingerprint
            require(fingerprint == self.fingerprint, 'Producer app bundle changed during proof')
            command(['codesign', '--verify', '--deep', '--strict', self.app_path])
            self.provenance['appArtifactUnchanged'] = True
        finally:
            (self.evidence / 'provenance.json').write_text(json.dumps(self.provenance, indent=2) + '\n')


def prepare_verified_app(root, evidence, destination, producer_run, declared_build_head, proof_head):
    require(type(producer_run) is int and producer_run > 0
            and isinstance(declared_build_head, str) and re.fullmatch('[0-9a-f]{40}', declared_build_head)
            and isinstance(proof_head, str) and re.fullmatch('[0-9a-f]{40}', proof_head), 'Invalid producer or proof identity')
    root, evidence, destination = Path(root), Path(evidence), Path(destination)
    check_host(root, destination, proof_head)
    work = destination.parent.resolve()
    require(not evidence.resolve().is_relative_to(work) and not work.is_relative_to(evidence.resolve()),
            'App archives must remain outside uploaded proof evidence')
    receipt = {'appBuildHead': declared_build_head, 'proofHead': proof_head, 'producerRun': producer_run,
               'reuseBoundary': 'The immutable producer binary is tested unchanged. External build input provenance belongs to its producer; no fresh-build reproducibility claim.',
               'status': 'blocked'}
    evidence = evidence / 'app-artifact'
    evidence.mkdir(parents=True, exist_ok=False)
    try:
        run = api(f'repos/{REPOSITORY}/actions/runs/{producer_run}')
        jobs = api(f'repos/{REPOSITORY}/actions/runs/{producer_run}/attempts/1/jobs?per_page=100')
        validate_run(run, jobs, producer_run, declared_build_head)
        (evidence / 'producer-run.json').write_text(json.dumps(run, indent=2) + '\n')
        (evidence / 'producer-jobs.json').write_text(json.dumps(jobs, indent=2) + '\n')
        changed, expected_lock = check_sources(root, declared_build_head, proof_head)
        receipt['changedProofPaths'] = changed
        listing = api(f'repos/{REPOSITORY}/actions/runs/{producer_run}/artifacts?per_page=100')
        app_artifact = select_artifact(listing, 'roma.just.talk.app', producer_run, declared_build_head)
        proof_artifact = select_artifact(listing, 'lip-dictation-app-evidence', producer_run, declared_build_head)
        (evidence / 'artifacts.json').write_text(json.dumps([app_artifact, proof_artifact], indent=2) + '\n')
        lock, lock_receipt = archived_lock(proof_artifact, expected_lock)
        (evidence / 'actual.Package.resolved').write_bytes(lock)
        receipt['actualDependencyLock'] = lock_receipt
        work.mkdir(mode=0o700)
        outer, inner = work / 'artifact.zip', work / 'app.zip'
        download(app_artifact, outer)
        with zipfile.ZipFile(outer) as archive:
            items = [item for item in members(archive) if not item.is_dir()]
            require(len(items) == 1 and items[0].filename == 'roma.just.talk.app.zip'
                    and not stat.S_ISLNK(items[0].external_attr >> 16) and items[0].file_size <= 2_000_000_000,
                    'App artifact does not contain its one expected package')
            with archive.open(items[0]) as source, inner.open('xb') as target:
                for block in iter(lambda: source.read(1_048_576), b''):
                    target.write(block)
        with zipfile.ZipFile(inner) as archive:
            validate_app_archive(archive)
        command(['/usr/bin/ditto', '-x', '-k', inner, work])
        require(destination.is_dir() and not destination.is_symlink(), 'Extracted app bundle missing')
        with (destination / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        require(info.get('CFBundleIdentifier') == APP_ID and info.get('CFBundleExecutable') == 'roma just talk', 'Extracted app identity differs')
        command(['codesign', '--verify', '--deep', '--strict', destination])
        signature = command(['codesign', '-d', '--verbose=4', destination], combine_output=True)
        (evidence / 'signature.log').write_bytes(signature)
        fingerprint, records = bundle_fingerprint(destination)
        (evidence / 'bundle-before.json').write_text(json.dumps(records, indent=2) + '\n')
        receipt.update(status='verified', artifactID=app_artifact['id'], artifactSHA256=app_artifact['digest'],
                       innerPackageSHA256=file_sha256(inner), appPath=str(destination),
                       executableSHA256=file_sha256(destination / 'Contents/MacOS/roma just talk'),
                       wholeBundleFingerprintSHA256=fingerprint, bundleItemCount=len(records), producerConclusion=run['conclusion'])
        return VerifiedApp(destination, receipt, fingerprint, evidence)
    except Exception as error:
        receipt['failure'] = str(error) if isinstance(error, ArtifactError) else type(error).__name__
        raise
    finally:
        (evidence / 'provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
