import copy
import hashlib
import io
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


class ArtifactTests(unittest.TestCase):
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
