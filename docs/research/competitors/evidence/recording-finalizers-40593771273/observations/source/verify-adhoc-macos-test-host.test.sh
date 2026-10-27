#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$repo" <<'PY'
import json
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
helper = repo / "scripts/verify-adhoc-macos-test-host.sh"
with tempfile.TemporaryDirectory(prefix="rjt-test-host-contract-") as temporary:
    root = Path(temporary)
    app = root / "roma just talk.app"
    macos = app / "Contents/MacOS"
    macos.mkdir(parents=True)
    executable = macos / "roma just talk"
    executable.write_text("mock executable, never launched\n")
    executable.chmod(0o755)
    info = app / "Contents/Info.plist"
    info.write_bytes(plistlib.dumps({"CFBundleExecutable": executable.name, "CFBundleIdentifier": "com.negentropi.RomaJustTalk"}))
    binary = root / "bin"
    binary.mkdir()
    code = binary / "codesign"
    code.write_text('''#!/usr/bin/env python3
import os, plistlib, sys
args = sys.argv[1:]
if args[0] == '-dvvv':
    if os.environ.get('MOCK_HOST_SIGNATURE_ERROR') == '1': sys.exit(1)
    print('Executable=' + args[-1], file=sys.stderr)
    print('CodeDirectory v=20500 size=123 flags=' + os.environ.get('MOCK_HOST_FLAGS', '0x2(adhoc)') + ' hashes=12+3 location=embedded', file=sys.stderr)
    print('Signature=' + os.environ.get('MOCK_HOST_SIGNATURE', 'adhoc'), file=sys.stderr)
elif args[:3] == ['-d', '--entitlements', ':-']:
    if os.environ.get('MOCK_HOST_ENTITLEMENTS') == 'malformed': print('invalid entitlement data')
    elif os.environ.get('MOCK_HOST_ENTITLEMENTS') != 'empty':
        sys.stdout.buffer.write(plistlib.dumps({'com.apple.security.cs.disable-library-validation': os.environ.get('MOCK_HOST_VALIDATION', '1') == '1'}))
elif args[:4] == ['--verify', '--deep', '--strict', '--verbose=4']:
    if os.environ.get('MOCK_HOST_DEEP_ERROR') == '1': sys.exit(1)
    print('valid on disk', file=sys.stderr)
else:
    raise SystemExit('Unexpected codesign command or signing mutation: ' + repr(args))
''')
    code.chmod(0o755)
    otool = binary / "otool"
    otool.write_text('''#!/usr/bin/env python3
import os, sys
assert sys.argv[1] == '-L'
print(sys.argv[2] + ':')
print('    /usr/lib/libSystem.B.dylib (compatibility version 1.0.0)')
if os.environ.get('MOCK_HOST_RELATIVE', '1') == '1':
    print('    @rpath/Fixture.framework/Versions/A/Fixture (compatibility version 1.0.0)')
''')
    otool.chmod(0o755)
    successes = 0
    failures = 0
    def run(label, expected, **settings):
        global successes, failures
        evidence = root / label
        environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], **settings)
        result = subprocess.run(['bash', str(helper), str(app), str(evidence)], env=environment, text=True, capture_output=True)
        assert (result.returncode == 0) is expected, (label, result.returncode, result.stdout, result.stderr)
        if expected:
            receipt = json.loads((evidence / 'result.json').read_text())
            assert receipt['classification'] == 'verified-adhoc-macos-test-host'
            assert receipt['signature'] == 'adhoc' and receipt['strict_deep_verification_passed'] is True
            assert receipt['executable_path'] == str(executable)
            assert receipt['raw_code_directory_flags'] == settings.get('MOCK_HOST_FLAGS', '0x2(adhoc)')
            assert 'No signing mutation' in receipt['scope']
            successes += 1
        else:
            assert not (evidence / 'result.json').exists(), label
            failures += 1
    run('xcode-debug-without-runtime', True)
    run('runtime-also-accepted', True, MOCK_HOST_FLAGS='0x10002(adhoc,runtime)')
    run('system-libraries-only', True, MOCK_HOST_RELATIVE='0', MOCK_HOST_ENTITLEMENTS='empty')
    run('developer-id-is-not-this-contract', False, MOCK_HOST_SIGNATURE='Developer ID Application')
    run('missing-library-validation', False, MOCK_HOST_VALIDATION='0')
    run('failed-deep-verification', False, MOCK_HOST_DEEP_ERROR='1')
    run('unreadable-signature', False, MOCK_HOST_SIGNATURE_ERROR='1')
    run('malformed-entitlements', False, MOCK_HOST_ENTITLEMENTS='malformed')
    run('missing-flags', False, MOCK_HOST_FLAGS='')
    run('malformed-nonempty-flags', False, MOCK_HOST_FLAGS='garbage')
    run('invalid-hex-flags', False, MOCK_HOST_FLAGS='0xXYZ(adhoc)')
    stale = root / 'stale-evidence'
    stale.mkdir()
    result = subprocess.run(['bash', str(helper), str(app), str(stale)], text=True, capture_output=True)
    assert result.returncode != 0
    failures += 1
    print(json.dumps({'classification':'mocked-test-host-contract-passed', 'accepted':successes, 'rejected':failures,
        'scope':'Mock codesign/otool responses and fixture metadata only; no native signature, app launch, TCC, microphone or Keychain execution.'}))
PY
