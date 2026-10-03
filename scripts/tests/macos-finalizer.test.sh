#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$root" <<'PY'
from datetime import datetime, timezone
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

root = Path(sys.argv[1])
scratch = Path(tempfile.mkdtemp(prefix='roma-macos-finalizer-'))
team = 'ABCDE12345'
source_sha = '1' * 40
tooling_sha = '2' * 40
certificate = b'controlled public certificate fixture'
identity = hashlib.sha1(certificate).hexdigest().upper()
uuid = '12345678-1234-1234-1234-123456789ABC'
bundle = 'com.negentropi.RomaJustTalk'
source_policy = plistlib.loads((root / 'VoiceInk/VoiceInk.entitlements').read_bytes())
claims = json.loads(json.dumps(source_policy).replace('$(PRODUCT_BUNDLE_IDENTIFIER)', bundle).replace('$(AppIdentifierPrefix)', team + '.'))
claims['com.apple.developer.aps-environment'] = 'production'
claims.update({'com.apple.application-identifier': team + '.' + bundle, 'com.apple.developer.team-identifier': team,
               'com.apple.developer.icloud-container-environment': 'Production'})
profile = {'UUID': uuid, 'TeamIdentifier': [team], 'ProvisionsAllDevices': True, 'Platform': ['OSX'],
           'ApplicationIdentifierPrefix': [team], 'ExpirationDate': datetime(2030, 1, 1),
           'DeveloperCertificates': [certificate], 'Entitlements': {key: value for key, value in claims.items() if not key.startswith('com.apple.security.')}}
profile_file = scratch / (uuid + '.provisionprofile')
profile_file.write_bytes(plistlib.dumps(profile))
(scratch / 'claims.plist').write_bytes(plistlib.dumps(claims))
settings = {'CONFIGURATION': 'Release', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'ENABLE_NATIVE_SPEECH_ANALYZER',
            'CODE_SIGN_ENTITLEMENTS': 'VoiceInk/VoiceInk.entitlements', 'CODE_SIGNING_ALLOWED': 'NO', 'ARCHS': 'arm64',
            'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'MACOSX_DEPLOYMENT_TARGET': '14.2.1'}
app = scratch / 'payload/roma.production.xcarchive/Products/Applications/roma just talk.app'
(app / 'Contents/MacOS').mkdir(parents=True)
(app / 'Contents/Resources').mkdir()
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'roma just talk',
                                                     'LSMinimumSystemVersion': '14.2.1', 'CFBundleShortVersionString': '0.0.0', 'CFBundleVersion': '1'}))
(app / 'Contents/MacOS/roma just talk').write_bytes(bytes.fromhex('cffaedfe') + b'controlled native image fixture')
(app / 'Contents/MacOS/roma just talk').chmod(0o755)
(app / 'Contents/Resources/source.txt').write_text('immutable resource')


def package(directory, archive):
    with zipfile.ZipFile(archive, 'w') as output:
        for path in sorted(directory.rglob('*')):
            name = path.relative_to(directory).as_posix()
            item = zipfile.ZipInfo(name + ('/' if path.is_dir() else ''))
            item.external_attr = (stat.S_IFDIR | 0o755 if path.is_dir() else stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)) << 16
            output.writestr(item, b'' if path.is_dir() else path.read_bytes())


archive_inner = scratch / 'roma.production.xcarchive.zip'
package(scratch / 'payload', archive_inner)


def source_transport(mode):
    path = scratch / (mode + '-source.zip')
    actual = dict(settings)
    if mode == 'local-build':
        actual['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] += ' LOCAL_BUILD'
    inner = archive_inner
    if mode == 'dot-archive-root':
        inner = scratch / 'dot-archive-root.zip'
        with zipfile.ZipFile(inner, 'w') as archive:
            archive.writestr('.', b'')
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED if mode == 'corrupt-deflate' else zipfile.ZIP_STORED) as archive:
        archive.write(inner, 'roma.production.xcarchive.zip')
        archive.writestr('build-settings.json', json.dumps([{'target': 'VoiceInk', 'buildSettings': actual}]))
        archive.writestr('source-sha.txt', source_sha + '\n')
        archive.writestr('xcode.txt', 'Xcode 26.6\nBuild version 17F113\n')
        archive.writestr('swift.txt', 'controlled compiler receipt\n')
        archive.writestr('app-info.plist', (app / 'Contents/Info.plist').read_bytes())
        archive.writestr('archive.log', 'controlled archive command output\n')
        archive.writestr('BOUNDARY.txt', 'Unsigned production archive, no qualification\n')
        archive.writestr('Package.resolved', (root / 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_bytes())
        archive.writestr('whisper-source-sha.txt', '60c0be6ac8fa71b1a2ae2dd938a31a34a508e774\n')
        manifest = scratch / 'fixture-app-manifest.txt'
        completed = subprocess.run(['bash', '-c', 'source "$1"; write_macos_bundle_manifest "$2" "$3"', '_',
                                    str(root / 'scripts/macos-bundle-manifest.sh'), str(app), str(manifest)], check=True)
        archive.writestr('unsigned-app-files.sha256', manifest.read_bytes())
    if mode in ('corrupt-deflate', 'unsupported-compression'):
        with zipfile.ZipFile(path) as archive:
            offset = archive.getinfo('roma.production.xcarchive.zip').header_offset
            central_offset = archive.start_dir
        with path.open('r+b') as stream:
            if mode == 'unsupported-compression':
                stream.seek(offset + 8)
                stream.write((99).to_bytes(2, 'little'))
                stream.seek(central_offset + 10)
                stream.write((99).to_bytes(2, 'little'))
            else:
                stream.seek(offset)
                header = stream.read(30)
                offset += 30 + int.from_bytes(header[26:28], 'little') + int.from_bytes(header[28:30], 'little')
                stream.seek(offset)
                first = stream.read(1)[0]
                stream.seek(offset)
                stream.write(bytes([(first & ~6) | 6]))
    return path


bin_dir = scratch / 'bin'
bin_dir.mkdir()
stub = bin_dir / 'transport.py'
stub.write_text(r'''#!/usr/bin/env python3
import base64, hashlib, json, os, plistlib, shutil, stat, sys, zipfile
from pathlib import Path
name=Path(sys.argv[0]).name; args=sys.argv[1:]; mode=os.environ['FINALIZER_CASE']
root=Path(os.environ['FINALIZER_ROOT']); source=Path(os.environ['FINALIZER_SOURCE']); scratch=Path(os.environ['FINALIZER_SCRATCH'])
team='ABCDE12345'; sha='1'*40; tooling='2'*40; bundle='com.negentropi.RomaJustTalk'
def emit(value): print(json.dumps(value))
if name=='git': print(tooling)
elif name=='gh':
 endpoint=args[-1].removeprefix('repos/negentropi/roma-just-talk/')
 if endpoint.startswith('contents/'):
  relative=endpoint[9:].split('?')[0]; data=(root/relative).read_bytes()
  if mode=='tooling-source-mismatch' and relative.endswith('finalize-notarized-macos-app.sh'): data+=b'changed'
  emit({'encoding':'base64','content':base64.b64encode(data).decode()})
 elif endpoint.endswith('/zip'): sys.stdout.buffer.write(source.read_bytes())
 elif endpoint.startswith('actions/artifacts/'):
  value={'id':300,'name':'roma.macos.unsigned-production-archive','expired':False,'created_at':'2026-10-03T12:02:00Z',
         'workflow_run':{'id':100,'head_sha':sha},'size_in_bytes':source.stat().st_size,'digest':'sha256:'+hashlib.sha256(source.read_bytes()).hexdigest()}
  if mode=='transport-mismatch': value['digest']='sha256:'+'0'*64
  if mode=='evidence-only-artifact': value['name']='roma.macos.production-compile-evidence'
  if mode=='wrong-artifact-attempt': value['created_at']='2026-10-03T11:00:00Z'
  emit(value)
 elif '/jobs?' in endpoint:
  producer='/900/' in endpoint
  job={'id':901 if producer else 101,'run_id':900 if producer else 100,'run_attempt':1,
       'name':'Finalize notarized macOS app' if producer else 'Compile Release without local behavior',
       'status':'in_progress' if producer else 'completed','conclusion':None if producer else 'success',
       'runner_id':42,'runner_name':'GitHub Actions 42','runner_group_name':'GitHub Actions','labels':['macos-26'],
       'started_at':'2026-10-03T12:00:00Z','completed_at':'2026-10-03T12:10:00Z'}
  if mode=='wrong-job-attempt' and not producer: job['run_attempt']=2
  emit({'total_count':1,'jobs':[job]})
 else:
  producer=endpoint.endswith('/900')
  value={'id':900 if producer else 100,'run_attempt':1,'repository':{'full_name':'negentropi/roma-just-talk'},
         'head_repository':{'full_name':'negentropi/roma-just-talk'},'head_sha':tooling if producer else sha,
         'path':'.github/workflows/qualify-macos-distribution.yml' if producer else '.github/workflows/macos-production-compile-check.yml',
         'event':'workflow_dispatch','pull_requests':[],'status':'in_progress' if producer else 'completed','conclusion':None if producer else 'success'}
  if mode=='source-run-incomplete' and not producer: value['status']='in_progress'; value['conclusion']=None
  if mode=='wrong-source-workflow' and not producer: value['path']='.github/workflows/voiceink-build.yml'
  emit(value)
elif name=='xcodebuild':
 if args==['-version']: print('Xcode 26.6\nBuild version 17F113')
 else:
  if mode=='export-fail': sys.exit(65)
  app=Path(args[args.index('-archivePath')+1])/'Products/Applications/roma just talk.app'
  output=Path(args[args.index('-exportPath')+1]); output.mkdir()
  target=output/app.name; shutil.copytree(app,target)
  shutil.copyfile(os.environ['FINALIZER_PROFILE'],target/'Contents/embedded.provisionprofile')
  if mode=='bundle-mutation': (target/'Contents/Resources/source.txt').write_text('changed during export')
elif name=='security':
 if args[0]=='find-identity':
  if mode!='no-key': print('1) '+os.environ['FINALIZER_IDENTITY']+' "Developer ID Application: Fixture ('+('WRONG12345' if mode=='wrong-team' else team)+')"')
 else: sys.stdout.buffer.write(Path(args[-1]).read_bytes())
elif name=='codesign':
 if '--entitlements' in args:
  claims=plistlib.loads((scratch/'claims.plist').read_bytes())
  if mode=='local-entitlement': claims['com.apple.security.cs.disable-library-validation']=True
  sys.stdout.buffer.write(plistlib.dumps(claims))
 elif args[0]=='--display':
  print('Executable='+args[-1]+'/Contents/MacOS/roma just talk',file=sys.stderr)
  print('CodeDirectory v=20500 flags=0x10000(runtime)\nTeamIdentifier=ABCDE12345\nIdentifier='+bundle,file=sys.stderr)
 elif mode=='nested-signature-fail' and args[0]=='--verify': sys.exit(1)
elif name=='lipo': print('arm64')
elif name=='otool': print('Load command 0\n cmd LC_SEGMENT_64\nLoad command 1\n cmd LC_BUILD_VERSION\n platform 1\n minos 14.2.1')
elif name=='spctl':
 print(args[-1]+': accepted'); print('source=Notarized Developer ID')
 if mode=='gatekeeper-override': print('override=security disabled')
elif name=='xcrun':
 if args[:2]==['notarytool','submit']:
  (scratch/'submission-digest.txt').write_text(hashlib.sha256(Path(args[2]).read_bytes()).hexdigest())
  if mode=='notary-bundle-mutation':
   target=Path(args[2]).parent/'export/roma just talk.app/Contents/Resources/source.txt'
   target.write_text('changed while notarizing')
  emit({'status':'Invalid' if mode=='notary-fail' else 'Accepted','id':'87654321-4321-4321-4321-CBA987654321'})
 elif args[:2]==['notarytool','log']:
  emit({'jobId':args[2],'status':'Accepted','sha256':('0'*64 if mode=='notary-log-mismatch' else (scratch/'submission-digest.txt').read_text())})
 elif args[:2]==['stapler','validate']:
  print('The validate action worked!')
  if mode=='stapler-fail': sys.exit(1)
 elif args[:2]==['stapler','staple']: print('The staple action worked!')
 else: sys.exit(1)
elif name=='ditto':
 if args[:2]==['-x','-k']:
  output=Path(args[-1]); output.mkdir()
  with zipfile.ZipFile(args[-2]) as archive:
   archive.extractall(output)
   for item in archive.infolist():
    path=output/item.filename
    path.chmod(stat.S_IMODE(item.external_attr>>16) or (0o755 if item.is_dir() else 0o644))
  sys.exit(0)
 app=Path(args[-2]); output=Path(args[-1])
 if mode=='package-mutation' and output.name=='final-pending.zip': (app/'Contents/Resources/source.txt').write_text('changed while packaging')
 with zipfile.ZipFile(output,'w') as archive:
  for path in sorted([app,*app.rglob('*')]):
   relative=path.relative_to(app.parent).as_posix()
   item=zipfile.ZipInfo(relative+('/' if path.is_dir() else ''))
   item.external_attr=(stat.S_IFDIR|stat.S_IMODE(path.stat().st_mode) if path.is_dir() else stat.S_IFREG|stat.S_IMODE(path.stat().st_mode))<<16
   archive.writestr(item,b'' if path.is_dir() else path.read_bytes())
else: sys.exit('Unexpected controlled command '+name)
''')
stub.chmod(0o755)
for command in ('gh', 'git', 'security', 'xcodebuild', 'codesign', 'lipo', 'otool', 'spctl', 'xcrun', 'ditto'):
    (bin_dir / command).symlink_to(stub.name)


def run(mode, archive=None):
    output = scratch / (mode + '-output')
    environment = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], GITHUB_REPOSITORY='negentropi/roma-just-talk',
                       GITHUB_SHA=tooling_sha, GITHUB_RUN_ID='900', GITHUB_RUN_ATTEMPT='1', FINALIZER_CASE=mode,
                       FINALIZER_ROOT=str(root), FINALIZER_SOURCE=str(archive or source_transport(mode)), FINALIZER_PROFILE=str(profile_file),
                       FINALIZER_SCRATCH=str(scratch), FINALIZER_IDENTITY=identity)
    argv = ['bash', str(root / 'scripts/finalize-notarized-macos-app.sh'), '--source-run-id', '100', '--source-run-attempt', '1',
            '--source-artifact-id', '300', '--expected-source-sha', source_sha, '--expected-tooling-sha', tooling_sha,
            '--developer-id-team', team, '--signing-identity-sha1', identity, '--provisioning-profile', str(profile_file),
            '--notary-keychain-profile', 'controlled-existing-profile', '--output-dir', str(output)]
    result = subprocess.run(argv, env=environment, capture_output=True, text=True, timeout=90)
    (scratch / (mode + '.stdout')).write_text(result.stdout)
    (scratch / (mode + '.stderr')).write_text(result.stderr)
    receipt = json.loads((output / 'finalization-result.json').read_text())
    records = json.loads((output / 'command-receipts/commands.json').read_text())
    return result, receipt, records, output


result, receipt, records, output = run('controlled-accepted')
assert result.returncode == 0 and receipt['state'] == 'finalized', (receipt, result.stderr)
assert receipt['publicationEligible'] is False
assert receipt['finalArchive']['sha256'] == hashlib.sha256((output / 'roma.just.talk.app.zip').read_bytes()).hexdigest()
trust = json.loads((output / 'final-trust/trust-command-receipts.json').read_text())
assert [record['name'] for record in trust['commands']] == ['codesign-verify', 'codesign-display', 'stapler-validate', 'gatekeeper-assess']
assert all(record['exitStatus'] == 0 and not record['timedOut'] for record in records + trust['commands'])
assert all('--allowProvisioningUpdates' not in record['argv'] and '--sign' not in record['argv'] for record in records)

expectations = {
    'no-key': 'Exact existing Developer ID identity', 'wrong-team': 'Exact existing Developer ID identity',
    'bundle-mutation': 'Export changed unsigned bundle content', 'package-mutation': 'App mutated during final packaging',
    'notary-fail': 'Notarization did not accept', 'notary-log-mismatch': 'Notary log is not bound',
    'notary-bundle-mutation': 'Notarization or stapling changed unsigned bundle content',
    'local-build': 'Not an unsigned production', 'local-entitlement': 'Exported production entitlements differ',
    'source-run-incomplete': 'Whole workflow', 'wrong-source-workflow': 'Run identity', 'wrong-job-attempt': 'Job attempt',
    'transport-mismatch': 'Source transport', 'wrong-artifact-attempt': 'Production source artifact',
    'corrupt-deflate': 'error', 'unsupported-compression': 'Unsupported archive compression',
    'dot-archive-root': 'Unsafe or duplicate archive member',
    'evidence-only-artifact': 'Production source artifact', 'tooling-source-mismatch': 'Local tooling differs',
    'export-fail': 'Command failed', 'nested-signature-fail': 'Command failed', 'stapler-fail': 'Command failed', 'gatekeeper-override': 'Command failed',
}
for mode, reason in expectations.items():
    result, receipt, records, output = run(mode)
    assert result.returncode != 0 and receipt['state'] == 'blocked' and receipt['publicationEligible'] is False, (mode, receipt)
    assert reason in receipt['reason'], (mode, receipt, result.stderr)
    assert not (output / 'roma.just.talk.app.zip').exists(), mode
    if mode in ('no-key', 'wrong-team'):
        assert not any(record['name'] == 'developer-id-export' for record in records)
    if mode in ('notary-fail', 'notary-log-mismatch'):
        assert not any(record['name'] == 'staple-ticket' for record in records)
    if mode in ('corrupt-deflate', 'unsupported-compression', 'dot-archive-root'):
        assert not any(record['name'] == 'available-identities' for record in records)
        if mode != 'dot-archive-root':
            assert records[-1]['name'] == 'source-download'

recorded = os.environ.get('RJT_FINALIZER_RECORDED_SOURCE_ARCHIVE')
if recorded:
    result, receipt, records, output = run('recorded-unqualified', Path(recorded))
    assert result.returncode != 0 and receipt['publicationEligible'] is False and not (output / 'roma.just.talk.app.zip').exists()
    assert not any(record['name'] == 'available-identities' for record in records), receipt

print(json.dumps({'state': 'controlled-tests-passed', 'cases': 1 + len(expectations) + bool(recorded),
                  'signedNotarizedDistributionProved': False, 'recordedSourceRejected': bool(recorded), 'evidenceDirectory': str(scratch)}))
PY
