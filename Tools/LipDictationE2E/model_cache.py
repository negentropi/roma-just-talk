"""One pinned CI checkpoint transport; unchanged native installer owns publication."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import zipfile

from app_artifact import REPOSITORY, REPOSITORY_ID, api, command, download, file_sha256, members, require, select_artifact


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


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


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


def validate_prior_setup(setup, summary, app):
    require(app.get('status') == 'verified' and app.get('producerRun') == SETUP_RUN and app.get('appBuildHead') == APP_HEAD
            and app.get('executableSHA256') == APP_EXECUTABLE, 'Prior Setup does not belong to this immutable app')
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
    validate_prior_setup(reports['setup.json'], reports['summary.json'], app)
    return {'run': SETUP_RUN, 'artifactID': artifact['id'], 'archiveSHA256': artifact['digest'],
            'wholeArchiveDigestVerified': True, 'actualSetupButtonPressed': True,
            'appBuildHead': APP_HEAD, 'executableSHA256': APP_EXECUTABLE,
            'boundary': 'Prior real Set Up/download success for the same executable; not current fresh Setup.'}


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
    require(verified_app is not None, 'Cached model requires an independently verified immutable app')
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
