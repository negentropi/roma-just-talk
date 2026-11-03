import copy
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import app_artifact as artifact


BUILD = '1' * 40
RUN = 41161053977


def producer():
    run = {'id': RUN, 'head_sha': BUILD, 'run_attempt': 1, 'event': 'push', 'status': 'completed', 'conclusion': 'failure',
           'name': 'Verify lip dictation app on macOS', 'head_branch': 'ci/lip-dictation-app-proof',
           'path': '.github/workflows/lip-dictation-app.yml',
           'repository': {'id': 1253985786, 'full_name': 'negentropi/roma-just-talk'},
           'head_repository': {'id': 1253985786, 'full_name': 'negentropi/roma-just-talk'}}
    names = ['Select Xcode and toolchain', 'Verify runtime harness core checks',
             'Compile and load the actual runtime proof helper', 'Prepare static Whisper', 'Install BlackHole input',
             'Prove text-only Power Mode isolation and all shared core checks', 'Build release app', 'Debug unit tests',
             'Prove microphone, paste, auto-send, Power Mode, and permission regressions', 'Package app',
             'Run actions/upload-artifact@v4', 'Run actions/upload-artifact@v4', 'Run actions/upload-artifact@v4']
    steps = [{'name': name, 'conclusion': 'success'} for name in names]
    steps.append({'name': 'Verify real voice and lip dictation through the app shortcut', 'conclusion': 'failure'})
    return run, {'total_count': 1, 'jobs': [{'name': 'verify', 'run_id': RUN, 'run_attempt': 1,
                                         'status': 'completed', 'conclusion': 'failure', 'steps': steps}]}


def listing():
    return {'total_count': 1, 'artifacts': [{'id': 7, 'name': 'roma.just.talk.app', 'expired': False,
            'size_in_bytes': 10, 'digest': 'sha256:' + 'a' * 64,
            'workflow_run': {'id': RUN, 'head_sha': BUILD, 'repository_id': 1253985786, 'head_repository_id': 1253985786}}]}


def zip_bytes(entries):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        for name, data, mode in entries:
            info = zipfile.ZipInfo(name)
            info.external_attr = mode << 16
            archive.writestr(info, data)
    return stream.getvalue()


class Response(io.BytesIO):
    def __init__(self, data, status, headers=None):
        super().__init__(data)
        self.status, self.headers = status, headers or {}


def hosted_producer():
    # Selected actual API fields from run41442208716 and its completed macOS job.
    run = {'id': 41442208716, 'head_sha': 'b998507d0595d2d05256ef19c3223279e0e69479', 'run_attempt': 1,
           'path': '.github/workflows/lip-pr-hosted-gates.yml', 'workflow_id': 402555449,
           'name': 'Run standard lip PR gates on isolated hosted Macs',
           'head_branch': 'ci/lip-pr-hosted-gates-20261102-b998507d0595',
           'event': 'push', 'status': 'completed', 'conclusion': 'failure',
           'repository': {'id': 1253985786, 'full_name': 'negentropi/roma-just-talk', 'fork': False},
           'head_repository': {'id': 1253985786, 'full_name': 'negentropi/roma-just-talk', 'fork': False},
           'actor': {'id': 171460575, 'login': 'negentropi'},
           'triggering_actor': {'id': 171460575, 'login': 'negentropi'}}
    names = '''Set up job
Checkout the exact PR source
Require an isolated hosted Mac and record the toolchain
Compile and verify autonomous runtime E2E harness
Verify Sonoma-compatible helper
Package runtime E2E helper
Upload runtime E2E helper
Keep disposable test desktop awake
Show Xcode version
Compile visible text latency harness helper
Verify latency helper run target
Verify ad-hoc Library Validation packaging contract
Verify distribution launch evidence contract
Build release app
Verify FluidAudio array reset semantics
Upload FluidAudio test evidence
Verify local bilingual model package
Prove recording cache cleanup regression red and green
Upload recording cache regression evidence
Prove text-only Power Mode isolation and all shared core checks
Install BlackHole input
Run Debug unit tests
Upload Debug test evidence
Prove microphone, paste, auto-send, Power Mode, and permission regressions
Upload Core and semantic-control proof receipts
Reject debug-only release payload
Verify packaged app identity
Reject test-coverage instrumentation in release app
Package app
Upload app artifact
Relocate only the three uploaded standard outputs
Archive the verified generated Qwen package lock
Verify current real voice and lip dictation
Upload actual same-job dictation and cache receipts
Record tested source and external build inputs
Upload hosted execution provenance
Post Checkout the exact PR source
Complete job'''.splitlines()
    job = {'id': 125266577339, 'run_id': 41442208716, 'run_attempt': 1,
           'head_sha': run['head_sha'], 'name': 'Run complete standard macOS gates',
           'labels': ['macos-26'], 'runner_group_name': 'GitHub Actions',
           'status': 'completed', 'conclusion': 'failure', 'steps': [
               {'name': name, 'status': 'completed',
                'conclusion': 'failure' if name == 'Verify current real voice and lip dictation' else 'success'}
               for name in names]}
    return run, {'total_count': 1, 'jobs': [job]}


class ArtifactTests(unittest.TestCase):
    def test_actual_hosted_metadata_needs_its_own_exact_producer_contract(self):
        run, jobs = hosted_producer()
        with self.assertRaises(artifact.ArtifactError):
            artifact.validate_run(run, jobs, 41442208716, artifact.HOSTED_BUILD)
        binding = artifact.producer_binding(run, jobs, 41442208716, artifact.HOSTED_BUILD)
        self.assertEqual(binding.profile, 'pinnedHostedWorkflow')
        self.assertEqual(binding.app_build_head, artifact.HOSTED_BUILD)
        self.assertEqual(binding.transport_head, run['head_sha'])
        old_run, old_jobs = producer()
        self.assertEqual(artifact.producer_binding(old_run, old_jobs, RUN, BUILD).profile, 'legacyAppWorkflow')
        with self.assertRaises(artifact.ArtifactError):
            artifact.producer_binding(dict(old_run, head_sha=artifact.HOSTED_TRANSPORT), old_jobs, RUN, BUILD)

    def test_hosted_wrong_run_source_actor_and_workflow_are_refused(self):
        run, jobs = hosted_producer()
        for field, value in [('id', 1), ('head_sha', artifact.HOSTED_BUILD), ('run_attempt', 2),
                             ('workflow_id', 1), ('path', '.github/workflows/unknown.yml'),
                             ('name', 'Other workflow'), ('head_branch', 'ci/lip-pr-hosted-gates-other'),
                             ('event', 'workflow_dispatch'), ('status', 'in_progress'), ('conclusion', 'success'),
                             ('actor', {'id': 1, 'login': 'negentropi'}),
                             ('triggering_actor', {'id': 171460575, 'login': 'someone'}),
                             ('head_repository', dict(run['head_repository'], fork=True))]:
            with self.subTest(field=field), self.assertRaises(artifact.ArtifactError):
                artifact.producer_binding(dict(run, **{field: value}), jobs, 41442208716, artifact.HOSTED_BUILD)
        for requested, source in [(1, artifact.HOSTED_BUILD), (41442208716, artifact.HOSTED_TRANSPORT)]:
            with self.assertRaises(artifact.ArtifactError):
                artifact.producer_binding(run, jobs, requested, source)

    def test_every_hosted_non_e2e_step_and_exact_job_must_pass(self):
        run, jobs = hosted_producer()
        for index, step in enumerate(jobs['jobs'][0]['steps']):
            for outcome in ('skipped', 'cancelled', 'failure' if step['conclusion'] == 'success' else 'success'):
                changed = copy.deepcopy(jobs)
                changed['jobs'][0]['steps'][index]['conclusion'] = outcome
                with self.subTest(name=step['name'], outcome=outcome), self.assertRaises(artifact.ArtifactError):
                    artifact.producer_binding(run, changed, 41442208716, artifact.HOSTED_BUILD)
        for change in ('duplicate-job', 'missing-step', 'reordered-step', 'job-id', 'labels', 'job-head'):
            changed = copy.deepcopy(jobs)
            job = changed['jobs'][0]
            if change == 'duplicate-job':
                changed['jobs'] *= 2; changed['total_count'] = 2
            elif change == 'missing-step':
                job['steps'].pop(1)
            elif change == 'reordered-step':
                job['steps'][1:3] = reversed(job['steps'][1:3])
            elif change == 'job-id':
                job['id'] += 1
            elif change == 'labels':
                job['labels'] = ['self-hosted']
            else:
                job['head_sha'] = artifact.HOSTED_BUILD
            with self.subTest(change=change), self.assertRaises(artifact.ArtifactError):
                artifact.producer_binding(run, changed, 41442208716, artifact.HOSTED_BUILD)

    def test_hosted_artifacts_bind_to_transport_and_complete_archive_pins(self):
        items = []
        for _, name, identifier, size, digest in artifact.HOSTED_ARTIFACTS:
            items.append({'id': identifier, 'name': name, 'expired': False, 'size_in_bytes': size,
                          'digest': 'sha256:' + digest, 'workflow_run': {
                              'id': 41442208716, 'head_sha': artifact.HOSTED_TRANSPORT,
                              'repository_id': 1253985786, 'head_repository_id': 1253985786}})
        listing = {'total_count': 3, 'artifacts': items}
        self.assertEqual(set(artifact.select_hosted_artifacts(listing)), {'app', 'runtime', 'execution'})
        for index in range(3):
            for field, value in [('id', 1), ('name', 'different'), ('size_in_bytes', 1),
                                 ('digest', 'sha256:' + '0' * 64), ('expired', True),
                                 ('workflow_run', dict(items[index]['workflow_run'], head_sha=artifact.HOSTED_BUILD))]:
                changed = copy.deepcopy(listing)
                changed['artifacts'][index][field] = value
                with self.subTest(index=index, field=field), self.assertRaises(artifact.ArtifactError):
                    artifact.select_hosted_artifacts(changed)

    def test_whole_hosted_workflow_pin_rejects_unrelated_shell_changes(self):
        from test_model_cache import workflow
        raw = workflow(artifact.HOSTED_BUILD)
        artifact.validate_same_job_workflow(raw, artifact.HOSTED_BUILD)
        for changed in (raw, raw + b'\n# An unrelated workflow edit\n'):
            with self.assertRaises(artifact.ArtifactError):
                artifact.validate_hosted_workflow(changed, artifact.HOSTED_WORKFLOW_BLOB)

    def test_hosted_transport_rejects_additional_product_or_wrapper_changes(self):
        for diff in [b'M\0VoiceInk/Engine.swift\0',
                     ('A\0' + artifact.SAME_JOB_WORKFLOW + '\0M\0Makefile\0').encode(),
                     ('M\0' + artifact.SAME_JOB_WORKFLOW + '\0').encode()]:
            with patch.object(artifact.subprocess, 'run', return_value=unittest.mock.Mock(returncode=0)), \
                    patch.object(artifact, 'command', side_effect=[b'', diff]), self.assertRaises(artifact.ArtifactError):
                artifact.check_hosted_transport(Path('/fixture'))

    def test_hosted_evidence_extraction_refuses_unsafe_or_non_receipt_members(self):
        for name, mode, accepted in [('nested/provenance.json', stat.S_IFREG, True),
                                     ('../outside.json', stat.S_IFREG, False),
                                     ('link.json', stat.S_IFLNK, False), ('model.pth', stat.S_IFREG, False)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                archive = Path(temporary) / 'proof.zip'
                archive.write_bytes(zip_bytes([(name, b'{}', mode)]))
                destination = Path(temporary) / 'evidence'
                if accepted:
                    artifact.extract_hosted_receipts(archive, destination)
                    self.assertEqual((destination / name).read_bytes(), b'{}')
                else:
                    with self.assertRaises(artifact.ArtifactError):
                        artifact.extract_hosted_receipts(archive, destination)

    def test_hosted_receipts_require_current_locks_and_restored_producer_integrity(self):
        locks = {name: ('actual bytes of ' + name).encode() for name in artifact.HOSTED_LOCKS}
        hashes = {name: hashlib.sha256(value).hexdigest() for name, value in locks.items()}
        workflow = {'workflowSHA256': artifact.HOSTED_WORKFLOW_SHA256, 'macosBlockSHA256': 'a' * 64,
                    'macProjectBuild': {'dependencyLock': artifact.LOCK}}
        runtime_receipt = {'appBuildHead': artifact.HOSTED_BUILD, 'proofHead': artifact.HOSTED_BUILD,
                           'checkoutSourceHead': artifact.HOSTED_BUILD, 'transportHead': artifact.HOSTED_TRANSPORT,
                           'runID': 41442208716, 'jobID': 125266577339, 'status': 'verified',
                           'sameJobSourcesUnchanged': True, 'appArtifactUnchanged': True,
                           **workflow, 'actualDependencyLockSHA256': hashes[artifact.LOCK]}
        execution_receipt = {'testedSourceHead': artifact.HOSTED_BUILD, 'transportHead': artifact.HOSTED_TRANSPORT,
                             'transportRef': 'refs/heads/' + artifact.HOSTED_REF, 'runID': '41442208716',
                             'runAttempt': '1', 'job': 'macos', 'dependencyLockSHA256': hashes}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, execution = root / 'runtime', root / 'execution'
            runtime.mkdir(); execution.mkdir()
            (runtime / 'actual.Package.resolved').write_bytes(locks[artifact.LOCK])

            def check(r, e):
                (runtime / 'provenance.json').write_text(json.dumps(r))
                (execution / 'provenance.json').write_text(json.dumps(e))
                with patch.object(artifact, 'command', side_effect=lambda args, _: locks[args[2].split(':', 1)[1]]):
                    return artifact.validate_hosted_receipts(root, 'c' * 40, runtime, execution,
                                                            locks[artifact.LOCK], workflow)

            producer, receipt = check(runtime_receipt, execution_receipt)
            self.assertEqual(producer, runtime_receipt)
            self.assertEqual(receipt['trackedLockSHA256'], hashes)
            self.assertNotIn('setup', receipt)
            for field, value in [('appBuildHead', artifact.HOSTED_TRANSPORT), ('transportHead', artifact.HOSTED_BUILD),
                                 ('workflowSHA256', '0' * 64), ('runID', 1), ('jobID', 1), ('status', 'blocked'),
                                 ('sameJobSourcesUnchanged', False), ('appArtifactUnchanged', False),
                                 ('actualDependencyLockSHA256', '0' * 64)]:
                with self.subTest(field=field), self.assertRaises(artifact.ArtifactError):
                    check(dict(runtime_receipt, **{field: value}), execution_receipt)
            for field, value in [('testedSourceHead', 'c' * 40), ('runAttempt', '2'),
                                 ('dependencyLockSHA256', {**hashes, artifact.HOSTED_LOCKS[-1]: '0' * 64})]:
                with self.subTest(field=field), self.assertRaises(artifact.ArtifactError):
                    check(runtime_receipt, dict(execution_receipt, **{field: value}))
            (runtime / 'actual.Package.resolved').write_bytes(b'changed producer lock')
            with self.assertRaises(artifact.ArtifactError):
                check(runtime_receipt, execution_receipt)

    def test_hosted_bundle_must_equal_both_native_producer_snapshots(self):
        records = [{'path': str(index), 'mode': 0o755, 'directory': True} for index in range(401)]
        fingerprint = hashlib.sha256(json.dumps(records, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        resources = [{'path': 'manifest.json', 'sha256': 'a' * 64}]
        producer = {'wholeBundleFingerprintSHA256': fingerprint, 'postRunBundleFingerprintSHA256': fingerprint,
                    'executableSHA256': artifact.HOSTED_EXECUTABLE_SHA256,
                    'postRunExecutableSHA256': artifact.HOSTED_EXECUTABLE_SHA256,
                    'appResourceHashes': resources, 'postRunAppResourceHashes': resources}
        with tempfile.TemporaryDirectory() as temporary, patch.object(artifact, 'HOSTED_BUNDLE_SHA256', fingerprint):
            root = Path(temporary)
            for name in ('bundle-before.json', 'bundle-after.json'):
                (root / name).write_text(json.dumps(records))
            artifact.validate_hosted_bundle(producer, fingerprint, records, artifact.HOSTED_EXECUTABLE_SHA256, resources, root)
            for field, value in [('postRunBundleFingerprintSHA256', '0' * 64),
                                 ('postRunExecutableSHA256', '0' * 64), ('postRunAppResourceHashes', [])]:
                with self.subTest(field=field), self.assertRaises(artifact.ArtifactError):
                    artifact.validate_hosted_bundle(dict(producer, **{field: value}), fingerprint, records,
                                                    artifact.HOSTED_EXECUTABLE_SHA256, resources, root)
            (root / 'bundle-after.json').write_text(json.dumps(records[:-1]))
            with self.assertRaises(artifact.ArtifactError):
                artifact.validate_hosted_bundle(producer, fingerprint, records, artifact.HOSTED_EXECUTABLE_SHA256, resources, root)

    def test_only_visual_producer_failure_can_be_replaced(self):
        run, jobs = producer()
        artifact.validate_run(run, jobs, RUN, BUILD)
        for name in ['Build release app', 'Debug unit tests', 'Prove microphone, paste, auto-send, Power Mode, and permission regressions']:
            changed = copy.deepcopy(jobs)
            next(step for step in changed['jobs'][0]['steps'] if step['name'] == name)['conclusion'] = 'failure'
            with self.subTest(name=name), self.assertRaises(artifact.ArtifactError):
                artifact.validate_run(run, changed, RUN, BUILD)
        changed = copy.deepcopy(jobs)
        changed['jobs'][0]['steps'].append({'name': 'Post checkout', 'conclusion': 'failure'})
        with self.assertRaises(artifact.ArtifactError):
            artifact.validate_run(run, changed, RUN, BUILD)

    def test_pending_fork_different_workflow_and_rerun_are_rejected(self):
        run, jobs = producer()
        changes = [('status', 'in_progress'), ('run_attempt', 2), ('path', '.github/workflows/another.yml'),
                   ('head_sha', '2' * 40), ('head_repository', {'id': 99, 'full_name': 'someone/roma-just-talk'})]
        for key, value in changes:
            changed = dict(run, **{key: value})
            with self.subTest(key=key), self.assertRaises(artifact.ArtifactError):
                artifact.validate_run(changed, jobs, RUN, BUILD)

    def test_duplicate_jobs_and_skipped_upload_are_rejected(self):
        run, jobs = producer()
        duplicate = copy.deepcopy(jobs)
        duplicate['jobs'] *= 2
        duplicate['total_count'] = 2
        with self.assertRaises(artifact.ArtifactError):
            artifact.validate_run(run, duplicate, RUN, BUILD)
        jobs['jobs'][0]['steps'][-2]['conclusion'] = 'skipped'
        with self.assertRaises(artifact.ArtifactError):
            artifact.validate_run(run, jobs, RUN, BUILD)

    def test_artifact_identity_digest_expiry_and_ambiguity(self):
        valid = listing()
        self.assertEqual(artifact.select_artifact(valid, 'roma.just.talk.app', RUN, BUILD)['id'], 7)
        for key, value in [('expired', True), ('digest', None), ('size_in_bytes', 0), ('workflow_run', {'id': 8})]:
            changed = copy.deepcopy(valid)
            changed['artifacts'][0][key] = value
            with self.subTest(key=key), self.assertRaises(artifact.ArtifactError):
                artifact.select_artifact(changed, 'roma.just.talk.app', RUN, BUILD)
        valid['artifacts'] *= 2
        valid['total_count'] = 2
        with self.assertRaises(artifact.ArtifactError):
            artifact.select_artifact(valid, 'roma.just.talk.app', RUN, BUILD)

    def test_only_exact_proof_paths_can_differ(self):
        self.assertEqual(artifact.check_changed_paths(b'Tools/LipDictationE2E/VisualCases.swift\0'), ['Tools/LipDictationE2E/VisualCases.swift'])
        self.assertEqual(artifact.check_changed_paths(b'Tools/LipCameraProbe/run.py\0'), ['Tools/LipCameraProbe/run.py'])
        for path in ['VoiceInk/Recorder.swift', 'VoiceInkLip/Package.swift', 'Makefile', 'LocalBuild.xcconfig',
                     'VoiceInkTests/RecordingRecognitionTests.swift', '.github/workflows/lip-dictation-app.yml',
                     'Tools/LipDictationE2E/other.py', 'Tools/LipDictationE2E/../VoiceInk/Recorder.swift']:
            with self.subTest(path=path), self.assertRaises(artifact.ArtifactError):
                artifact.check_changed_paths((path + '\0').encode())

    def test_local_host_is_rejected_before_writing_or_reading_credentials(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            destination = Path(temporary) / 'source' / 'roma just talk.app'
            with self.assertRaises(artifact.ArtifactError):
                artifact.prepare_verified_app(Path(temporary), Path(temporary) / 'evidence', destination, RUN, BUILD, '2' * 40)
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_range_requires_206_exact_bounds_and_sends_no_authorization(self):
        requests = []
        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                return Response(b'cdefg', 206, {'Content-Range': 'bytes 2-6/10'})
        reader = artifact.RangeReader('https://example.invalid/artifact', 10)
        reader.seek(2)
        with patch.object(artifact.urllib.request, 'build_opener', return_value=Opener()):
            self.assertEqual(reader.read(5), b'cdefg')
        self.assertEqual(reader.bytes_read, 5)
        self.assertNotIn('Authorization', requests[0].headers)
        for status, header in [(200, 'bytes 2-6/10'), (206, 'bytes 0-4/10')]:
            opener = unittest.mock.Mock()
            opener.open.return_value = Response(b'cdefg', status, {'Content-Range': header})
            reader = artifact.RangeReader('https://example.invalid/artifact', 10)
            reader.seek(2)
            with patch.object(artifact.urllib.request, 'build_opener', return_value=opener), self.assertRaises(artifact.ArtifactError):
                reader.read(5)

    def test_lock_range_reads_require_exact_bytes_and_unique_member(self):
        expected = b'{"pins":["immutable"]}\n'
        lock = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        for entries, accepted in [([(lock, expected, stat.S_IFREG)], True),
                                  ([(lock, b'changed', stat.S_IFREG)], False),
                                  ([(lock, expected, stat.S_IFLNK)], False),
                                  ([(lock, expected, stat.S_IFREG), ('other/' + lock, expected, stat.S_IFREG)], False)]:
            reader = io.BytesIO(zip_bytes(entries))
            reader.bytes_read = 0
            with patch.object(artifact, 'artifact_url', return_value='https://example.invalid/artifact'), patch.object(artifact, 'RangeReader', return_value=reader):
                if accepted:
                    data, receipt = artifact.archived_lock({'id': 7, 'size_in_bytes': 100}, expected)
                    self.assertEqual(data, expected)
                    self.assertFalse(receipt['wholeEvidenceArchiveDigestVerified'])
                else:
                    with self.assertRaises(artifact.ArtifactError):
                        artifact.archived_lock({'id': 7, 'size_in_bytes': 100}, expected)

    def test_download_verifies_full_outer_digest(self):
        body = b'immutable artifact bytes'
        metadata = {'id': 7, 'size_in_bytes': len(body), 'digest': 'sha256:' + hashlib.sha256(body).hexdigest()}
        for valid in [True, False]:
            with tempfile.TemporaryDirectory() as temporary:
                opener = unittest.mock.Mock()
                opener.open.return_value = Response(body, 200)
                received = metadata if valid else dict(metadata, digest='sha256:' + '0' * 64)
                with patch.object(artifact, 'artifact_url', return_value='https://example.invalid/artifact'), patch.object(artifact.urllib.request, 'build_opener', return_value=opener):
                    if valid:
                        artifact.download(received, Path(temporary) / 'artifact.zip')
                    else:
                        with self.assertRaises(artifact.ArtifactError):
                            artifact.download(received, Path(temporary) / 'artifact.zip')

    def test_app_archive_preserves_safe_framework_links(self):
        prefix = 'roma just talk.app/Contents/'
        entries = [(prefix + 'Info.plist', b'identity', stat.S_IFREG),
                   (prefix + 'Frameworks/F.framework/Versions/A/F', b'binary', stat.S_IFREG),
                   (prefix + 'Frameworks/F.framework/Versions/Current', b'A', stat.S_IFLNK),
                   (prefix + 'Frameworks/F.framework/F', b'Versions/Current/F', stat.S_IFLNK)]
        with zipfile.ZipFile(io.BytesIO(zip_bytes(entries))) as archive:
            artifact.validate_app_archive(archive)
        for addition in [('roma just talk.app/../../outside', b'bad', stat.S_IFREG),
                         (prefix + 'outside', b'/tmp/outside', stat.S_IFLNK),
                         (prefix + 'outside', b'../../../outside', stat.S_IFLNK),
                         (prefix + 'Frameworks/F.framework/Versions/Current/child', b'bad', stat.S_IFREG)]:
            with zipfile.ZipFile(io.BytesIO(zip_bytes(entries + [addition]))) as archive, self.assertRaises(artifact.ArtifactError):
                artifact.validate_app_archive(archive)
        cycle = entries + [(prefix + 'A', b'B', stat.S_IFLNK), (prefix + 'B', b'A', stat.S_IFLNK)]
        with zipfile.ZipFile(io.BytesIO(zip_bytes(cycle))) as archive, self.assertRaises(artifact.ArtifactError):
            artifact.validate_app_archive(archive)

    def test_bundle_fingerprint_detects_bytes_modes_and_link_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            app, evidence = Path(temporary) / 'app', Path(temporary) / 'evidence'
            app.mkdir(); evidence.mkdir()
            payload = app / 'binary'
            payload.write_bytes(b'original')
            original, _ = artifact.bundle_fingerprint(app)
            verified = artifact.VerifiedApp(app, {}, original, evidence)
            with patch.object(artifact, 'command') as call:
                verified.verify_unchanged()
                call.assert_called_once_with(['codesign', '--verify', '--deep', '--strict', app])
            self.assertTrue(verified.provenance['appArtifactUnchanged'])
            payload.write_bytes(b'altered')
            with self.assertRaises(artifact.ArtifactError):
                verified.verify_unchanged()
            self.assertFalse(verified.provenance['appArtifactUnchanged'])
            payload.write_bytes(b'original')
            payload.chmod(0o755)
            self.assertNotEqual(artifact.bundle_fingerprint(app)[0], original)
            (app / 'outside').symlink_to(Path(temporary) / 'elsewhere')
            with self.assertRaises(artifact.ArtifactError):
                artifact.bundle_fingerprint(app)

    def test_post_run_signature_failure_never_records_unchanged_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            app, evidence = Path(temporary) / 'app', Path(temporary) / 'evidence'
            app.mkdir(); evidence.mkdir()
            (app / 'binary').write_bytes(b'original')
            fingerprint, _ = artifact.bundle_fingerprint(app)
            verified = artifact.VerifiedApp(app, {}, fingerprint, evidence)
            with patch.object(artifact, 'command', side_effect=artifact.ArtifactError('Signature rejected')), self.assertRaises(artifact.ArtifactError):
                verified.verify_unchanged()
            self.assertFalse(verified.provenance['appArtifactUnchanged'])


if __name__ == '__main__':
    unittest.main()
