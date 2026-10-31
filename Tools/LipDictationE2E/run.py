#!/usr/bin/env python3
"""Run the existing real-shortcut/AX runtime harness on a disposable hosted Mac."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import sqlite3
import subprocess
import sys
import time
import urllib.request
import wave

ROOT = Path(__file__).resolve().parents[2]
APP_ID = 'com.negentropi.RomaJustTalk'
HELPER_ID = 'com.happyf.roma-just-talk.RuntimeE2EHarness'
VOICE_MODEL_PREFERENCE_KEY = 'CurrentTranscriptionModel'
MODEL_REVISION = 'ee09c569f73759e6d44c9bd16766f477b2b36d39'
MODEL_BASE = 'https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/' + MODEL_REVISION
FIXTURE_URL = 'https://media.githubusercontent.com/media/CheyneyComputerScience/CREMA-D/1658cd342dff90010aa843eaeebd53610a08b1dc/VideoFlash/1003_IEO_NEU_XX.flv'
FIXTURE_SHA = 'db7b8cf8cdbe547ab491c42801a1bae5b16c5471050d7e3d9e1f0173c7a0d8fc'


def sha256(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def download(url, destination, expected_hash, expected_size=None):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and (expected_size is None or destination.stat().st_size == expected_size) and sha256(destination) == expected_hash:
        return
    temporary = destination.with_name(destination.name + '.lip-e2e-download')
    request = urllib.request.Request(url, headers={'User-Agent': 'RomaJustTalk-Disposable-E2E'})
    with urllib.request.urlopen(request, timeout=90) as response, temporary.open('wb') as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)
    if expected_size is not None and temporary.stat().st_size != expected_size:
        raise RuntimeError('Unexpected fixture/model byte count: ' + destination.name)
    if sha256(temporary) != expected_hash:
        raise RuntimeError('Fixture/model hash mismatch: ' + destination.name)
    temporary.replace(destination)


def history():
    path = Path.home() / 'Library/Application Support' / APP_ID / 'default.store'
    if not path.exists():
        return []
    with sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True) as connection:
        connection.row_factory = sqlite3.Row
        tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if 'ZTRANSCRIPTION' not in tables:
            raise RuntimeError('SwiftData history table unavailable; cannot independently verify history')
        columns = {row[1] for row in connection.execute('PRAGMA table_info(ZTRANSCRIPTION)')}
        required = {'Z_PK', 'ZTEXT', 'ZAUDIOFILEURL', 'ZTRANSCRIPTIONSTATUS', 'ZTRANSCRIPTIONMODELNAME'}
        if not required <= columns:
            raise RuntimeError('SwiftData schema differs; update the independent history reader')
        return [dict(row) for row in connection.execute('SELECT Z_PK, ZTEXT, ZAUDIOFILEURL, ZTRANSCRIPTIONSTATUS, ZTRANSCRIPTIONMODELNAME FROM ZTRANSCRIPTION ORDER BY Z_PK')]


def microphone_tcc_fixture(evidence, run, name, expected_value):
    database = Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db'
    query = "SELECT service,client,client_type,auth_value,auth_reason,auth_version,hex(csreq) AS requirementHex FROM access WHERE service='kTCCServiceMicrophone' AND client='" + APP_ID + "' AND client_type=0 AND indirect_object_identifier='UNUSED';"
    run(name, ['/usr/bin/sqlite3', '-json', database, query])
    rows = json.loads((evidence / (name + '.log')).read_text())
    if len(rows) != 1 or rows[0]['auth_value'] != expected_value:
        raise RuntimeError('The microphone TCC test fixture does not have the required row state: ' + name)
    row = rows[0]
    requirement = bytes.fromhex(row.pop('requirementHex'))
    if requirement != (evidence / (APP_ID + '.csreq')).read_bytes():
        raise RuntimeError('The microphone TCC fixture does not match the exact signed app requirement')
    write(evidence / (name + '.json'), {
        'observedRow': row, 'signedRequirementSHA256': hashlib.sha256(requirement).hexdigest(),
        'appAuthorizationAPIQueried': False,
        'boundary': 'Observed SQL fixture state only. App behavior is established separately by actual dictation and microphone hardware diagnostics.',
    })


def build_visual_driver(evidence, run):
    build = evidence / 'visual-build'
    build.mkdir(exist_ok=True)
    helper = build / 'LipDictationE2E.app'
    (helper / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    frameworks = helper / 'Contents/Frameworks'
    frameworks.mkdir(exist_ok=True)
    core = ROOT / 'Tools/RuntimeE2EHarness/Sources/RuntimeE2ECore/RuntimeE2ECore.swift'
    run('build-reused-harness-core', ['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0', '-O', '-parse-as-library', '-emit-library', '-emit-module', '-module-name', 'RuntimeE2ECore', core, '-emit-module-path', build / 'RuntimeE2ECore.swiftmodule', '-o', frameworks / 'libRuntimeE2ECore.dylib', '-Xlinker', '-install_name', '-Xlinker', '@rpath/libRuntimeE2ECore.dylib'], timeout=180)
    sources = sorted(path for path in (ROOT / 'Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness').glob('*.swift') if path.name != 'main.swift')
    driver = ROOT / 'Tools/LipDictationE2E/VisualCases.swift'
    run('build-visual-driver', ['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0', '-O', '-parse-as-library', '-module-name', 'LipDictationE2E', '-I', build, '-L', frameworks, '-lRuntimeE2ECore', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', *sources, driver, '-o', helper / 'Contents/MacOS/LipDictationE2E'], timeout=240)
    info = plistlib.loads((ROOT / 'Tools/RuntimeE2EHarness/Info.plist').read_bytes())
    info.update({'CFBundleIdentifier': 'com.negentropi.LipDictationE2E', 'CFBundleExecutable': 'LipDictationE2E', 'CFBundleName': 'Lip Dictation E2E'})
    (helper / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('sign-visual-core', ['codesign', '--force', '--sign', '-', frameworks / 'libRuntimeE2ECore.dylib'])
    run('sign-visual-driver', ['codesign', '--force', '--sign', '-', helper])
    run('verify-visual-driver', ['codesign', '--verify', '--deep', '--strict', helper])
    run('verify-native-helper-load', [helper / 'Contents/MacOS/LipDictationE2E', '--link-check'])
    if (evidence / 'verify-native-helper-load.log').read_text().strip() != 'PASS native lip dictation helper loaded':
        raise RuntimeError('The native helper did not acknowledge the link-only check')
    write(evidence / 'visual-driver-source.json', {'nativeLoadVerified': True, 'executableSHA256': sha256(helper / 'Contents/MacOS/LipDictationE2E'), 'reusedSources': [{'path': str(path.relative_to(ROOT)), 'sha256': sha256(path)} for path in [core, *sources, driver]]})
    return helper


def prepare_screen_capture(evidence, app, driver, name, run):
    app, driver = app.resolve(), driver.resolve()
    capture = evidence / (name + '-capture.json')
    consent = evidence / (name + '-consent.json')
    ready = consent.with_suffix('.ready.json')
    if any(path.exists() for path in [capture, consent, ready]):
        raise RuntimeError('Screen preflight requires fresh receipt paths: ' + name)
    configuration = evidence / (name + '-consent-config.json')
    write(configuration, {'appPath': str(app.resolve()), 'captureReport': str(capture), 'readyReport': str(ready)})
    launch_environment = []
    for key in ['GITHUB_ACTIONS', 'RUNNER_ENVIRONMENT']:
        launch_environment.extend(['--env', key + '=' + os.environ[key]])
    driver_command = ['/usr/bin/open', '-W', '-n', *launch_environment, '-o', str(evidence / (name + '-driver.stdout.log')), '--stderr', str(evidence / (name + '-driver.stderr.log')), driver, '--args', '--screen-consent-driver', configuration, '--output', consent]
    code, consent_code = None, None
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            approval = pool.submit(run, name + '-consent-driver', driver_command, timeout=55, required=False)
            try:
                deadline = time.monotonic() + 10
                while not ready.is_file() and time.monotonic() < deadline and not approval.done():
                    time.sleep(0.1)
                if not ready.is_file() or json.loads(ready.read_text()).get('ready') is not True:
                    raise RuntimeError('The native screen consent driver was not ready: ' + name)
                code = run(name + '-capture', ['/usr/bin/open', '-W', '-n', *launch_environment, '-o', str(evidence / (name + '-capture.stdout.log')), '--stderr', str(evidence / (name + '-capture.stderr.log')), app, '--args', '--screen-capture-check', '--json-output', capture, '--consent-result', consent], timeout=60, required=False)
            finally:
                consent_code = approval.result()
    finally:
        if code != 0 or consent_code != 0:
            for receipt, bundle in [(capture, app), (ready, driver)]:
                if not receipt.is_file():
                    continue
                identity = json.loads(receipt.read_text())
                pid = identity.get('pid')
                if not isinstance(pid, int) or pid <= 1 or identity.get('bundlePath') != str(bundle):
                    continue
                bundle_info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
                executable_path = str(bundle / 'Contents/MacOS' / bundle_info['CFBundleExecutable'])
                for sig in [signal.SIGTERM, signal.SIGKILL]:
                    observed = subprocess.run(['/bin/ps', '-p', str(pid), '-ww', '-o', 'comm='], capture_output=True, text=True, timeout=3)
                    if observed.returncode != 0 or observed.stdout.strip() != executable_path:
                        break
                    try:
                        os.kill(pid, sig)
                    except ProcessLookupError:
                        break
                    time.sleep(0.2)
    if not capture.is_file() or not consent.is_file():
        raise RuntimeError('Screen capture or consent receipt missing: ' + name)
    actual = json.loads(capture.read_text())
    approved = json.loads(consent.read_text())
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    screenshot = capture.with_suffix('.png')
    passed = code == 0 and consent_code == 0 and actual.get('passed') is True and actual.get('consentAcknowledged') is True and approved.get('passed') is True and approved.get('promptGone') is True and approved.get('allowPressCount') == 1 and actual.get('bundleID') == info['CFBundleIdentifier'] and actual.get('bundlePath') == str(app.resolve()) and actual.get('executableSHA256') == sha256(executable) and screenshot.is_file() and screenshot.stat().st_size > 0 and actual.get('pngSHA256') == sha256(screenshot)
    if not passed:
        raise RuntimeError('Actual screen capture and normal OS consent preflight failed: ' + name)
    return {'passed': True, 'captureReport': capture.name, 'consentReport': consent.name, 'screenshot': screenshot.name, 'allowPressCount': approved['allowPressCount'], 'boundary': 'Real ScreenCaptureKit capture, exact owned-helper OS prompt observed, ordinary Allow exactly once, and prompt absent before dictation fixtures'}


def camera_source_binding(camera, proof_head, same_job_app=None):
    expected = proof_head
    if same_job_app is not None:
        if (same_job_app.get('buildOrigin') != 'sameJobRelease' or same_job_app.get('proofHead') != proof_head
                or same_job_app.get('appBuildHead') != proof_head or same_job_app.get('transportHead') != os.environ.get('GITHUB_SHA')):
            raise RuntimeError('Camera transport is not bound to the verified same-job feature source')
        expected = same_job_app['transportHead']
    if camera.get('sourceHead') != expected:
        raise RuntimeError('The camera receipt belongs to a different source or transport revision')
    return {'probeSourceHead': proof_head, 'receiptSourceHead': camera['sourceHead'],
            'transportHead': expected if same_job_app is not None else None,
            'boundary': ('The probe stamps the GitHub transport revision. Its actual feature checkout is bound by the verified wrapper-only transport delta.'
                         if same_job_app is not None else 'The probe receipt matches the exact checked-out proof source.')}


def run_visual_cases(args, evidence, configuration, original, audio_fixture, app, helper, run, grant, owned_obs_cleanup, cached_model=None):
    visual_config = evidence / 'visual-config.json'
    write(visual_config, configuration)
    control_report = evidence / 'negative-controls.json'
    code = run('run-negative-controls', ['/usr/bin/open', '-W', '-n', '--env', 'GITHUB_ACTIONS=' + os.environ['GITHUB_ACTIONS'], '--env', 'RUNNER_ENVIRONMENT=' + os.environ['RUNNER_ENVIRONMENT'], '-o', str(evidence / 'negative-controls.stdout.log'), '--stderr', str(evidence / 'negative-controls.stderr.log'), helper, '--args', '--config', visual_config, '--output', control_report, '--scenario', 'negative-controls', '--app-log', evidence / 'app.log'], timeout=90, required=False)
    controls = json.loads(control_report.read_text()) if control_report.is_file() else {}
    controls_passed = code == 0 and controls.get('passed') is True and controls.get('unchangedObservation') == 'readableUnchanged' and controls.get('changedObservation') == 'changed' and controls.get('closedObservation') == 'unreadable' and controls.get('closedTargetReadable') is False and controls.get('acceptedStates') == ['readableUnchanged'] and controls.get('rejectedStates') == ['changed', 'unreadable']
    cases = [{'scenario': 'negative-controls', 'passed': controls_passed, 'report': control_report.name}]
    if not controls_passed:
        write(evidence / 'visual-summary.json', {'passed': False, 'cases': cases})
        raise RuntimeError('Actual negative-observation controls failed')
    websocket = Path.home() / 'Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json'
    video = evidence / 'clock-padded-silent.mp4'
    silence = evidence / 'clock-silent.wav'
    run('prepare-aligned-camera-feed', ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-i', original, '-map', '0:v:0', '-an', '-vf', 'scale=640:480,fps=25,tpad=start_mode=clone:start_duration=1:stop_mode=clone:stop_duration=0.5', '-c:v', 'libx264', '-crf', '0', '-pix_fmt', 'yuv420p', video])
    run('prepare-zero-audio', ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-i', audio_fixture, '-af', 'volume=0', silence])
    run('verify-zero-audio', ['ffmpeg', '-nostdin', '-hide_banner', '-i', silence, '-af', 'volumedetect', '-f', 'null', '-'])
    with wave.open(str(silence), 'rb') as stream:
        if any(stream.readframes(stream.getnframes())):
            raise RuntimeError('The fallback test audio contains nonzero PCM')
    write(evidence / 'visual-fixture-hashes.json', {'silentMotionVideoSHA256': sha256(video), 'speechAudioSHA256': sha256(audio_fixture), 'zeroAudioSHA256': sha256(silence), 'zeroAudioPCMVerified': True})
    for scenario in ['setup', 'combined', 'combined-silent', 'lips', 'cancel', 'disable', 'quit']:
        if scenario == 'combined':
            camera_summary = args.obs_summary or Path(os.environ['RUNNER_TEMP']) / 'lip-camera-probe/summary.json'
            if args.obs_summary is None:
                run('provision-supported-camera', ['env', 'LIP_CAMERA_PROBE_KEEP_OBS_RUNNING=1', 'python3', ROOT / 'Tools/LipCameraProbe/run.py'], timeout=1000)
            if not camera_summary.is_file():
                raise RuntimeError('The actual virtual-camera probe wrote no receipt')
            camera = json.loads(camera_summary.read_text())
            if camera.get('status') != 'supportedDeviceReady' or camera.get('obsRetainedForE2E') is not True:
                raise RuntimeError('A moving supported OBS camera and retained running OBS process are required')
            proof_head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
            binding = camera_source_binding(camera, proof_head, cached_model['appBuild'] if args.same_job_build else None)
            write(evidence / 'supported-camera-source.json', binding)
            # Cleanup ownership transfers only after accepting the successful retained-producer receipt.
            owned_obs_cleanup['accepted'] = True
            write(evidence / 'supported-camera.json', camera)
            if not websocket.is_file():
                raise RuntimeError('The probe-owned private OBS WebSocket configuration is unavailable')
        enabled = scenario != 'setup'
        lips_only = scenario in ['lips', 'cancel', 'disable', 'quit']
        recorder_fixture = None
        if scenario == 'cancel':
            recorder_read = run('read-cancel-recorder-type', ['defaults', 'read', APP_ID, 'RecorderType'], required=False)
            recorder_value = (evidence / 'read-cancel-recorder-type.log').read_text().strip()
            if recorder_read != 0 and 'does not exist' not in recorder_value:
                raise RuntimeError('Could not establish the original cancel recorder preference')
            if recorder_read == 0 and recorder_value not in ['none', 'notch', 'mini']:
                raise RuntimeError('Unexpected recorder style in the fresh cancel fixture')
            recorder_fixture = {'originalPresent': recorder_read == 0, 'originalRawValue': recorder_value if recorder_read == 0 else None, 'requestedRawValue': 'mini', 'restored': False}
            write(evidence / 'cancel-recorder-fixture.json', recorder_fixture)
        for key, value in [('LipDictationEnabled', enabled), ('LipDictationLipOnly', lips_only)]:
            run('set-' + scenario + '-' + key, ['defaults', 'write', APP_ID, key, '-bool', str(value).lower()])
        report = evidence / (scenario + '.json')
        before = history()
        before_ids = {row['Z_PK'] for row in before}
        command = ['/usr/bin/open', '-W', '-n', '-o', str(evidence / (scenario + '.stdout.log')), '--stderr', str(evidence / (scenario + '.stderr.log')), helper, '--args', '--config', visual_config, '--output', report, '--scenario', scenario, '--app-log', evidence / 'app.log', '--obs-config', websocket, '--video', video, '--audio', silence if scenario == 'combined-silent' else audio_fixture]
        if scenario == 'setup' and cached_model is not None:
            command += ['--prior-setup-run', cached_model['priorSetup']['run']]
            if cached_model['priorSetup']['evidenceScope'] == 'unchangedSetupSources':
                command += ['--prior-setup-source-head', cached_model['priorSetup']['appBuildHead']]
        deny_microphone = scenario == 'lips'
        if deny_microphone:
            microphone_tcc_fixture(evidence, run, 'microphone-authorized-before-lips', 2)
        try:
            if recorder_fixture is not None:
                run('set-cancel-recorder-type', ['defaults', 'write', APP_ID, 'RecorderType', '-string', 'mini'])
            run('refresh-' + scenario + '-preferences', ['killall', 'cfprefsd'], required=False)
            if deny_microphone:
                grant(app, APP_ID, [], ['kTCCServiceMicrophone'], auth_value=0)
                run('refresh-denied-microphone-tcc-user', ['killall', 'tccd'], required=False)
                run('refresh-denied-microphone-tcc-system', ['sudo', '-n', 'killall', 'tccd'], required=False)
                time.sleep(2)
                microphone_tcc_fixture(evidence, run, 'microphone-denied-before-lips', 0)
            code = run('run-' + scenario, command, timeout=1400 if scenario == 'setup' else 360, required=False)
            if not report.is_file():
                raise RuntimeError('The actual ' + scenario + ' helper wrote no report')
            result = json.loads(report.read_text())
            if deny_microphone:
                microphone_tcc_fixture(evidence, run, 'microphone-denied-after-lips', 0)
        finally:
            if recorder_fixture is not None:
                if recorder_fixture['originalPresent']:
                    run('restore-cancel-recorder-type', ['defaults', 'write', APP_ID, 'RecorderType', '-string', recorder_fixture['originalRawValue']])
                else:
                    run('restore-cancel-recorder-type', ['defaults', 'delete', APP_ID, 'RecorderType'])
                run('refresh-restored-recorder-preferences', ['killall', 'cfprefsd'], required=False)
                restored_code = run('verify-restored-recorder-type', ['defaults', 'read', APP_ID, 'RecorderType'], required=False)
                restored_value = (evidence / 'verify-restored-recorder-type.log').read_text().strip()
                recorder_fixture['restored'] = (restored_code == 0 and restored_value == recorder_fixture['originalRawValue']) if recorder_fixture['originalPresent'] else (restored_code != 0 and 'does not exist' in restored_value)
                write(evidence / 'cancel-recorder-fixture.json', recorder_fixture)
                if not recorder_fixture['restored']:
                    raise RuntimeError('Cancel recorder preference restoration was not verified')
            if deny_microphone:
                grant(app, APP_ID, [], ['kTCCServiceMicrophone'])
                run('refresh-restored-microphone-tcc-user', ['killall', 'tccd'], required=False)
                run('refresh-restored-microphone-tcc-system', ['sudo', '-n', 'killall', 'tccd'], required=False)
                time.sleep(2)
                microphone_tcc_fixture(evidence, run, 'microphone-restored-after-lips', 2)
        after = history()
        created = [row for row in after if row['Z_PK'] not in before_ids]
        completed = [row for row in created if row['ZTRANSCRIPTIONSTATUS'] == 'completed']
        positive = scenario in ['combined', 'combined-silent', 'lips']
        passed = code == 0 and result.get('passed') is True and len(completed) == (1 if positive else 0)
        if scenario == 'setup':
            if cached_model is None:
                passed = passed and result.get('actualSetupButtonPressed') is True and result.get('freshDownloadAssessed') is True
            else:
                passed = passed and result.get('actualSetupButtonPressed') is False and result.get('freshDownloadAssessed') is False and result.get('priorSetupRun') == cached_model['priorSetup']['run'] and result.get('actualSetupUIReady') is True and result.get('initialMasterOffObserved') is True and result.get('initialLipsOnlyOffObserved') is True and result.get('finalMasterOffObserved') is True and result.get('finalLipsOnlyOffObserved') is True
                if cached_model['priorSetup']['evidenceScope'] == 'unchangedSetupSources':
                    passed = passed and result.get('setupProfile') == 'verifiedCachedModelWithPriorSetupSources' and result.get('priorSetupSameExecutable') is False and result.get('priorSetupSourceHead') == cached_model['priorSetup']['appBuildHead']
        if positive:
            passed = passed and len(created) == 1 and completed[0]['ZTEXT'].strip() != ''
            if scenario == 'lips':
                passed = passed and completed[0]['ZAUDIOFILEURL'] is None
            else:
                passed = passed and bool(completed[0]['ZAUDIOFILEURL'])
        elif scenario in ['setup', 'disable', 'quit']:
            passed = passed and not created
        else:
            passed = passed and all(row['ZAUDIOFILEURL'] is None for row in created)
        write(evidence / (scenario + '-history.json'), {'createdRows': created, 'independentHistoryPassed': passed})
        cases.append({'scenario': scenario, 'passed': passed, 'report': report.name, 'historyReport': scenario + '-history.json', 'microphoneTCCDeniedFixture': deny_microphone, 'recorderStyleFixture': 'cancel-recorder-fixture.json' if recorder_fixture is not None else None})
        if not passed:
            write(evidence / 'visual-summary.json', {'passed': False, 'cases': cases})
            raise RuntimeError('Actual app visual scenario failed: ' + scenario)
    private_clips = list(Path(os.environ.get('TMPDIR', '/tmp')).glob('RomaJustTalk-LipDictation/**/*.mov'))
    write(evidence / 'visual-summary.json', {'passed': not private_clips, 'cases': cases, 'remainingPrivateClipCount': len(private_clips), 'recognitionScope': 'One pinned public utterance. This verifies integration, not broad language accuracy or a physical webcam.'})
    if private_clips:
        raise RuntimeError('Private capture clips remained after actual app scenarios')
    return cases


def parse_arguments(arguments=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path)
    parser.add_argument('--app-source-head')
    parser.add_argument('--producer-run', type=int, help='Verify and reuse an immutable Release artifact with identical app and build sources')
    parser.add_argument('--same-job-build', action='store_true', help='Verify a fresh Release built by the dedicated hosted wrapper; prior Setup covers unchanged sources only')
    parser.add_argument('--model-cache-run', type=int, help='Use the pinned CI checkpoint through the unchanged native installer with explicitly scoped prior Setup evidence')
    parser.add_argument('--build-helper-only', action='store_true', help='Compile, link, sign, and load the native helper without app, models, OBS, or TCC changes')
    parser.add_argument('--visual', action='store_true', help='After voice passes, provision OBS and run real visual app scenarios')
    parser.add_argument('--obs-summary', type=Path, help='Reuse a successful same-host OBS probe receipt that retained OBS')
    parser.add_argument('--out', type=Path, default=Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'lip-dictation-e2e')
    args = parser.parse_args(arguments)
    if args.build_helper_only:
        if args.app or args.app_source_head or args.producer_run is not None or args.same_job_build or args.model_cache_run is not None or args.visual or args.obs_summary:
            parser.error('--build-helper-only accepts only --out')
    elif args.app is None or args.app_source_head is None:
        parser.error('--app and --app-source-head are required for runtime proof')
    if args.producer_run is not None and args.producer_run <= 0:
        parser.error('--producer-run must be a positive GitHub Actions run ID')
    if args.same_job_build and (args.producer_run is not None or args.model_cache_run is None or not args.visual):
        parser.error('--same-job-build requires --model-cache-run and --visual, and excludes --producer-run')
    if args.model_cache_run is not None and (args.model_cache_run <= 0 or not (args.producer_run is not None or args.same_job_build) or not args.visual):
        parser.error('--model-cache-run requires a positive run ID, --visual, and either --producer-run or --same-job-build')
    return args


def main():
    args = parse_arguments()
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted' or sys.platform != 'darwin':
        raise RuntimeError('Only a fresh disposable GitHub-hosted macOS runner is supported')
    if os.getuid() == 0 or subprocess.check_output(['stat', '-f', '%u', '/dev/console'], text=True).strip() != str(os.getuid()):
        raise RuntimeError('The ordinary runner user must own the desktop session')
    if platform.machine() != 'arm64':
        raise RuntimeError('This proof requires the hosted Apple-silicon Mac')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if not args.build_helper_only and head != args.app_source_head and args.producer_run is None:
        raise RuntimeError('The supplied app build head must match the checked-out proof source')
    args.out.mkdir(parents=True, exist_ok=True)
    evidence = args.out
    summary = {'sourceHead': head, 'declaredAppSourceHead': args.app_source_head, 'appSourceBoundary': 'The declared app source head is compared with the checkout. The calling workflow must establish the app was built from that head. The executable hash and signature are verified here.', 'status': 'blocked', 'events': [], 'boundary': 'Real app, real shortcut, public audio through BlackHole, independent TextEdit AX/rendered observation and SQLite history'}
    helper = ROOT / '.local-build/Tools/RuntimeE2EHarness.app'
    log_process = None
    log_handle = None
    owned_obs_cleanup = {}
    verified_app = None

    def run(name, command, timeout=60, required=True):
        path = evidence / (name + '.log')
        with path.open('wb') as output:
            try:
                result = subprocess.run([str(item) for item in command], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
        summary['events'].append({'operation': name, 'exitCode': code, 'log': path.name})
        if required and code:
            raise RuntimeError(name + ' failed; inspect ' + str(path))
        return code

    def grant(app, identifier, system_services, user_services, auth_value=2):
        if auth_value not in [0, 2] or (auth_value == 0 and (identifier != APP_ID or system_services or user_services != ['kTCCServiceMicrophone'])):
            raise RuntimeError('Only the app microphone has a denied test fixture')
        run('requirement-' + identifier, ['codesign', '-dr', '-', app])
        lines = (evidence / ('requirement-' + identifier + '.log')).read_text().splitlines()
        requirements = [line.split('designated => ', 1)[1] for line in lines if 'designated => ' in line]
        if len(requirements) != 1:
            raise RuntimeError('Missing exact signed designated requirement: ' + identifier)
        requirement_path = evidence / (identifier + '.requirement')
        requirement_path.write_text(requirements[0] + '\n')
        requirement_binary = evidence / (identifier + '.csreq')
        run('compile-requirement-' + identifier, ['csreq', '-r', requirement_path, '-b', requirement_binary])
        for system, services in [(True, system_services), (False, user_services)]:
            database = Path('/Library/Application Support/com.apple.TCC/TCC.db') if system else Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db'
            for service in services:
                sql = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','" + identifier + "',0," + str(auth_value) + ",4,1,X'" + requirement_binary.read_bytes().hex() + "',0,'UNUSED',0);"
                command = (['sudo', '-n'] if system else []) + ['/usr/bin/sqlite3', str(database), sql]
                run('grant-' + identifier + '-' + service + ('-system' if system else '-user'), command)

    try:
        visual_helper = build_visual_driver(evidence, run)
        if args.build_helper_only:
            summary.pop('declaredAppSourceHead')
            summary.pop('appSourceBoundary')
            summary['status'] = 'nativeHelperBuilt'
            summary['boundary'] = 'Native compile, link, signature, and load check only. No app, model, OBS, TCC, capture, or dictation execution.'
            summary['helperExecutableSHA256'] = sha256(visual_helper / 'Contents/MacOS/LipDictationE2E')
            return 0
        summary['appBuildHead'] = args.app_source_head
        if args.producer_run is not None:
            from app_artifact import prepare_verified_app
            verified_app = prepare_verified_app(
                ROOT, evidence, args.app, args.producer_run, args.app_source_head, head
            )
            app = verified_app.app_path
            summary['appArtifactProvenance'] = verified_app.provenance
            summary['appSourceBoundary'] = 'The immutable producer artifact and source equivalence are verified independently. App build and proof heads remain separate; this is artifact reuse, not a fresh or reproducible build.'
        else:
            app = args.app.resolve()
            if args.same_job_build:
                from model_cache import prepare_same_job_app
                verified_app = prepare_same_job_app(ROOT, evidence, app, args.app_source_head)
                summary['sameJobBuildProvenance'] = verified_app.provenance
                summary['transportHead'] = verified_app.provenance['transportHead']
                summary['appSourceBoundary'] = 'Fresh Release built by this hosted job from the declared feature checkout. Its transport commit adds only the reviewed wrapper; prior Setup covers unchanged sources, not this executable.'
        if not app.is_dir():
            raise RuntimeError('Built app bundle missing')
        with (app / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        if info.get('CFBundleIdentifier') != APP_ID:
            raise RuntimeError('Unexpected application identity')
        executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
        summary['appExecutableSHA256'] = sha256(executable)
        run('verify-app-signature', ['codesign', '--verify', '--deep', '--strict', app])
        run('host', ['sw_vers'])
        run('audio-devices', ['system_profiler', 'SPAudioDataType'])
        if 'BlackHole 2ch' not in (evidence / 'audio-devices.log').read_text():
            run('install-blackhole', ['brew', 'install', '--cask', 'blackhole-2ch'], timeout=420)
            run('reload-audio', ['sudo', '-n', 'killall', 'coreaudiod'], required=False)
            time.sleep(4)
        if shutil.which('ffmpeg') is None:
            run('install-ffmpeg', ['brew', 'install', 'ffmpeg'], timeout=420)
        if not helper.is_dir():
            run('build-existing-harness', ['make', 'runtime-e2e-app'], timeout=300)
        run('verify-helper-signature', ['codesign', '--verify', '--deep', '--strict', helper])
        grant(app, APP_ID, ['kTCCServiceAccessibility', 'kTCCServiceListenEvent', 'kTCCServicePostEvent'], ['kTCCServiceMicrophone'] + (['kTCCServiceCamera'] if args.visual else []))
        grant(helper, HELPER_ID, ['kTCCServiceAccessibility', 'kTCCServicePostEvent', 'kTCCServiceScreenCapture'], ['kTCCServiceScreenCapture'])
        grant(visual_helper, 'com.negentropi.LipDictationE2E', ['kTCCServiceAccessibility', 'kTCCServicePostEvent', 'kTCCServiceScreenCapture'], ['kTCCServiceScreenCapture'])
        run('refresh-tcc-user', ['killall', 'tccd'], required=False)
        run('refresh-tcc-system', ['sudo', '-n', 'killall', 'tccd'], required=False)
        time.sleep(2)
        summary['screenCapturePreflight'] = [
            prepare_screen_capture(evidence, helper, visual_helper, 'runtime-screen', run),
            prepare_screen_capture(evidence, visual_helper, visual_helper, 'visual-screen', run),
        ]

        model = Path.home() / 'Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2'
        manifest = ROOT / 'scripts/runtime-e2e-parakeet-v2.manifest'
        entries = []
        for line in manifest.read_text().splitlines():
            if not line.strip() or line.startswith('#'):
                continue
            digest, size, relative = line.split()
            if Path(relative).is_absolute() or '..' in Path(relative).parts:
                raise RuntimeError('Invalid existing model manifest path')
            entries.append((digest, int(size), relative))
        if len(entries) != 22:
            raise RuntimeError('Pinned Parakeet manifest shape changed')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            tasks = [pool.submit(download, MODEL_BASE + '/' + relative, model / relative, digest, size) for digest, size, relative in entries]
            for task in tasks:
                task.result()
        write(evidence / 'voice-model-receipt.json', {'revision': MODEL_REVISION, 'manifestSHA256': sha256(manifest), 'files': [{'path': name, 'sha256': digest, 'bytes': size} for digest, size, name in entries]})
        original = evidence / 'clock-source.flv'
        download(FIXTURE_URL, original, FIXTURE_SHA)
        audio = evidence / 'audio'
        audio.mkdir(exist_ok=True)
        fixture = audio / 'clock.wav'
        run('extract-public-audio', ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-i', original, '-map', '0:a:0', '-ac', '1', '-ar', '16000', '-af', 'adelay=1000:all=1,apad=pad_dur=0.5', fixture])
        write(evidence / 'fixture-provenance.json', {'url': FIXTURE_URL, 'sourceSHA256': FIXTURE_SHA, 'audioSHA256': sha256(fixture), 'reference': "It's eleven o'clock", 'referenceBoundary': 'Expected text enters the observer configuration only. It is never supplied to the app or recognition model.'})

        for key, kind, value in [
            ('hasCompletedOnboarding', '-bool', 'true'), (VOICE_MODEL_PREFERENCE_KEY, '-string', 'parakeet-tdt-0.6b-v2'),
            ('PrewarmModelOnWake', '-bool', 'true'), ('isSoundFeedbackEnabled', '-bool', 'false'),
            ('enableAnnouncements', '-bool', 'false'), ('restoreClipboardAfterPaste', '-bool', 'false'),
            ('appendTrailingSpace', '-bool', 'false'), ('isAIEnhancementEnabled', '-bool', 'false'),
            ('LipDictationEnabled', '-bool', 'false'), ('LipDictationLipOnly', '-bool', 'false'),
        ]:
            run('preference-' + key, ['defaults', 'write', APP_ID, key, kind, value])
        run('refresh-preferences', ['killall', 'cfprefsd'], required=False)
        configuration = json.loads((ROOT / 'Tools/RuntimeE2EHarness/runtime-e2e.example.json').read_text())
        configuration.update({'audioDirectory': str(audio), 'voiceInkAppPath': str(app), 'voiceInkBuildDirectory': str(app.parent), 'audioLeadSeconds': 0, 'releaseTailSeconds': 0.4, 'explicitHoldSeconds': None, 'preRollWarmupSeconds': 5, 'targetSettleSeconds': 1, 'targetTextTimeoutSeconds': 90, 'latencyThresholdMilliseconds': 90000, 'maximumWordErrorRate': 0.2, 'repetitions': 1, 'minimumTargetCount': 1, 'targetAvailabilityPolicy': 'launchIfNeeded', 'targets': [{'id': 'textedit', 'displayName': 'TextEdit', 'bundleIdentifier': 'com.apple.TextEdit', 'kind': 'document'}], 'expectedTranscripts': {fixture.name: "It's eleven o'clock"}, 'voiceInkLifecycle': 'reuse'})
        config_path = evidence / 'voice-config.json'
        write(config_path, configuration)
        before = history()
        write(evidence / 'history-before.json', before)
        log_handle = (evidence / 'app.log').open('wb')
        log_process = subprocess.Popen(['/usr/bin/log', 'stream', '--level', 'debug', '--style', 'compact', '--predicate', 'subsystem == "com.negentropi.RomaJustTalk"'], stdout=log_handle, stderr=subprocess.STDOUT)
        report_path = evidence / 'voice-default-off.json'
        code = run('voice-default-off', ['/usr/bin/open', '-W', '-n', '-o', str(evidence / 'harness.stdout.log'), '--stderr', str(evidence / 'harness.stderr.log'), helper, '--args', '--config', config_path, '--json-output', report_path], timeout=300, required=False)
        if not report_path.is_file():
            raise RuntimeError('The real runtime harness wrote no report')
        report = json.loads(report_path.read_text())
        after = history()
        write(evidence / 'history-after.json', after)
        before_ids = {row['Z_PK'] for row in before}
        created = [row for row in after if row['Z_PK'] not in before_ids]
        cases = report.get('cases', [])
        log_text = (evidence / 'app.log').read_text(errors='replace')
        passed = code == 0 and report.get('summary', {}).get('passed') is True and len(cases) == 2 and len(created) == 2 and all(row['ZTRANSCRIPTIONSTATUS'] == 'completed' and row['ZAUDIOFILEURL'] and row['ZTEXT'].strip() for row in created) and 'capture.start id=' not in log_text and 'LipRuntime' not in log_text
        summary['voiceDefaultOff'] = {'passed': passed, 'caseCount': len(cases), 'createdHistoryCount': len(created), 'history': created, 'cameraStartObserved': 'capture.start id=' in log_text, 'lipInferenceObserved': 'LipRuntime' in log_text, 'functionalDeadlineSeconds': 90, 'latencyClaim': 'No product latency claim. The generous limit only bounds this functional proof.'}
        if not passed:
            raise RuntimeError('Default-off real dictation gate failed; inspect actual AX, rendered text, history and app logs')
        summary['status'] = 'voiceDefaultOffVerified'
        if args.visual:
            cached_model = None
            if args.model_cache_run is not None:
                from model_cache import prepare_cached_model
                summary['modelCacheReceipt'] = 'model-cache.json'
                cached_model = prepare_cached_model(ROOT, evidence, verified_app, args.model_cache_run, run)
                summary['modelCache'] = cached_model
            summary['visualCases'] = run_visual_cases(args, evidence, configuration, original, fixture, app, visual_helper, run, grant, owned_obs_cleanup, cached_model)
            summary['status'] = 'lipDictationVerified'
    except Exception as error:
        summary['status'] = 'blocked'
        summary['failure'] = str(error)
    finally:
        if owned_obs_cleanup.get('accepted'):
            try:
                control = Path(os.environ['RUNNER_TEMP']) / 'lip-camera-probe/bin/OBSControl'
                websocket = Path.home() / 'Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json'
                receipt = evidence / 'obs-cleanup.json'
                code = run('close-owned-obs', [control, websocket, '-', receipt, 'stop-and-quit'], timeout=55, required=False)
                cleanup = json.loads(receipt.read_text()) if receipt.is_file() else {}
                summary['obsCleanup'] = cleanup
                if code != 0 or cleanup.get('closed') is not True:
                    raise RuntimeError('Owned OBS cleanup did not verify inactive output and process exit; inspect obs-cleanup.json')
            except Exception as error:
                summary['cleanupFailure'] = str(error)
                summary.setdefault('failure', str(error))
                summary['status'] = 'blocked'
        if log_process is not None:
            log_process.terminate()
            try:
                log_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                log_process.kill()
                log_process.wait(timeout=5)
        if log_handle is not None:
            log_handle.close()
        if verified_app is not None:
            try:
                if args.same_job_build:
                    from model_cache import verify_same_job_unchanged
                    verify_same_job_unchanged(ROOT, verified_app)
                else:
                    verified_app.verify_unchanged()
                summary['sameJobAppUnchanged' if args.same_job_build else 'appArtifactUnchanged'] = True
            except Exception as error:
                summary['sameJobAppUnchanged' if args.same_job_build else 'appArtifactUnchanged'] = False
                summary['artifactIntegrityFailure'] = str(error)
                summary['status'] = 'blocked'
        write(evidence / 'summary.json', summary)
        print(json.dumps(summary, indent=2, sort_keys=True))
    if args.visual:
        return 0 if summary['status'] == 'lipDictationVerified' else 1
    return 0 if summary['status'] == 'voiceDefaultOffVerified' else 1


if __name__ == '__main__':
    sys.exit(main())
