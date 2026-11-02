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
    'Tools/LipDictationE2E/model_cache.py',
    'Tools/LipDictationE2E/test_model_cache.py',
    'Tools/LipCameraProbe/run.py',
    'Tools/LipCameraProbe/README.md',
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
SAME_JOB_WORKFLOW = '.github/workflows/lip-pr-hosted-gates.yml'
SAME_JOB_BRANCH = 'ci/lip-pr-hosted-gates-'
CHECKOUT_ACTION = '11d5960a326750d5838078e36cf38b85af677262'
SAME_JOB_STEPS = ('Build release app', 'Run Debug unit tests',
                  'Prove microphone, paste, auto-send, Power Mode, and permission regressions', 'Package app')
SAME_JOB_E2E = 'Verify current real voice and lip dictation'
CHECKPOINT_SHA256 = '8dd3bbf4e8d6287e87e7c3d9bc65f6238b4d75b12040e10f5589e3c6e76bda8f'
CHECKPOINT_BYTES = 1975266407

# One audited hosted producer. Its API transport revision is not its app checkout.
HOSTED_RUN = 41442208716
HOSTED_BUILD = '095c058ddedfe4986802d88c11fe8a58bc71df15'
HOSTED_TRANSPORT = 'b998507d0595d2d05256ef19c3223279e0e69479'
HOSTED_REF = 'ci/lip-pr-hosted-gates-20261102-b998507d0595'
HOSTED_JOB = 125266577339
HOSTED_WORKFLOW_SHA256 = 'dcaf9bfc80774bd119b9e9cb66db04cc975adcd3975bc1cde53423c4af0acb29'
HOSTED_WORKFLOW_BLOB = '2efd489ec925b6fb2398949fa884629ec10d2b67'
HOSTED_EXECUTABLE_SHA256 = 'd91158569d3266d15cf9d6473ef3fba7b54dd17532dde03704d890e9fe3cff6d'
HOSTED_BUNDLE_SHA256 = '4612e81db2bc5fd9cc1697d4c7bbdcb11c3e7ff73fea168b3ab5a48e6e00b760'
HOSTED_INNER_SHA256 = 'dc6b7da3eabb26a793e43b1a0dcbc162bcff43adf75d925719a65bac19fb3219'
HOSTED_ARTIFACTS = (
    ('app', 'roma.just.talk.app', 13146490251, 40410846,
     'c6253415007f1a3abe4cf4bed99f55ff9f35c642379db31b6dba0b2c613f7a61'),
    ('runtime', 'lip-standard-runtime-evidence-41442208716', 13145198641, 4610820,
     '1ae58fc2fc999b53bda82379847e866283f072283210b0f10cbeea462b9c4688'),
    ('execution', 'lip-pr-hosted-gates-macos-41442208716', 13145053783, 4812,
     '33f8254ee25ab73efc209aba5d6feb15d02b9ce52ee247fc06f8f328c2b8b273'),
)
HOSTED_LOCKS = (LOCK, 'VoiceInk.xcworkspace/xcshareddata/swiftpm/Package.resolved',
                'iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
HOSTED_STEPS = (
    'Checkout the exact PR source',
    'Require an isolated hosted Mac and record the toolchain',
    'Compile and verify autonomous runtime E2E harness',
    'Verify Sonoma-compatible helper',
    'Package runtime E2E helper',
    'Upload runtime E2E helper',
    'Keep disposable test desktop awake',
    'Show Xcode version',
    'Compile visible text latency harness helper',
    'Verify latency helper run target',
    'Verify ad-hoc Library Validation packaging contract',
    'Verify distribution launch evidence contract',
    'Build release app',
    'Verify FluidAudio array reset semantics',
    'Upload FluidAudio test evidence',
    'Verify local bilingual model package',
    'Prove recording cache cleanup regression red and green',
    'Upload recording cache regression evidence',
    'Prove text-only Power Mode isolation and all shared core checks',
    'Install BlackHole input',
    'Run Debug unit tests',
    'Upload Debug test evidence',
    'Prove microphone, paste, auto-send, Power Mode, and permission regressions',
    'Upload Core and semantic-control proof receipts',
    'Reject debug-only release payload',
    'Verify packaged app identity',
    'Reject test-coverage instrumentation in release app',
    'Package app',
    'Upload app artifact',
    'Relocate only the three uploaded standard outputs',
    'Archive the verified generated Qwen package lock',
    SAME_JOB_E2E,
    'Upload actual same-job dictation and cache receipts',
    'Record tested source and external build inputs',
    'Upload hosted execution provenance',
)


@dataclass(frozen=True)
class ProducerBinding:
    profile: str
    app_build_head: str
    transport_head: str


def validate_same_job_workflow(raw, source_head):
    """Check the reviewed wrapper's fixed indentation, not arbitrary YAML semantics."""
    text = raw.decode('utf-8')
    found = re.findall(r'(?ms)^  macos:\n(.*?)(?=^  [A-Za-z0-9_-]+:|\Z)', text)
    require(len(found) == 1, 'Same-job wrapper has no unique macos job')
    block = found[0]
    require(re.search(r'(?m)^    name: Run complete standard macOS gates$', block)
            and re.search(r'(?m)^    runs-on: macos-26$', block), 'Same-job wrapper desktop job differs')
    checkouts = re.findall(r'(?m)^    - (?:name: [^\n]+\n      )?uses: actions/checkout@([0-9a-f]{40})\n'
                           r'      with:\n        ref: ([0-9a-f]{40})$', block)
    require(checkouts == [(CHECKOUT_ACTION, source_head)] and block.count('uses: actions/checkout@') == 1,
            'Same-job wrapper checkout is not pinned to the declared feature source')
    pins = re.findall(r'(?m)^ +TESTED_SOURCE_HEAD: ([0-9a-f]{40})$', text)
    require(pins and all(pin == source_head for pin in pins), 'Same-job wrapper source variable differs')
    steps = re.findall(r'(?ms)^    - name: ([^\n]+)\n(.*?)(?=^    - |\Z)', block)
    build = [body for name, body in steps if name == 'Build release app']
    require(len(build) == 1 and re.search(r'(?m)^      run: make local CONFIGURATION=Release$', build[0]),
            'Same-job wrapper does not run the existing Release build command')
    proof = [body for name, body in steps if name == SAME_JOB_E2E]
    require(len(proof) == 1 and '--same-job-build' in proof[0] and '--producer-run' not in proof[0]
            and '--app-source-head "$TESTED_SOURCE_HEAD"' in proof[0], 'Same-job wrapper proof profile differs')
    return {'workflowSHA256': hashlib.sha256(raw).hexdigest(), 'macosBlockSHA256': hashlib.sha256(block.encode()).hexdigest(),
            'checkoutSourceHead': source_head, 'method': 'Bounded literal checks of the reviewed fixed-indentation wrapper; not a general YAML parser.'}


def validate_mac_project_build(raw):
    recipes = re.findall(r'(?ms)^local: check setup\n(.*?)(?=^[^\s#][^\n]*:|\Z)', raw.decode('utf-8'))
    require(len(recipes) == 1, 'Pinned Makefile has no unique local build recipe')
    lines = re.findall(r'(?m)^\txcodebuild[^\n]*$', recipes[0])
    require(lines == ['\txcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration "$(CONFIGURATION)" \\']
            and re.findall(r'(?<!\S)-(?:project|workspace)\s+\S+', recipes[0]) == ['-project VoiceInk.xcodeproj'],
            'Same-job build requires the exact existing Mac project recipe, not a workspace build')
    return {'target': 'make local CONFIGURATION=Release', 'project': 'VoiceInk.xcodeproj', 'dependencyLock': LOCK,
            'boundary': 'The pinned local recipe uses xcodebuild -project. The root iOS workspace is not an input to this Mac build.'}


def app_resources(root, app):
    found = [path.parent for path in app.rglob('manifest.json') if path.parent.name == 'Resources'
             and any(part.startswith('VoiceInkLip') and part.endswith('.bundle') for part in path.relative_to(app).parts)]
    require(len(found) == 1, 'Verified app has no unique native lip resource bundle')
    resources, records = found[0], []
    source = root / 'VoiceInkLip/Sources/VoiceInkLip/Resources'
    for path in sorted(source.rglob('*')):
        if path.is_file():
            actual = resources / path.relative_to(source)
            require(actual.is_file() and not actual.is_symlink() and file_sha256(actual) == file_sha256(path),
                    'Actual app lip resource differs from current source: ' + str(path.relative_to(source)))
            records.append({'path': path.relative_to(source).as_posix(), 'sha256': file_sha256(actual)})
    manifest = json.loads((resources / 'manifest.json').read_text())
    require(manifest['checkpoint_bytes'] == CHECKPOINT_BYTES and manifest['checkpoint_sha256'] == CHECKPOINT_SHA256
            and len(manifest['storages']) == 658, 'Actual app checkpoint manifest differs')
    return resources, manifest, records


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


def producer_binding(run, jobs, producer_run, build_head):
    if run.get('path') == WORKFLOW:
        validate_run(run, jobs, producer_run, build_head)
        return ProducerBinding('legacyAppWorkflow', build_head, build_head)
    require(run.get('path') == SAME_JOB_WORKFLOW, 'Unrecognized producer workflow')
    require(producer_run == HOSTED_RUN and build_head == HOSTED_BUILD
            and run.get('id') == HOSTED_RUN and run.get('head_sha') == HOSTED_TRANSPORT
            and run.get('workflow_id') == 402555449 and run.get('run_attempt') == 1
            and run.get('name') == 'Run standard lip PR gates on isolated hosted Macs'
            and run.get('head_branch') == HOSTED_REF and run.get('event') == 'push'
            and run.get('status') == 'completed' and run.get('conclusion') == 'failure',
            'Hosted producer is not the exact audited run and app source')
    for field in ('repository', 'head_repository'):
        require(run.get(field, {}).get('id') == REPOSITORY_ID
                and run.get(field, {}).get('full_name') == REPOSITORY
                and run.get(field, {}).get('fork') is False, 'Hosted producer repository or fork differs')
    for field in ('actor', 'triggering_actor'):
        require(run.get(field, {}).get('id') == 171460575 and run.get(field, {}).get('login') == 'negentropi',
                'Hosted producer actor differs')
    require(jobs.get('total_count') == 1 and len(jobs.get('jobs', [])) == 1, 'Ambiguous hosted producer job')
    job = jobs['jobs'][0]
    require(job.get('id') == HOSTED_JOB and job.get('run_id') == HOSTED_RUN and job.get('run_attempt') == 1
            and job.get('head_sha') == HOSTED_TRANSPORT and job.get('name') == 'Run complete standard macOS gates'
            and job.get('labels') == ['macos-26'] and job.get('runner_group_name') == 'GitHub Actions'
            and job.get('status') == 'completed' and job.get('conclusion') == 'failure', 'Hosted producer job differs')
    steps = job.get('steps', [])
    expected = ['Set up job', *HOSTED_STEPS, 'Post Checkout the exact PR source', 'Complete job']
    require([step.get('name') for step in steps] == expected, 'Hosted producer steps are missing, duplicated, or reordered')
    for step in steps:
        require(step.get('status') == 'completed'
                and step.get('conclusion') == ('failure' if step['name'] == SAME_JOB_E2E else 'success'),
                'Hosted producer gate did not pass: ' + step['name'])
    return ProducerBinding('pinnedHostedWorkflow', build_head, HOSTED_TRANSPORT)


def validate_hosted_workflow(raw, blob):
    require(hashlib.sha256(raw).hexdigest() == HOSTED_WORKFLOW_SHA256 and blob == HOSTED_WORKFLOW_BLOB,
            'Hosted producer complete workflow differs from the audited bytes')
    return validate_same_job_workflow(raw, HOSTED_BUILD)


def check_hosted_transport(root):
    if subprocess.run(['git', 'cat-file', '-e', HOSTED_TRANSPORT + '^{commit}'], cwd=root, capture_output=True).returncode:
        command(['git', 'fetch', '--no-tags', '--depth=2', 'https://github.com/' + REPOSITORY + '.git', HOSTED_TRANSPORT], root)
    command(['git', 'merge-base', '--is-ancestor', HOSTED_BUILD, HOSTED_TRANSPORT], root)
    changed = command(['git', 'diff', '--no-renames', '--name-status', '-z', HOSTED_BUILD, HOSTED_TRANSPORT], root)
    require(changed == ('A\0' + SAME_JOB_WORKFLOW + '\0').encode(), 'Hosted transport changes more than its one wrapper')
    raw = command(['git', 'show', HOSTED_TRANSPORT + ':' + SAME_JOB_WORKFLOW], root)
    blob = command(['git', 'rev-parse', HOSTED_TRANSPORT + ':' + SAME_JOB_WORKFLOW], root).decode().strip()
    receipt = validate_hosted_workflow(raw, blob)
    receipt['macProjectBuild'] = validate_mac_project_build(command(['git', 'show', HOSTED_BUILD + ':Makefile'], root))
    return receipt


def select_hosted_artifacts(listing):
    selected = {}
    for role, name, identifier, size, digest in HOSTED_ARTIFACTS:
        item = select_artifact(listing, name, HOSTED_RUN, HOSTED_TRANSPORT)
        require(item['id'] == identifier and item['size_in_bytes'] == size and item['digest'] == 'sha256:' + digest,
                'Hosted producer artifact differs from its audited ID, size, or full digest: ' + name)
        selected[role] = item
    return selected


def extract_hosted_receipts(path, destination):
    destination.mkdir()
    with zipfile.ZipFile(path) as archive:
        items = members(archive)
        require(sum(item.file_size for item in items) <= 20_000_000, 'Hosted evidence expansion exceeds its bound')
        for item in items:
            require(not item.is_dir() and stat.S_IFMT(item.external_attr >> 16) in (0, stat.S_IFREG)
                    and item.file_size <= 2_000_000
                    and PurePosixPath(item.filename).suffix in ('.json', '.jsonl', '.resolved', '.txt', '.log', '.png'),
                    'Unsafe hosted evidence member')
            target = destination / item.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream:
                stream.write(archive.read(item))


def validate_hosted_receipts(root, proof_head, runtime, execution, expected_lock, workflow):
    producer = json.loads((runtime / 'provenance.json').read_bytes())
    recorded = json.loads((execution / 'provenance.json').read_bytes())
    require(all(producer.get(key) == HOSTED_BUILD for key in ('appBuildHead', 'proofHead', 'checkoutSourceHead'))
            and producer.get('transportHead') == HOSTED_TRANSPORT and producer.get('runID') == HOSTED_RUN
            and producer.get('jobID') == HOSTED_JOB and producer.get('status') == 'verified'
            and producer.get('sameJobSourcesUnchanged') is True and producer.get('appArtifactUnchanged') is True
            and producer.get('workflowSHA256') == workflow['workflowSHA256']
            and producer.get('macosBlockSHA256') == workflow['macosBlockSHA256']
            and producer.get('macProjectBuild') == workflow['macProjectBuild'], 'Hosted runtime source or integrity receipt differs')
    require(recorded.get('testedSourceHead') == HOSTED_BUILD and recorded.get('transportHead') == HOSTED_TRANSPORT
            and recorded.get('transportRef') == 'refs/heads/' + HOSTED_REF and recorded.get('runID') == str(HOSTED_RUN)
            and recorded.get('runAttempt') == '1' and recorded.get('job') == 'macos', 'Hosted execution identity differs')
    lock_hashes = {}
    for name in HOSTED_LOCKS:
        built = command(['git', 'show', HOSTED_BUILD + ':' + name], root)
        require(built == command(['git', 'show', proof_head + ':' + name], root), 'Hosted dependency source locks differ')
        lock_hashes[name] = hashlib.sha256(built).hexdigest()
    actual = (runtime / 'actual.Package.resolved').read_bytes()
    require(actual == expected_lock and hashlib.sha256(actual).hexdigest() == lock_hashes[LOCK]
            and producer.get('actualDependencyLockSHA256') == lock_hashes[LOCK]
            and recorded.get('dependencyLockSHA256') == lock_hashes, 'Hosted actual dependency lock or three-lock map differs')
    return producer, {'rawMacProjectLockSHA256': lock_hashes[LOCK], 'trackedLockSHA256': lock_hashes,
                      'boundary': 'Mac project lock bytes are archived; other two tracked locks have authenticated actual producer hash receipts. All equal both source heads.'}


def validate_hosted_bundle(producer, fingerprint, records, executable_hash, resources, runtime):
    before = json.loads((runtime / 'bundle-before.json').read_bytes())
    after = json.loads((runtime / 'bundle-after.json').read_bytes())
    require(fingerprint == HOSTED_BUNDLE_SHA256 and len(records) == 401 and records == before == after
            and producer.get('wholeBundleFingerprintSHA256') == producer.get('postRunBundleFingerprintSHA256') == fingerprint,
            'Extracted hosted bundle differs from producer before/after records')
    require(executable_hash == HOSTED_EXECUTABLE_SHA256
            and producer.get('executableSHA256') == producer.get('postRunExecutableSHA256') == executable_hash,
            'Extracted hosted executable differs from producer')
    require(resources == producer.get('appResourceHashes') == producer.get('postRunAppResourceHashes'),
            'Extracted hosted resources differ from producer')


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
        binding = producer_binding(run, jobs, producer_run, declared_build_head)
        receipt.update(producerProfile=binding.profile, producerTransportHead=binding.transport_head,
                       producerConclusion=run['conclusion'])
        (evidence / 'producer-run.json').write_text(json.dumps(run, indent=2) + '\n')
        (evidence / 'producer-jobs.json').write_text(json.dumps(jobs, indent=2) + '\n')
        changed, expected_lock = check_sources(root, binding.app_build_head, proof_head)
        receipt['changedProofPaths'] = changed
        listing = api(f'repos/{REPOSITORY}/actions/runs/{producer_run}/artifacts?per_page=100')
        producer = None
        if binding.profile == 'pinnedHostedWorkflow':
            workflow = check_hosted_transport(root)
            artifacts = select_hosted_artifacts(listing)
            app_artifact = artifacts['app']
            (evidence / 'artifacts.json').write_text(json.dumps(list(artifacts.values()), indent=2) + '\n')
            work.mkdir(mode=0o700)
            for role in ('runtime', 'execution'):
                archive = work / (role + '.zip')
                download(artifacts[role], archive)
                extract_hosted_receipts(archive, evidence / ('producer-' + role))
            runtime = evidence / 'producer-runtime/lip-dictation-e2e/same-job-build'
            execution = evidence / 'producer-execution'
            producer, locks = validate_hosted_receipts(root, proof_head, runtime, execution, expected_lock, workflow)
            receipt.update(producerWorkflow=workflow, actualDependencyLock=locks, historicalSetupUsed=False,
                           currentSetupBoundary='The explicitly selected setup profile and all cases must pass in this run; no historical Setup pass is transferred.',
                           producerProofArchivesFullyVerified=True)
        else:
            app_artifact = select_artifact(listing, 'roma.just.talk.app', producer_run, binding.transport_head)
            proof_artifact = select_artifact(listing, 'lip-dictation-app-evidence', producer_run, binding.transport_head)
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
        if producer is not None:
            require(file_sha256(inner) == HOSTED_INNER_SHA256, 'Hosted inner app package differs')
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
        if producer is not None:
            _, _, resources = app_resources(root, destination)
            validate_hosted_bundle(producer, fingerprint, records,
                                   file_sha256(destination / 'Contents/MacOS/roma just talk'), resources, runtime)
            receipt['appResourceHashes'] = resources
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
