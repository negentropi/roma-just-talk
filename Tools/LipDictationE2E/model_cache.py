"""One pinned CI checkpoint transport; unchanged native installer owns publication."""
import base64
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import zipfile

from app_artifact import APP_ID, APP_NAME, LOCK, REPOSITORY, REPOSITORY_ID, VerifiedApp, api, bundle_fingerprint, command, download, file_sha256, members, require, select_artifact


CACHE_RUN = 41172814095
CACHE_HEAD = '515983d4a090fc038608aa00479965a739b10f14'
CACHE_BRANCH = 'ci/lip-model-cache-ba2effb0d0394934839f605434913b50'
CACHE_WORKFLOW = '.github/workflows/lip-model-cache-transport.yml'
CACHE_WORKFLOW_SHA256 = '93e773f026eba13c14ee18b74d4fbcafa412c8fdb971b5e8dcfc5abfda078f69'
CACHE_NAME = 'braven-publisher-checkpoint-8dd3bbf4e8d6287e'
CACHE_ARTIFACT_ID = 13032296667
CACHE_ARTIFACT_DIGEST = 'sha256:244374f617f1421d9108b7ac27059ec3821f92937d4c089dbc330b7140d6bd63'
SETUP_RUN = 41165570823
APP_HEAD = '49d045815749a043016634a2604decfbacbb9803'
APP_EXECUTABLE = 'bc1e4646779f39c668b58f97cb8a70213549c477977d6edb1b50559482ab5d67'
SETUP_ARTIFACT_ID = 13029488782
SETUP_ARTIFACT_DIGEST = 'sha256:9c9dd998a6dcafed99a2d4107a231b769d90b8521ccf40938c5f74b8daf36756'
CHECKPOINT_SHA256 = '8dd3bbf4e8d6287e87e7c3d9bc65f6238b4d75b12040e10f5589e3c6e76bda8f'
CHECKPOINT_BYTES = 1975266407
NOTICES = {'notices/LICENSE': 'Tools/BRAVEn/Upstream/LICENSE',
           'notices/README.md': 'Tools/BRAVEn/Upstream/README.md',
           'notices/provenance.json': 'Tools/BRAVEn/provenance.json'}
SAME_JOB_WORKFLOW = '.github/workflows/lip-pr-hosted-gates.yml'
SAME_JOB_BRANCH = 'ci/lip-pr-hosted-gates-'
CHECKOUT_ACTION = '11d5960a326750d5838078e36cf38b85af677262'
SAME_JOB_STEPS = ('Build release app', 'Run Debug unit tests',
                  'Prove microphone, paste, auto-send, Power Mode, and permission regressions', 'Package app')
SAME_JOB_E2E = 'Verify current real voice and lip dictation'
SETUP_INPUTS = (
    'VoiceInk/Views/Settings', 'VoiceInk/Transcription/LipDictation', 'VoiceInk/Transcription/Engine',
    'VoiceInk/Services/CaptureAuthorizationDecision.swift', 'VoiceInk/VoiceInk.swift', 'VoiceInk/AppDefaults.swift', 'VoiceInk/Info.plist',
    'VoiceInk/VoiceInk.entitlements', 'VoiceInk/VoiceInk.local.entitlements',
    'VoiceInkCore/Sources/VoiceInkCore/LipDictationPreference.swift',
    'VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift', 'VoiceInkCore/Package.swift', 'VoiceInkCore/Package.resolved',
    'VoiceInkLip', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj',
    'Makefile', 'LocalBuild.xcconfig', 'scripts/verify-static-whisper-xcframework.sh',
    'scripts/verify-static-whisper-app.sh', 'scripts/verify-adhoc-library-validation.sh',
)


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


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


def validate_same_job_run(run, jobs, environment):
    run_id, attempt = int(environment['GITHUB_RUN_ID']), int(environment['GITHUB_RUN_ATTEMPT'])
    transport = environment['GITHUB_SHA']
    require(attempt > 0 and run.get('id') == run_id and run.get('head_sha') == transport and run.get('run_attempt') == attempt
            and run.get('path') == SAME_JOB_WORKFLOW and run.get('event') == 'push'
            and run.get('head_branch') == environment['GITHUB_REF'].removeprefix('refs/heads/')
            and run.get('status') == 'in_progress', 'Same-job build run identity differs')
    for key in ('repository', 'head_repository'):
        require(run.get(key, {}).get('id') == REPOSITORY_ID and run.get(key, {}).get('full_name') == REPOSITORY,
                'Same-job build repository or fork differs')
    require(jobs.get('total_count') == len(jobs.get('jobs', [])) <= 10, 'Same-job job listing is incomplete')
    selected = [job for job in jobs['jobs'] if job.get('name') == 'Run complete standard macOS gates']
    require(len(selected) == 1, 'Same-job macos job is ambiguous')
    job = selected[0]
    require(job.get('run_id') == run_id and job.get('run_attempt') == attempt
            and job.get('head_sha') == transport and job.get('status') == 'in_progress'
            and job.get('runner_name') == environment['RUNNER_NAME'] and job.get('labels') == ['macos-26'],
            'Same-job desktop runner identity differs')
    steps = job.get('steps', [])
    proof = [index for index, step in enumerate(steps) if step.get('name') == SAME_JOB_E2E]
    require(len(proof) == 1 and not any(step.get('conclusion') == 'failure' for step in steps),
            'Same-job proof step is missing or a prior gate failed')
    for name in SAME_JOB_STEPS:
        found = [(index, step) for index, step in enumerate(steps) if step.get('name') == name]
        require(len(found) == 1 and found[0][0] < proof[0] and found[0][1].get('status') == 'completed'
                and found[0][1].get('conclusion') == 'success', 'Same-job gate did not pass before proof: ' + name)
    return job


def ensure_commit(root, head):
    require(re.fullmatch('[0-9a-f]{40}', head) is not None, 'Invalid same-job source revision')
    if subprocess.run(['git', 'cat-file', '-e', head + '^{commit}'], cwd=root, capture_output=True).returncode:
        command(['git', 'fetch', '--no-tags', '--depth=2', 'https://github.com/' + REPOSITORY + '.git', head], root)


def validate_mac_project_build(raw):
    recipes = re.findall(r'(?ms)^local: check setup\n(.*?)(?=^[^\s#][^\n]*:|\Z)', raw.decode('utf-8'))
    require(len(recipes) == 1, 'Pinned Makefile has no unique local build recipe')
    lines = re.findall(r'(?m)^\txcodebuild[^\n]*$', recipes[0])
    require(lines == ['\txcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration "$(CONFIGURATION)" \\']
            and re.findall(r'(?<!\S)-(?:project|workspace)\s+\S+', recipes[0]) == ['-project VoiceInk.xcodeproj'],
            'Cached Setup source scope requires the exact existing Mac project build, not a workspace build')
    return {'target': 'make local CONFIGURATION=Release', 'project': 'VoiceInk.xcodeproj', 'dependencyLock': LOCK,
            'boundary': 'The pinned local recipe uses xcodebuild -project. The root iOS workspace is not an input to this Mac build.'}


def check_same_job_sources(root, source_head, transport):
    require(command(['git', 'rev-parse', 'HEAD'], root).decode().strip() == source_head, 'Declared feature source differs from git HEAD')
    require(not command(['git', 'status', '--porcelain=v1', '-z', '--untracked-files=all'], root), 'Same-job checkout is dirty')
    ensure_commit(root, transport)
    command(['git', 'merge-base', '--is-ancestor', source_head, transport], root)
    changed = command(['git', 'diff', '--no-renames', '--name-status', '-z', source_head, transport], root)
    require(changed == ('A\0' + SAME_JOB_WORKFLOW + '\0').encode(), 'Transport changes more than its one added wrapper')
    workflow = command(['git', 'show', transport + ':' + SAME_JOB_WORKFLOW], root)
    receipt = validate_same_job_workflow(workflow, source_head)
    ensure_commit(root, APP_HEAD)
    old = command(['git', 'ls-tree', '-r', '-z', APP_HEAD, '--', *SETUP_INPUTS], root)
    current = command(['git', 'ls-tree', '-r', '-z', source_head, '--', *SETUP_INPUTS], root)
    require(old and old == current, 'Prior Setup implementation, resources, dependencies, or build inputs changed')
    names = [entry.split(b'\t', 1)[1].decode() for entry in current.split(b'\0') if entry]
    require(all(any(name == path or name.startswith(path + '/') for name in names) for path in SETUP_INPUTS),
            'A required Setup source path is absent')
    receipt['macProjectBuild'] = validate_mac_project_build(command(['git', 'show', source_head + ':Makefile'], root))
    receipt['setupSources'] = {'status': 'verified', 'priorSourceHead': APP_HEAD, 'currentSourceHead': source_head,
                             'paths': list(SETUP_INPUTS), 'gitTreeManifestSHA256': hashlib.sha256(current).hexdigest(),
                             'gitTreeEntries': current.decode().split('\0')[:-1]}
    return receipt


def prepare_same_job_app(root, evidence, destination, source_head):
    environment = os.environ
    transport = environment.get('GITHUB_SHA', '')
    require(environment.get('GITHUB_ACTIONS') == 'true' and environment.get('RUNNER_ENVIRONMENT') == 'github-hosted'
            and environment.get('RUNNER_OS') == 'macOS' and environment.get('RUNNER_ARCH') == 'ARM64'
            and sys.platform == 'darwin' and platform.machine() == 'arm64' and os.getuid() != 0
            and environment.get('GITHUB_REPOSITORY') == REPOSITORY and environment.get('GITHUB_JOB') == 'macos'
            and environment.get('GITHUB_REF', '').startswith('refs/heads/' + SAME_JOB_BRANCH)
            and environment.get('GITHUB_WORKFLOW_REF') == REPOSITORY + '/' + SAME_JOB_WORKFLOW + '@' + environment.get('GITHUB_REF', '')
            and re.fullmatch('[0-9a-f]{40}', source_head) and re.fullmatch('[0-9a-f]{40}', transport)
            and all(re.fullmatch('[1-9][0-9]*', environment.get(key, '')) for key in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'))
            and bool(environment.get('RUNNER_NAME')) and bool(environment.get('GH_TOKEN')),
            'Same-job build requires its dedicated trusted hosted workflow')
    require(root.resolve() == Path(environment.get('GITHUB_WORKSPACE', '')).resolve()
            and command(['stat', '-f', '%u', '/dev/console']).decode().strip() == str(os.getuid()), 'Same-job desktop or checkout owner differs')
    require(destination == Path.home() / 'Applications' / APP_NAME and destination.is_dir() and not destination.is_symlink(),
            'Same-job proof requires the installed Release app from make local')
    receipt = check_same_job_sources(root, source_head, transport)
    run = api(f'repos/{REPOSITORY}/actions/runs/{environment["GITHUB_RUN_ID"]}')
    jobs = api(f'repos/{REPOSITORY}/actions/runs/{environment["GITHUB_RUN_ID"]}/attempts/{environment["GITHUB_RUN_ATTEMPT"]}/jobs?per_page=100')
    job = validate_same_job_run(run, jobs, environment)
    output = evidence / 'same-job-build'
    output.mkdir(exist_ok=False)
    write(output / 'run.json', run)
    write(output / 'jobs.json', jobs)
    with (destination / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    require(info.get('CFBundleIdentifier') == APP_ID and info.get('CFBundleExecutable') == 'roma just talk', 'Same-job app identity differs')
    command(['codesign', '--verify', '--deep', '--strict', destination])
    (output / 'signature.log').write_bytes(command(['codesign', '-d', '--verbose=4', destination], combine_output=True))
    fingerprint, records = bundle_fingerprint(destination)
    write(output / 'bundle-before.json', records)
    _, _, resource_hashes = app_resources(root, destination)
    lock = (root / LOCK).read_bytes()
    require(lock == command(['git', 'show', source_head + ':' + LOCK], root), 'Same-job dependency lock changed during build')
    (output / 'actual.Package.resolved').write_bytes(lock)
    receipt.update(status='verified', buildOrigin='sameJobRelease', appBuildHead=source_head, proofHead=source_head,
                   transportHead=transport, runID=run['id'], jobID=job['id'], appPath=str(destination),
                   executableSHA256=file_sha256(destination / 'Contents/MacOS/roma just talk'),
                   wholeBundleFingerprintSHA256=fingerprint, appResourceHashes=resource_hashes,
                   actualDependencyLockSHA256=hashlib.sha256(lock).hexdigest(),
                   boundary='Fresh Release from the current trusted hosted job. Prior download evidence covers unchanged Setup sources only, not this executable.')
    write(output / 'provenance.json', receipt)
    return VerifiedApp(destination, receipt, fingerprint, output)


def verify_same_job_unchanged(root, app):
    app.provenance['sameJobSourcesUnchanged'] = False
    try:
        app.verify_unchanged()
        sources = check_same_job_sources(root, app.provenance['appBuildHead'], app.provenance['transportHead'])
        require(sources['workflowSHA256'] == app.provenance['workflowSHA256']
                and sources['setupSources'] == app.provenance['setupSources'], 'Same-job source binding changed during proof')
        _, _, resources = app_resources(root, app.app_path)
        require(resources == app.provenance['appResourceHashes'], 'Same-job lip resources changed during proof')
        executable = file_sha256(app.app_path / 'Contents/MacOS/roma just talk')
        require(executable == app.provenance['executableSHA256'], 'Same-job executable changed during proof')
        app.provenance.update(sameJobSourcesUnchanged=True, postRunExecutableSHA256=executable,
                              postRunAppResourceHashes=resources)
    finally:
        write(app.evidence / 'provenance.json', app.provenance)


def validate_cache_run(run, jobs, requested):
    require(type(requested) is int and requested == CACHE_RUN, 'Cache run is not the pinned checkpoint producer')
    require(run.get('id') == CACHE_RUN and run.get('head_sha') == CACHE_HEAD and run.get('run_attempt') == 1
            and run.get('workflow_id') == 402499348 and run.get('path') == CACHE_WORKFLOW
            and run.get('name') == 'Transport verified publisher checkpoint for one CI replay'
            and run.get('head_branch') == CACHE_BRANCH and run.get('event') == 'push'
            and run.get('status') == 'completed' and run.get('conclusion') == 'success', 'Cache producer provenance differs')
    for key in ('repository', 'head_repository'):
        require(run.get(key, {}).get('id') == REPOSITORY_ID and run.get(key, {}).get('full_name') == REPOSITORY,
                'Cache producer repository differs')
    require(jobs.get('total_count') == 1 and len(jobs.get('jobs', [])) == 1, 'Ambiguous cache producer job')
    job = jobs['jobs'][0]
    require(job.get('id') == 124454201080 and job.get('name') == 'upload' and job.get('run_id') == CACHE_RUN
            and job.get('run_attempt') == 1 and job.get('status') == 'completed' and job.get('conclusion') == 'success'
            and job.get('labels') == [CACHE_BRANCH.removeprefix('ci/')], 'Cache upload job identity differs')
    steps = job.get('steps', [])
    for name in ('Verify exact job and original publisher bytes', 'Upload one-day repository-scoped checkpoint artifact', 'Record artifact receipt'):
        found = [step for step in steps if step.get('name') == name]
        require(len(found) == 1 and found[0].get('conclusion') == 'success', 'Cache producer gate did not pass: ' + name)
    require(not any(step.get('conclusion') == 'failure' for step in steps), 'Cache producer has a failed step')


def validate_cache_artifact(artifact):
    require(CACHE_ARTIFACT_ID is not None and CACHE_ARTIFACT_DIGEST is not None, 'Cache artifact API pins are pending')
    require(artifact['id'] == CACHE_ARTIFACT_ID and artifact['digest'] == CACHE_ARTIFACT_DIGEST,
            'Cache artifact ID or API archive digest differs')


def validate_prior_setup(setup, summary, app, setup_sources=None):
    if setup_sources is None:
        require(app.get('status') == 'verified' and app.get('producerRun') == SETUP_RUN and app.get('appBuildHead') == APP_HEAD
                and app.get('executableSHA256') == APP_EXECUTABLE, 'Prior Setup does not belong to this immutable app')
    else:
        require(app.get('status') == 'verified' and app.get('buildOrigin') == 'sameJobRelease'
                and app.get('appBuildHead') == app.get('proofHead') == setup_sources.get('currentSourceHead')
                and setup_sources.get('status') == 'verified' and setup_sources.get('priorSourceHead') == APP_HEAD
                and setup_sources.get('paths') == list(SETUP_INPUTS)
                and re.fullmatch('[0-9a-f]{64}', setup_sources.get('gitTreeManifestSHA256', '')),
                'Prior Setup sources are not bound to the verified current-job app')
    require(all(summary.get(key) == APP_HEAD for key in ('sourceHead', 'declaredAppSourceHead', 'appBuildHead'))
            and summary.get('appExecutableSHA256') == APP_EXECUTABLE, 'Prior Setup app source or executable differs')
    require(setup.get('scenario') == 'setup' and all(setup.get(key) is True for key in
            ('passed', 'actualSetupButtonPressed', 'actualSetupUIReady', 'actualModeControlsChanged', 'restored')),
            'Prior evidence did not pass the actual Set Up UI and download gate')


def prior_setup(work, evidence, app):
    listing = api(f'repos/{REPOSITORY}/actions/runs/{SETUP_RUN}/artifacts?per_page=100')
    artifact = select_artifact(listing, 'lip-dictation-runtime-evidence', SETUP_RUN, APP_HEAD)
    require(artifact['id'] == SETUP_ARTIFACT_ID and artifact['digest'] == SETUP_ARTIFACT_DIGEST
            and artifact['size_in_bytes'] <= 20_000_000, 'Prior Setup artifact identity differs')
    archive_path = work / 'prior-setup.zip'
    download(artifact, archive_path)
    reports = {}
    with zipfile.ZipFile(archive_path) as archive:
        items = members(archive)
        for name in ('setup.json', 'summary.json'):
            found = [item for item in items if item.filename == 'lip-dictation-e2e/' + name]
            require(len(found) == 1 and not found[0].is_dir() and not stat.S_ISLNK(found[0].external_attr >> 16)
                    and found[0].file_size <= 1_000_000, 'Prior Setup report missing or unsafe')
            reports[name] = json.loads(archive.read(found[0]))
            write(evidence / ('prior-' + name), reports[name])
    setup_sources = app.get('setupSources') if app.get('buildOrigin') == 'sameJobRelease' else None
    validate_prior_setup(reports['setup.json'], reports['summary.json'], app, setup_sources)
    same_binary = setup_sources is None
    return {'run': SETUP_RUN, 'artifactID': artifact['id'], 'archiveSHA256': artifact['digest'],
            'wholeArchiveDigestVerified': True, 'actualSetupButtonPressed': True,
            'appBuildHead': APP_HEAD, 'executableSHA256': APP_EXECUTABLE,
            'sameExecutable': same_binary, 'evidenceScope': 'sameExecutable' if same_binary else 'unchangedSetupSources',
            'setupSources': setup_sources,
            'boundary': ('Prior real Set Up/download success for the same executable; not current fresh Setup.' if same_binary
                         else 'Prior real Set Up/download success for a different executable with exactly unchanged Setup sources; no current fresh Set Up or download claim.')}


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
                    'Actual app lip resource differs from unchanged source: ' + str(path.relative_to(source)))
            records.append({'path': path.relative_to(source).as_posix(), 'sha256': file_sha256(actual)})
    manifest = json.loads((resources / 'manifest.json').read_text())
    require(manifest['checkpoint_bytes'] == CHECKPOINT_BYTES and manifest['checkpoint_sha256'] == CHECKPOINT_SHA256
            and len(manifest['storages']) == 658, 'Actual app checkpoint manifest differs')
    return resources, manifest, records


def extract_checkpoint(archive_path, work, package, manifest):
    with zipfile.ZipFile(archive_path) as archive:
        items = members(archive)
        require({item.filename for item in items} == {'braven-large-self.pth', *NOTICES}, 'Unexpected checkpoint archive members')
        for item in items:
            require(not item.is_dir() and stat.S_IFMT(item.external_attr >> 16) in (0, stat.S_IFREG), 'Unsafe checkpoint archive member')
            if item.filename in NOTICES:
                expected = package / NOTICES[item.filename]
                require(item.file_size == expected.stat().st_size and item.file_size <= 1_000_000
                        and archive.read(item) == expected.read_bytes(), 'Checkpoint notice or provenance differs')
        item = archive.getinfo('braven-large-self.pth')
        require(item.file_size == manifest['checkpoint_bytes'], 'Checkpoint ZIP member byte count differs')
        checkpoint = work / item.filename
        with archive.open(item) as source, checkpoint.open('xb') as target:
            shutil.copyfileobj(source, target, length=1_048_576)
    require(checkpoint.stat().st_size == manifest['checkpoint_bytes']
            and file_sha256(checkpoint) == manifest['checkpoint_sha256'], 'Checkpoint bytes differ from the verified app manifest')
    return checkpoint


INSTALL_FIXTURE = r'''import CryptoKit
import Foundation
import XCTest
@testable import VoiceInkLip

final class VerifiedCheckpointCacheInstall: XCTestCase {
    func testInstallVerifiedPublisherCheckpoint() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["GITHUB_ACTIONS"] == "true", env["RUNNER_ENVIRONMENT"] == "github-hosted",
              env["RUNNER_OS"] == "macOS", env["GITHUB_REPOSITORY"] == "negentropi/roma-just-talk",
              let configPath = env["RJT_MODEL_CACHE_CONFIG"] else { throw CocoaError(.fileReadNoPermission) }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        let directory = URL(fileURLWithPath: config.directory)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        let resources = URL(fileURLWithPath: config.resources)
        let manifestData = try Data(contentsOf: resources.appendingPathComponent("manifest.json"))
        let identity = SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined()
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        let storageCount = (manifest["storages"] as! [String: Any]).count
        let checkpoint = URL(fileURLWithPath: config.checkpoint)
        let store = LipModelStore(directory: directory, resources: resources) { _, destination in
            try FileManager.default.copyItem(at: checkpoint, to: destination)
        }
        let installed = try await store.install()
        let ready = await store.isInstalled()
        let verified = try await store.modelURL()
        let completion = try String(contentsOf: installed.deletingLastPathComponent().appendingPathComponent("complete"), encoding: .utf8)
        let files = try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().appendingPathComponent("storages").path)
        let passed = ready && installed == verified && completion == identity && files.count == storageCount && storageCount == 658
        XCTAssertTrue(passed)
        let receipt: [String: Any] = ["passed": passed, "nativeInstaller": "unchanged LipModelStore.install",
            "modelPath": installed.path, "completionIdentity": completion, "storageFileCount": files.count,
            "nativeFullVerificationPassed": installed == verified, "freshDownloadAssessed": false]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: config.receipt), options: .atomic)
    }
    private struct Configuration: Decodable { let directory, resources, checkpoint, receipt: String }
}
'''


def prepare_cached_model(root, evidence, verified_app, requested, run_command):
    require(verified_app is not None, 'Cached model requires an independently verified app build')
    require(requested == CACHE_RUN, 'Cache run is not the pinned checkpoint producer')
    work = Path(os.environ['RUNNER_TEMP']).resolve() / 'lip-model-cache-work'
    require(not work.exists() and not work.is_relative_to(evidence.resolve()) and not evidence.resolve().is_relative_to(work),
            'Large checkpoint work must be fresh and outside uploaded evidence')
    work.mkdir(mode=0o700)
    receipt = {'status': 'blocked', 'cacheRun': requested, 'cacheHead': CACHE_HEAD,
               'freshDownloadAssessed': False, 'currentFreshSetupAssessed': False,
               'publisherFailures': [
                   {'run': 41171479909, 'head': '9a544dd83de0554375a78966eb3ef785fb15e70c', 'request': 'no Range',
                    'httpStatus': 200, 'contentType': 'text/html', 'bytes': 2040,
                    'sha256': '6c0122867fe7a998536ac2199975cef22c7da1e3a6fe173c35638b5d9f822c9b'},
                   {'run': 41172002726, 'head': '190a31c742908b273143944e67e451024d33cbd6', 'request': 'full-object Range',
                    'httpStatus': 200, 'contentType': 'text/html', 'bytes': 2040,
                    'sha256': '96cf136ced6abd811c5c67bfa34a13939e1093aa170a1534472b6b08ce1e7742'}],
               'boundary': 'CI-only verified checkpoint transport through the unchanged native installer. No product URL, library, or completion receipt is patched.'}
    try:
        receipt['appBuild'] = {key: verified_app.provenance.get(key) for key in
                               ('buildOrigin', 'appBuildHead', 'proofHead', 'transportHead', 'executableSHA256', 'wholeBundleFingerprintSHA256')}
        receipt['priorSetup'] = prior_setup(work, evidence, verified_app.provenance)
        resources, manifest, receipt['appResourceHashes'] = app_resources(root, verified_app.app_path)
        cache_run = api(f'repos/{REPOSITORY}/actions/runs/{requested}')
        jobs = api(f'repos/{REPOSITORY}/actions/runs/{requested}/attempts/1/jobs?per_page=100')
        validate_cache_run(cache_run, jobs, requested)
        source = api(f'repos/{REPOSITORY}/contents/{CACHE_WORKFLOW}?ref={CACHE_HEAD}')
        workflow = base64.b64decode(source['content'])
        require(hashlib.sha256(workflow).hexdigest() == CACHE_WORKFLOW_SHA256, 'Cache upload workflow bytes differ')
        write(evidence / 'model-cache-producer.json', {'run': cache_run, 'jobs': jobs, 'workflowSHA256': CACHE_WORKFLOW_SHA256})
        listing = api(f'repos/{REPOSITORY}/actions/runs/{requested}/artifacts?per_page=100')
        artifact = select_artifact(listing, CACHE_NAME, CACHE_RUN, CACHE_HEAD)
        require(listing['total_count'] == 1, 'Checkpoint producer has extra artifacts')
        validate_cache_artifact(artifact)
        receipt['artifact'] = artifact
        archive = work / 'checkpoint-artifact.zip'
        download(artifact, archive)
        checkpoint = extract_checkpoint(archive, work, root / 'VoiceInkLip', manifest)
        receipt.update(wholeArchiveDigestVerified=True, checkpointBytes=checkpoint.stat().st_size,
                       checkpointSHA256=manifest['checkpoint_sha256'])
        package = work / 'VoiceInkLip'
        paths = command(['git', 'ls-files', '-z', 'VoiceInkLip'], root).decode().split('\0')[:-1]
        hashes = []
        for name in paths:
            source = root / name
            require(source.is_file() and not source.is_symlink(), 'Unexpected native package source type')
            target = package / source.relative_to(root / 'VoiceInkLip')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            require(file_sha256(source) == file_sha256(target), 'Native installer source copy differs')
            hashes.append({'path': name, 'sha256': file_sha256(source)})
        fixture = package / 'Tests/VoiceInkLipTests/VerifiedCheckpointCacheInstall.swift'
        fixture.write_text(INSTALL_FIXTURE)
        (evidence / 'model-cache-install-fixture.swift').write_text(INSTALL_FIXTURE)
        write(evidence / 'model-cache-native-source.json', {'unchangedPackageFiles': hashes,
              'fixtureSHA256': file_sha256(fixture), 'swiftVersion': command(['swift', '--version']).decode().strip(),
              'host': command(['sw_vers']).decode().strip(), 'proofHead': verified_app.provenance['proofHead'],
              'environment': {key: os.environ.get(key) for key in ('GITHUB_ACTIONS', 'RUNNER_ENVIRONMENT', 'RUNNER_OS', 'RUNNER_ARCH')}})
        directory = Path.home() / 'Library/Application Support' / 'com.negentropi.RomaJustTalk/WhisperModels/LipReading'
        require(not directory.exists(), 'Fresh cached model destination already exists')
        config = work / 'install-config.json'
        native_receipt = evidence / 'model-cache-native-install.json'
        write(config, {'directory': str(directory), 'resources': str(resources), 'checkpoint': str(checkpoint), 'receipt': str(native_receipt)})
        run_command('install-verified-cached-model', ['/usr/bin/env', 'RJT_MODEL_CACHE_CONFIG=' + str(config), 'swift', 'test',
                    '--package-path', package, '--scratch-path', work / 'native-build',
                    '--filter', 'VerifiedCheckpointCacheInstall/testInstallVerifiedPublisherCheckpoint'], timeout=1200)
        require(all(file_sha256(package / Path(record['path']).relative_to('VoiceInkLip')) == record['sha256'] for record in hashes),
                'Native package sources changed during installation')
        resolved = package / 'Package.resolved'
        require(resolved.is_file(), 'Native installer dependency resolution receipt is missing')
        shutil.copyfile(resolved, evidence / 'model-cache-native.Package.resolved')
        native = json.loads(native_receipt.read_text())
        require(native.get('passed') is True and native.get('nativeFullVerificationPassed') is True
                and native.get('storageFileCount') == 658, 'Native cached checkpoint installation did not pass')
        receipt.update(status='verified', nativeInstall=native)
        return receipt
    finally:
        write(evidence / 'model-cache.json', receipt)
