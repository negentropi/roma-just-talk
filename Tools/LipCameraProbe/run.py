#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ['RUNNER_TEMP']) / 'lip-camera-probe'
OUT.mkdir(parents=True, exist_ok=True)
BIN = OUT / 'bin'
BIN.mkdir(exist_ok=True)
UI_APP = OUT / 'LipCameraUIProbe.app'
summary = {'status': 'blocked', 'sourceHead': os.environ.get('GITHUB_SHA', ''), 'events': [],
           'boundary': 'Supported OBS camera extension and actual AVFoundation device frames, not app dictation'}
OBS_SHA = '3d6b2eedeb56416602af635adaba32327fdf11ff9d2806a4ce7d5b608de73238'
OBS_URL = 'https://github.com/obsproject/obs-studio/releases/download/33.0.1/OBS-Studio-33.0.1-macOS-Apple.dmg'
FIXTURE_SHA = 'db7b8cf8cdbe547ab491c42801a1bae5b16c5471050d7e3d9e1f0173c7a0d8fc'
FIXTURE_URL = 'https://media.githubusercontent.com/media/CheyneyComputerScience/CREMA-D/1658cd342dff90010aa843eaeebd53610a08b1dc/VideoFlash/1003_IEO_NEU_XX.flv'
mounted = False
started_obs = False
probe_process = None


def run(name, arguments, timeout=40, required=False):
    log = OUT / (name + '.log')
    with log.open('wb') as stream:
        try:
            result = subprocess.run(arguments, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    summary['events'].append({'operation': name, 'exitCode': code, 'log': log.name})
    if required and code != 0:
        raise RuntimeError(name + ' failed with exit code ' + str(code))
    return code


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(part)
    return value.hexdigest()


def screenshot(name):
    run(name, ['/usr/sbin/screencapture', '-x', str(OUT / (name + '.png'))], timeout=12)


def ui(name, approve=False):
    command = ['/usr/bin/open', '-W', '-n', str(UI_APP), '--args', str(OUT / (name + '.json'))]
    if approve:
        command.append('approve')
    run(name, command, timeout=20)


try:
    if os.environ.get('GITHUB_ACTIONS') != 'true' or sys.platform != 'darwin':
        raise RuntimeError('Run only on a disposable macOS GitHub Actions host')
    if subprocess.check_output(['uname', '-m'], text=True).strip() != 'arm64':
        raise RuntimeError('Pinned OBS artifact requires arm64')
    for name, arguments in [
        ('os', ['sw_vers']), ('architecture', ['uname', '-m']), ('sip', ['/usr/bin/csrutil', 'status']),
        ('gatekeeper', ['/usr/sbin/spctl', '--status']), ('console-owner', ['/usr/bin/stat', '-f', '%Su', '/dev/console']),
        ('extensions-before', ['/usr/bin/systemextensionsctl', 'list']),
        ('desktop-before', ['/usr/sbin/system_profiler', 'SPDisplaysDataType']),
    ]:
        run(name, arguments)
    for source in ['UIProbe', 'OBSControl', 'CameraProbe']:
        run('compile-' + source, ['xcrun', 'swiftc', '-parse-as-library', str(ROOT / 'Tools/LipCameraProbe' / (source + '.swift')), '-o', str(BIN / source)], timeout=90, required=True)
    (UI_APP / 'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(BIN / 'UIProbe', UI_APP / 'Contents/MacOS/UIProbe')
    shutil.copy2(ROOT / 'Tools/LipCameraProbe/UIProbe-Info.plist', UI_APP / 'Contents/Info.plist')
    run('sign-ui-probe', ['/usr/bin/codesign', '--force', '--sign', '-', str(UI_APP)], required=True)
    run('verify-ui-probe', ['/usr/bin/codesign', '--verify', '--strict', str(UI_APP)], required=True)
    run('ui-probe-requirement', ['/usr/bin/codesign', '-dr', '-', str(UI_APP)], required=True)
    lines = (OUT / 'ui-probe-requirement.log').read_text().splitlines()
    requirements = [line.split('designated => ', 1)[1] for line in lines if 'designated => ' in line]
    if len(requirements) != 1:
        raise RuntimeError('Expected one signed helper designated requirement')
    requirement = OUT / 'ui-probe-requirement.txt'
    requirement.write_text(requirements[0] + '\n')
    csreq = OUT / 'ui-probe.csreq'
    run('compile-ui-probe-requirement', ['/usr/bin/csreq', '-r', str(requirement), '-b', str(csreq)], required=True)
    database = '/Library/Application Support/com.apple.TCC/TCC.db'
    client = 'com.negentropi.LipCameraUIProbe'
    query = "SELECT count(*) FROM access WHERE service='kTCCServiceAccessibility' AND client='" + client + "';"
    preflight = run('ax-grant-preflight', ['sudo', '-n', '/usr/bin/sqlite3', database, query])
    if preflight == 0 and (OUT / 'ax-grant-preflight.log').read_text().strip() == '0':
        sql = "INSERT INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('kTCCServiceAccessibility','" + client + "',0,2,4,1,X'" + csreq.read_bytes().hex() + "',0,'UNUSED',0);"
        granted = run('provision-helper-accessibility', ['sudo', '-n', '/usr/bin/sqlite3', database, sql]) == 0
        summary['testHelperAccessibilityGrantInstalled'] = granted
        if granted:
            run('refresh-user-tcc-cache', ['/usr/bin/killall', 'tccd'])
            run('refresh-system-tcc-cache', ['sudo', '-n', '/usr/bin/killall', 'tccd'])
            time.sleep(2)
    else:
        summary['testHelperAccessibilityGrantInstalled'] = False
        summary['accessibilityProvisioningBlocker'] = 'Scoped test-host TCC write unavailable or helper row unexpectedly pre-existing; existing grants preserved'
    ui('helper-accessibility-check')
    helper = json.loads((OUT / 'helper-accessibility-check.json').read_text())
    summary['testHelperAccessibilityTrusted'] = helper.get('accessibilityTrusted', False)
    dmg = OUT / 'OBS.dmg'
    run('download-obs', ['curl', '--fail', '--location', '--retry', '2', '--max-time', '180', OBS_URL, '-o', str(dmg)], timeout=200, required=True)
    assert digest(dmg) == OBS_SHA, 'OBS publisher asset SHA mismatch'
    (OUT / 'download-provenance.json').write_text(json.dumps({'obs': {'url': OBS_URL, 'sha256': OBS_SHA}, 'fixture': {'url': FIXTURE_URL, 'sha256': FIXTURE_SHA}}, indent=2))
    mount = OUT / 'obs-mount'
    mount.mkdir(exist_ok=True)
    run('mount-obs', ['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(dmg)], timeout=30, required=True)
    mounted = True
    installed = Path('/Applications/OBS.app')
    if installed.exists():
        raise RuntimeError('Existing OBS installation is not a disposable probe-owned target')
    run('install-obs', ['/usr/bin/ditto', str(mount / 'OBS.app'), str(installed)], timeout=60, required=True)
    run('verify-obs', ['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=4', str(installed)], required=True)
    run('assess-obs', ['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=4', str(installed)], required=True)
    run('obs-signature', ['/usr/bin/codesign', '-dv', '--verbose=4', str(installed)])
    extension = installed / 'Contents/Library/SystemExtensions/com.obsproject.obs-studio.mac-camera-extension.systemextension'
    run('extension-signature', ['/usr/bin/codesign', '-dv', '--verbose=4', str(extension)])
    run('verify-extension', ['/usr/bin/codesign', '--verify', '--strict', '--verbose=4', str(extension)], required=True)
    original = OUT / 'public-original.flv'
    silent = OUT / 'public-silent.mp4'
    run('download-fixture', ['curl', '--fail', '--location', '--retry', '2', '--max-time', '90', FIXTURE_URL, '-o', str(original)], timeout=100, required=True)
    assert digest(original) == FIXTURE_SHA, 'Public fixture SHA mismatch'
    if shutil.which('ffmpeg') is None:
        run('install-ffmpeg', ['brew', 'install', 'ffmpeg'], timeout=420, required=True)
    run('prepare-silent-fixture', ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(original), '-map', '0:v:0', '-an', '-vf', 'scale=640:480,fps=25', '-c:v', 'libx264', '-crf', '0', '-pix_fmt', 'yuv420p', str(silent)], required=True)
    run('silent-fixture-streams', ['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(silent)], required=True)
    config = Path.home() / 'Library/Application Support/obs-studio'
    if config.exists():
        raise RuntimeError('Existing OBS configuration is not probe-owned')
    websocket = config / 'plugin_config/obs-websocket/config.json'
    websocket.parent.mkdir(parents=True)
    websocket.write_text(json.dumps({'server_enabled': True, 'server_port': 4455, 'auth_required': True, 'server_password': uuid.uuid4().hex, 'first_load': False, 'alerts_enabled': False}))
    websocket.chmod(0o600)
    (config / 'global.ini').write_text('[General]\nFirstRun=true\nEnableAutoUpdates=false\n\n[Basic]\nProfile=RJTLipProof\nProfileDir=RJTLipProof\nSceneCollection=RJTLipProof\nSceneCollectionFile=RJTLipProof\n')
    profile = config / 'basic/profiles/RJTLipProof'
    profile.mkdir(parents=True)
    (profile / 'basic.ini').write_text('[General]\nName=RJTLipProof\n\n[Video]\nBaseCX=640\nBaseCY=480\nOutputCX=640\nOutputCY=480\nFPSType=0\nFPSCommon=25\n\n[Audio]\nDesktopDevice1=disabled\nDesktopDevice2=disabled\nAuxDevice1=disabled\nAuxDevice2=disabled\nAuxDevice3=disabled\nAuxDevice4=disabled\n')
    run('open-obs', ['/usr/bin/open', '-a', str(installed), '--args', '--profile', 'RJTLipProof', '--disable-updater'])
    started_obs = True
    time.sleep(8)
    ui('obs-first-ui')
    screenshot('obs-first')
    run('configure-and-request-camera', [str(BIN / 'OBSControl'), str(websocket), str(silent), str(OUT / 'obs-control-first.json')], timeout=25)
    time.sleep(3)
    run('extensions-requested', ['/usr/bin/systemextensionsctl', 'list'])
    screenshot('extension-request')
    run('open-extension-settings', ['/usr/bin/open', 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension'])
    for attempt in range(4):
        ui('approval-' + str(attempt), approve=True)
        screenshot('approval-' + str(attempt))
        report = json.loads((OUT / ('approval-' + str(attempt) + '.json')).read_text())
        if report.get('authenticationRequired') or not report.get('accessibilityTrusted'):
            break
        time.sleep(2)
    run('extensions-after-approval', ['/usr/bin/systemextensionsctl', 'list'])
    run('retry-camera', [str(BIN / 'OBSControl'), str(websocket), str(silent), str(OUT / 'obs-control-retry.json')], timeout=20)
    app = OUT / 'LipCameraProbe.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(BIN / 'CameraProbe', app / 'Contents/MacOS/LipCameraProbe')
    shutil.copy2(ROOT / 'Tools/LipCameraProbe/CameraProbe-Info.plist', app / 'Contents/Info.plist')
    run('sign-camera-probe', ['/usr/bin/codesign', '--force', '--sign', '-', str(app)], required=True)
    run('verify-camera-probe', ['/usr/bin/codesign', '--verify', '--strict', str(app)], required=True)
    probe_process = subprocess.Popen(['/usr/bin/open', '-W', '-n', str(app), '--args', '--report-directory', str(OUT)])
    for attempt in range(8):
        time.sleep(2)
        ui('capture-permission-' + str(attempt), approve=True)
        if probe_process.poll() is not None:
            break
    try:
        probe_process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        summary['events'].append({'operation': 'camera-app', 'error': 'did not exit before deadline'})
        probe_process.terminate()
    screenshot('final-desktop')
    camera_path = OUT / 'camera.json'
    if camera_path.exists():
        camera = json.loads(camera_path.read_text())
        summary['camera'] = camera
        if camera.get('status') == 'supportedDeviceReady' and camera.get('cameraClosed') and camera.get('audioInputCount') == 0:
            summary['status'] = 'supportedDeviceReady'
except Exception as error:
    summary['failure'] = str(error)
finally:
    if started_obs:
        run('obs-log-copy', ['/bin/cp', '-R', str(Path.home() / 'Library/Application Support/obs-studio/logs'), str(OUT / 'obs-logs')])
        run('close-obs', ['/usr/bin/osascript', '-e', 'tell application id "com.obsproject.obs-studio" to quit'], timeout=12)
    run('extensions-final', ['/usr/bin/systemextensionsctl', 'list'])
    run('extension-events', ['/usr/bin/log', 'show', '--last', '6m', '--style', 'compact', '--predicate', 'process == "sysextd" AND eventMessage CONTAINS[c] "obsproject"'], timeout=25)
    if mounted:
        run('unmount-obs', ['/usr/bin/hdiutil', 'detach', str(OUT / 'obs-mount')], timeout=15)
    (OUT / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output, 'a') as stream:
            stream.write('camera_status=' + summary['status'] + '\n')
