import copy
import contextlib
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import zipfile

from app_artifact import ArtifactError, REPOSITORY, REPOSITORY_ID
import model_cache as cache
import run as runner


def workflow(source):
    return f'''name: Bounded hosted proof
env:
  TESTED_SOURCE_HEAD: {source}
jobs:
  macos:
    name: Run complete standard macOS gates
    runs-on: macos-26
    steps:
    - name: Checkout actual feature source
      uses: actions/checkout@{cache.CHECKOUT_ACTION}
      with:
        ref: {source}
    - name: Build release app
      id: release_app
      run: make local CONFIGURATION=Release
    - name: Verify current real voice and lip dictation
      run: |
        python3 Tools/LipDictationE2E/run.py --same-job-build --app-source-head "$TESTED_SOURCE_HEAD"
  ios:
    steps:
    - uses: actions/checkout@{cache.CHECKOUT_ACTION}
      with:
        ref: {'d' * 40}
'''.encode()


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

    def test_same_job_profile_is_explicit_and_cannot_replace_immutable_provenance(self):
        base = ['--app', '/fixture/app', '--app-source-head', 'a' * 40, '--visual', '--model-cache-run', str(cache.CACHE_RUN)]
        self.assertTrue(runner.parse_arguments(base + ['--same-job-build']).same_job_build)
        old = runner.parse_arguments(base + ['--producer-run', str(cache.SETUP_RUN)])
        self.assertFalse(old.same_job_build)
        for arguments in [base, base + ['--same-job-build', '--producer-run', str(cache.SETUP_RUN)],
                          ['--same-job-build', '--app', '/fixture/app', '--app-source-head', 'a' * 40, '--visual'],
                          ['--same-job-build', '--build-helper-only']]:
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                runner.parse_arguments(arguments)

    def test_same_job_cached_install_does_not_transfer_historical_setup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / 'evidence'
            evidence.mkdir()
            runner_temp = root / 'runner'
            runner_temp.mkdir()
            app = SimpleNamespace(app_path=root / 'app', provenance={
                'status': 'verified', 'buildOrigin': 'sameJobRelease',
                'appBuildHead': 'a' * 40, 'proofHead': 'a' * 40, 'transportHead': 'b' * 40})
            with patch.dict(cache.os.environ, {'RUNNER_TEMP': str(runner_temp)}), \
                    patch.object(cache, 'prior_setup', side_effect=AssertionError('Historical Setup must not transfer')) as prior, \
                    patch.object(cache, 'app_resources', side_effect=RuntimeError('Fixture stops before network')) as resources, \
                    patch.object(cache, 'api') as api:
                with self.assertRaisesRegex(RuntimeError, 'Fixture stops before network'):
                    cache.prepare_cached_model(root, evidence, app, cache.CACHE_RUN, Mock())
                prior.assert_not_called()
                resources.assert_called_once_with(root, app.app_path)
                api.assert_not_called()
            receipt = json.loads((evidence / 'model-cache.json').read_text())
            self.assertNotIn('priorSetup', receipt)
            self.assertEqual(receipt['setupProfile'], 'currentNativeCachedInstall')
            for field in ('historicalSetupUsed', 'actualSetupButtonPressed',
                          'freshDownloadAssessed', 'currentFreshSetupAssessed'):
                self.assertIs(receipt[field], False)

    def test_cached_install_refuses_unverified_same_job_provenance_before_network(self):
        valid = {'status': 'verified', 'buildOrigin': 'sameJobRelease',
                 'appBuildHead': 'a' * 40, 'proofHead': 'a' * 40, 'transportHead': 'b' * 40}
        for field, value in [('status', 'blocked'), ('proofHead', 'c' * 40), ('transportHead', 'main'), ('transportHead', None)]:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                evidence = root / 'evidence'
                evidence.mkdir()
                app = SimpleNamespace(app_path=root / 'app', provenance=dict(valid, **{field: value}))
                with patch.dict(cache.os.environ, {'RUNNER_TEMP': str(root)}), \
                        patch.object(cache, 'prior_setup') as prior, patch.object(cache, 'app_resources') as resources, \
                        patch.object(cache, 'api') as api, self.assertRaises(ArtifactError):
                    cache.prepare_cached_model(root, evidence, app, cache.CACHE_RUN, Mock())
                prior.assert_not_called()
                resources.assert_not_called()
                api.assert_not_called()

    def test_immutable_cached_install_keeps_prior_same_executable_setup_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / 'evidence'
            evidence.mkdir()
            app = SimpleNamespace(app_path=root / 'app', provenance={
                'status': 'verified', 'producerRun': cache.SETUP_RUN,
                'appBuildHead': cache.APP_HEAD, 'executableSHA256': cache.APP_EXECUTABLE})
            prior_receipt = {'run': cache.SETUP_RUN, 'sameExecutable': True, 'evidenceScope': 'sameExecutable'}
            with patch.dict(cache.os.environ, {'RUNNER_TEMP': str(root)}), \
                    patch.object(cache, 'prior_setup', return_value=prior_receipt) as prior, \
                    patch.object(cache, 'app_resources', side_effect=RuntimeError('Fixture stops before network')):
                with self.assertRaisesRegex(RuntimeError, 'Fixture stops before network'):
                    cache.prepare_cached_model(root, evidence, app, cache.CACHE_RUN, Mock())
                prior.assert_called_once_with(root.resolve() / 'lip-model-cache-work', evidence, app.provenance)
            receipt = json.loads((evidence / 'model-cache.json').read_text())
            self.assertEqual(receipt['priorSetup'], prior_receipt)
            self.assertNotIn('setupProfile', receipt)
            self.assertFalse(receipt['currentFreshSetupAssessed'])

    def test_wrapper_checks_macos_checkout_and_build_without_confusing_ios(self):
        source = 'a' * 40
        raw = workflow(source)
        self.assertEqual(cache.validate_same_job_workflow(raw, source)['checkoutSourceHead'], source)
        for changed in [raw.replace(('ref: ' + source).encode(), b'ref: main'),
                        raw.replace(cache.CHECKOUT_ACTION.encode(), b'b' * 40, 1),
                        raw.replace(b'run: make local CONFIGURATION=Release', b'run: make local CONFIGURATION=Debug'),
                        raw.replace(b'--same-job-build', b'--producer-run 7'),
                        raw.replace(b'  macos:\n', b'  other:\n')]:
            with self.subTest(changed=changed[:60]), self.assertRaises(ArtifactError):
                cache.validate_same_job_workflow(changed, source)

    def test_same_job_api_requires_actual_transport_runner_and_completed_gates(self):
        environment = {'GITHUB_RUN_ID': '17', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_SHA': 'b' * 40,
                       'GITHUB_REF': 'refs/heads/' + cache.SAME_JOB_BRANCH + 'fixture', 'RUNNER_NAME': 'hosted-Mac'}
        run = {'id': 17, 'head_sha': 'b' * 40, 'run_attempt': 1, 'path': cache.SAME_JOB_WORKFLOW,
               'event': 'push', 'head_branch': environment['GITHUB_REF'].removeprefix('refs/heads/'), 'status': 'in_progress',
               'repository': {'id': REPOSITORY_ID, 'full_name': REPOSITORY},
               'head_repository': {'id': REPOSITORY_ID, 'full_name': REPOSITORY}}
        job = {'id': 21, 'name': 'Run complete standard macOS gates', 'run_id': 17, 'run_attempt': 1,
               'head_sha': 'b' * 40, 'status': 'in_progress', 'runner_name': 'hosted-Mac', 'labels': ['macos-26'],
               'steps': [{'name': name, 'status': 'completed', 'conclusion': 'success'} for name in cache.SAME_JOB_STEPS]
                        + [{'name': cache.SAME_JOB_E2E, 'status': 'in_progress', 'conclusion': None}]}
        jobs = {'total_count': 2, 'jobs': [job, {'name': 'Unrelated pending iOS job', 'status': 'queued'}]}
        self.assertEqual(cache.validate_same_job_run(run, jobs, environment)['id'], 21)
        rerun_jobs = copy.deepcopy(jobs)
        rerun_jobs['jobs'][0]['run_attempt'] = 2
        rerun_environment = dict(environment, GITHUB_RUN_ATTEMPT='2')
        self.assertEqual(cache.validate_same_job_run(dict(run, run_attempt=2), rerun_jobs, rerun_environment)['id'], 21)
        for wrong_run, wrong_jobs in [(run, rerun_jobs), (dict(run, run_attempt=2), jobs)]:
            with self.assertRaises(ArtifactError):
                cache.validate_same_job_run(wrong_run, wrong_jobs, rerun_environment)
        for field, value in [('head_sha', 'a' * 40), ('run_attempt', 2), ('path', 'other.yml'),
                             ('head_repository', {'id': 22, 'full_name': REPOSITORY})]:
            with self.subTest(field=field), self.assertRaises(ArtifactError):
                cache.validate_same_job_run(dict(run, **{field: value}), jobs, environment)
        for name in cache.SAME_JOB_STEPS:
            changed = copy.deepcopy(jobs)
            next(step for step in changed['jobs'][0]['steps'] if step['name'] == name)['conclusion'] = 'skipped'
            with self.subTest(step=name), self.assertRaises(ArtifactError):
                cache.validate_same_job_run(run, changed, environment)
        for field, value in [('runner_name', 'another-host'), ('head_sha', 'a' * 40), ('labels', ['self-hosted'])]:
            changed = copy.deepcopy(jobs)
            changed['jobs'][0][field] = value
            with self.subTest(field=field), self.assertRaises(ArtifactError):
                cache.validate_same_job_run(run, changed, environment)
        changed = copy.deepcopy(jobs)
        changed['jobs'][0]['steps'].reverse()
        with self.assertRaises(ArtifactError):
            cache.validate_same_job_run(run, changed, environment)

    def test_current_cached_setup_requires_native_install_and_actual_ui_without_prior_claims(self):
        result = {'setupProfile': 'currentNativeCachedInstall', 'actualSetupButtonPressed': False,
                  'freshDownloadAssessed': False, 'currentFreshSetupAssessed': False, 'historicalSetupUsed': False,
                  'actualSetupUIReady': True, 'actualModeControlsChanged': True, 'initialMasterOffObserved': True,
                  'initialLipsOnlyOffObserved': True, 'finalMasterOffObserved': True, 'finalLipsOnlyOffObserved': True}
        model = {'status': 'verified', 'setupProfile': 'currentNativeCachedInstall', 'historicalSetupUsed': False,
                 'nativeInstall': {'passed': True, 'nativeFullVerificationPassed': True, 'storageFileCount': 658}}
        self.assertTrue(runner.cached_setup_passed(result, model, True))
        for field in result:
            changed = dict(result, **{field: not result[field] if type(result[field]) is bool else 'other'})
            with self.subTest(field=field):
                self.assertFalse(runner.cached_setup_passed(changed, model, True))
        for field in ('priorSetupRun', 'priorSetupSourceHead', 'priorSetupSameExecutable'):
            with self.subTest(prior=field):
                self.assertFalse(runner.cached_setup_passed(dict(result, **{field: cache.SETUP_RUN}), model, True))
        for changed in [dict(model, status='blocked'), dict(model, priorSetup={'run': cache.SETUP_RUN}),
                        dict(model, historicalSetupUsed=True), dict(model, nativeInstall={}),
                        dict(model, nativeInstall=dict(model['nativeInstall'], storageFileCount=657))]:
            with self.subTest(model=changed):
                self.assertFalse(runner.cached_setup_passed(result, changed, True))
        prior = dict(result, setupProfile='verifiedCachedModelWithPriorSetup', priorSetupRun=cache.SETUP_RUN)
        prior_model = {'priorSetup': {'run': cache.SETUP_RUN}}
        self.assertTrue(runner.cached_setup_passed(prior, prior_model, False))
        self.assertFalse(runner.cached_setup_passed(dict(prior, priorSetupRun=cache.SETUP_RUN + 1), prior_model, False))
        self.assertFalse(runner.cached_setup_passed(prior, prior_model, True))

    def test_actual_app_resources_cannot_be_substituted_for_the_cached_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'VoiceInkLip/Sources/VoiceInkLip/Resources'
            actual = root / 'app/Contents/Resources/VoiceInkLip_VoiceInkLip.bundle/Resources'
            for directory in (source, actual):
                directory.mkdir(parents=True)
                (directory / 'manifest.json').write_text(json.dumps({'checkpoint_bytes': cache.CHECKPOINT_BYTES,
                    'checkpoint_sha256': cache.CHECKPOINT_SHA256, 'storages': {str(index): {} for index in range(658)}}))
                (directory / 'visual-ctc.onnx').write_bytes(b'real graph fixture')
            cache.app_resources(root, root / 'app')
            (actual / 'visual-ctc.onnx').write_bytes(b'changed graph')
            with self.assertRaises(ArtifactError):
                cache.app_resources(root, root / 'app')

    def test_same_job_profile_refuses_local_host_before_any_writes_or_api(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(cache.os.environ, {}, clear=True), \
                patch.object(cache, 'api') as api, patch.object(cache, 'command') as command:
            root = Path(temporary)
            with self.assertRaises(ArtifactError):
                cache.prepare_same_job_app(root, root / 'evidence', root / 'app', 'a' * 40)
            self.assertEqual(list(root.iterdir()), [])
            api.assert_not_called()
            command.assert_not_called()

    def test_same_job_postcheck_refuses_changed_sources_resources_or_executable(self):
        for changed in ('none', 'sources', 'resources', 'executable', 'signature'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                provenance = {'appBuildHead': 'a' * 40, 'transportHead': 'b' * 40, 'workflowSHA256': 'c' * 64,
                              'macProjectBuild': {'project': 'VoiceInk.xcodeproj'}, 'appResourceHashes': [{'sha256': 'd' * 64}],
                              'executableSHA256': 'e' * 64}
                app = SimpleNamespace(provenance=provenance, evidence=root, app_path=root / 'app',
                                      verify_unchanged=Mock(side_effect=ArtifactError('Signature changed') if changed == 'signature' else None))
                source = {'workflowSHA256': 'f' * 64 if changed == 'sources' else 'c' * 64,
                          'macProjectBuild': {'project': 'VoiceInk.xcodeproj'}}
                resources = [{'sha256': 'f' * 64 if changed == 'resources' else 'd' * 64}]
                with patch.object(cache, 'check_same_job_sources', return_value=source), \
                        patch.object(cache, 'app_resources', return_value=(root, {}, resources)), \
                        patch.object(cache, 'file_sha256', return_value='f' * 64 if changed == 'executable' else 'e' * 64):
                    if changed == 'none':
                        cache.verify_same_job_unchanged(root, app)
                        self.assertTrue(provenance['sameJobSourcesUnchanged'])
                    else:
                        with self.assertRaises(ArtifactError):
                            cache.verify_same_job_unchanged(root, app)
                        self.assertFalse(provenance['sameJobSourcesUnchanged'])
                app.verify_unchanged.assert_called_once()
                self.assertEqual(json.loads((root / 'provenance.json').read_text())['sameJobSourcesUnchanged'], changed == 'none')

    def test_camera_transport_binding_does_not_relax_immutable_receipt_checks(self):
        feature, transport = 'a' * 40, 'b' * 40
        self.assertEqual(runner.camera_source_binding({'sourceHead': feature}, feature)['probeSourceHead'], feature)
        with self.assertRaises(RuntimeError):
            runner.camera_source_binding({'sourceHead': transport}, feature)
        app = {'buildOrigin': 'sameJobRelease', 'proofHead': feature, 'appBuildHead': feature, 'transportHead': transport}
        with patch.dict(runner.os.environ, {'GITHUB_SHA': transport}):
            receipt = runner.camera_source_binding({'sourceHead': transport}, feature, app)
            self.assertEqual((receipt['probeSourceHead'], receipt['receiptSourceHead']), (feature, transport))
            for wrong in [dict(app, proofHead='c' * 40), dict(app, transportHead='c' * 40), dict(app, buildOrigin='other')]:
                with self.assertRaises(RuntimeError):
                    runner.camera_source_binding({'sourceHead': transport}, feature, wrong)
            with self.assertRaises(RuntimeError):
                runner.camera_source_binding({'sourceHead': feature}, feature, app)

    def test_real_git_current_source_is_bound_without_historical_setup_equivalence(self):
        for change in ('none', 'updated-setup', 'dirty', 'untracked', 'extra-transport', 'wrong-pin', 'wrong-head', 'workspace-build'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)

                def git(*arguments):
                    return subprocess.check_output(['git', '-c', 'user.name=Proof Fixture', '-c', 'user.email=fixture@example.invalid',
                                                    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
                                                    *arguments], cwd=root, stderr=subprocess.DEVNULL).decode().strip()

                def commit():
                    git('add', '.')
                    git('commit', '-qm', 'fixture')
                    return git('rev-parse', 'HEAD')

                git('init', '-q')
                (root / 'Setup.swift').write_text('original installer')
                (root / 'Policy.swift').write_text('old policy')
                (root / 'Makefile').write_bytes((Path(__file__).resolve().parents[2] / 'Makefile').read_bytes())
                prior = commit()
                (root / 'Policy.swift').write_text('fixed policy')
                if change == 'updated-setup':
                    (root / 'Setup.swift').write_text('changed installer')
                if change == 'workspace-build':
                    makefile = root / 'Makefile'
                    makefile.write_bytes(makefile.read_bytes().replace(b'-project VoiceInk.xcodeproj', b'-workspace VoiceInk.xcworkspace'))
                feature = commit()
                wrapper = root / cache.SAME_JOB_WORKFLOW
                wrapper.parent.mkdir(parents=True)
                wrapper.write_bytes(workflow('d' * 40 if change == 'wrong-pin' else feature))
                if change == 'extra-transport':
                    (root / 'Policy.swift').write_text('unreviewed transport product')
                transport = commit()
                git('checkout', '-q', '--detach', feature)
                if change == 'dirty':
                    (root / 'Setup.swift').write_text('dirty installer')
                if change == 'untracked':
                    (root / 'Unexpected.swift').write_text('untracked source')
                declared = prior if change == 'wrong-head' else feature
                with patch.object(cache, 'ensure_commit', wraps=cache.ensure_commit) as ensure:
                    if change in ('none', 'updated-setup'):
                        receipt = cache.check_same_job_sources(root, declared, transport)
                        self.assertNotIn('setupSources', receipt)
                        self.assertEqual(receipt['checkoutSourceHead'], feature)
                        self.assertEqual(receipt['macProjectBuild']['dependencyLock'], cache.LOCK)
                        self.assertEqual([call.args for call in ensure.call_args_list], [(root, transport)])
                    else:
                        with self.assertRaises(ArtifactError):
                            cache.check_same_job_sources(root, declared, transport)


if __name__ == '__main__':
    unittest.main()
