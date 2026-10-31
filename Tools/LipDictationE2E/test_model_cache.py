import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from app_artifact import ArtifactError, REPOSITORY, REPOSITORY_ID
import model_cache as cache


class ModelCacheTests(unittest.TestCase):
    def test_wrong_cache_run_head_workflow_and_upload_are_refused(self):
        run = {'id': cache.CACHE_RUN, 'head_sha': cache.CACHE_HEAD, 'run_attempt': 1, 'workflow_id': 402499348,
               'path': cache.CACHE_WORKFLOW, 'name': 'Transport verified publisher checkpoint for one CI replay',
               'head_branch': cache.CACHE_BRANCH, 'event': 'push', 'status': 'completed', 'conclusion': 'success',
               'repository': {'id': REPOSITORY_ID, 'full_name': REPOSITORY},
               'head_repository': {'id': REPOSITORY_ID, 'full_name': REPOSITORY}}
        jobs = {'total_count': 1, 'jobs': [{'id': 124454201080, 'name': 'upload', 'run_id': cache.CACHE_RUN,
                'run_attempt': 1, 'status': 'completed', 'conclusion': 'success',
                'labels': [cache.CACHE_BRANCH.removeprefix('ci/')], 'steps': [
                    {'name': name, 'conclusion': 'success'} for name in (
                        'Verify exact job and original publisher bytes',
                        'Upload one-day repository-scoped checkpoint artifact', 'Record artifact receipt')]}]}
        cache.validate_cache_run(run, jobs, cache.CACHE_RUN)
        for field, value in [('head_sha', 'f' * 40), ('path', '.github/workflows/other.yml'),
                             ('run_attempt', 2), ('head_repository', {'id': 99, 'full_name': REPOSITORY})]:
            with self.subTest(field=field), self.assertRaises(ArtifactError):
                cache.validate_cache_run(dict(run, **{field: value}), jobs, cache.CACHE_RUN)
        with self.assertRaises(ArtifactError):
            cache.validate_cache_run(run, jobs, cache.CACHE_RUN + 1)
        changed = copy.deepcopy(jobs)
        changed['jobs'][0]['steps'][1]['conclusion'] = 'skipped'
        with self.assertRaises(ArtifactError):
            cache.validate_cache_run(run, changed, cache.CACHE_RUN)
        changed = copy.deepcopy(jobs)
        changed['jobs'][0]['id'] += 1
        with self.assertRaises(ArtifactError):
            cache.validate_cache_run(run, changed, cache.CACHE_RUN)

    def test_different_archive_identity_and_digest_are_refused(self):
        with patch.object(cache, 'CACHE_ARTIFACT_ID', 7), patch.object(cache, 'CACHE_ARTIFACT_DIGEST', 'sha256:' + 'a' * 64):
            good = {'id': 7, 'digest': 'sha256:' + 'a' * 64}
            cache.validate_cache_artifact(good)
            for changed in [dict(good, id=8), dict(good, digest='sha256:' + 'b' * 64)]:
                with self.assertRaises(ArtifactError):
                    cache.validate_cache_artifact(changed)

    def test_changed_checkpoint_bytes_and_notices_are_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / 'package'
            for name in cache.NOTICES.values():
                path = package / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'original notice')
            data = b'original checkpoint'
            manifest = {'checkpoint_bytes': len(data), 'checkpoint_sha256': hashlib.sha256(data).hexdigest()}
            for index, (checkpoint, changed_notice, accepted) in enumerate([
                    (data, False, True), (b'changed! checkpoint', False, False), (data, True, False)]):
                work = root / str(index)
                work.mkdir()
                archive = work / 'artifact.zip'
                with zipfile.ZipFile(archive, 'w') as output:
                    output.writestr('braven-large-self.pth', checkpoint)
                    for name, source in cache.NOTICES.items():
                        output.writestr(name, b'altered notice' if changed_notice else (package / source).read_bytes())
                if accepted:
                    self.assertEqual(cache.extract_checkpoint(archive, work, package, manifest).read_bytes(), data)
                else:
                    with self.assertRaises(ArtifactError):
                        cache.extract_checkpoint(archive, work, package, manifest)

    def test_prior_setup_requires_the_same_executable_and_real_ui_success(self):
        setup = {'scenario': 'setup', 'passed': True, 'actualSetupButtonPressed': True,
                 'actualSetupUIReady': True, 'actualModeControlsChanged': True, 'restored': True}
        summary = {'sourceHead': cache.APP_HEAD, 'declaredAppSourceHead': cache.APP_HEAD,
                   'appBuildHead': cache.APP_HEAD, 'appExecutableSHA256': cache.APP_EXECUTABLE, 'status': 'blocked'}
        app = {'status': 'verified', 'producerRun': cache.SETUP_RUN, 'appBuildHead': cache.APP_HEAD, 'executableSHA256': cache.APP_EXECUTABLE}
        # Overall producer visual failure does not turn its actual successful Setup into a fresh current success.
        cache.validate_prior_setup(setup, summary, app)
        for changed in [dict(app, producerRun=cache.SETUP_RUN + 1), dict(app, executableSHA256='b' * 64)]:
            with self.assertRaises(ArtifactError):
                cache.validate_prior_setup(setup, summary, changed)
        for field in ['passed', 'actualSetupButtonPressed', 'actualSetupUIReady']:
            with self.subTest(field=field), self.assertRaises(ArtifactError):
                cache.validate_prior_setup(dict(setup, **{field: False}), summary, app)
        for field, value in [('appExecutableSHA256', 'b' * 64), ('sourceHead', 'f' * 40)]:
            with self.subTest(field=field), self.assertRaises(ArtifactError):
                cache.validate_prior_setup(setup, dict(summary, **{field: value}), app)


if __name__ == '__main__':
    unittest.main()
