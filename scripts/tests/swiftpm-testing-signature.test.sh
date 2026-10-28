#!/usr/bin/env bash
set -euo pipefail

proof() {
  python3 - "$@" <<'PY'
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

NAME = 'SignaturePreparation'
CASE = 'signaturePreparationRunsStandardSwiftTesting'
FAILURE = 'code has no resources but signature indicates they must be present'
MANIFEST = '// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: "SignaturePreparation", platforms: [.macOS(.v14)], targets: [.testTarget(name: "SignaturePreparationTests", resources: [.process("signed-resource.txt")])], swiftLanguageVersions: [.v5])\n'
RESOURCE = 'RJT signed-resource\nliteral e\u0301 台北 👩🏽‍💻\n'.encode('utf-8')
TEST = 'import Foundation\nimport Testing\n@Test func signaturePreparationRunsStandardSwiftTesting() throws {\n    let url = try #require(Bundle.module.url(forResource: "signed-resource", withExtension: "txt"))\n    let actual = try Data(contentsOf: url)\n    #expect(actual == Data([' + ', '.join(str(value) for value in RESOURCE) + ']))\n}\n'
digest = lambda data: hashlib.sha256(data).hexdigest()
def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def files(root):
    return {str(path.relative_to(root)): digest(path.read_bytes()) for path in sorted(root.rglob('*')) if path.is_file()}
def native_pregate(code, stdout, stderr, bundle):
    return code != 0 and not stdout.strip() and stderr.strip() == bundle + ': ' + FAILURE
def classify(log, code, before, after):
    started = re.findall(r'^◇ Test (\S+)\(\) started\.$', log, re.M)
    passed = re.findall(r'^✔ Test (\S+)\(\) passed after [^\r\n]+\.$', log, re.M)
    summaries = re.findall(r'^✔ Test run with (\d+) tests?(?: in \d+ suites?)? passed after [^\r\n]+\.$', log, re.M)
    bad = re.findall(r'^.*(?:✘|↷|recorded an issue|recorded \d+ issues?|\bskipped\b|\berror:).*$' , log, re.M)
    events = [line for line in log.splitlines() if re.match(r'^[◇✔✘↷] Test ', line) and not re.match(r'^[◇✔] Test run ', line)]
    expected_events = ['◇ Test ' + CASE + '() started.'] + re.findall(r'^✔ Test ' + CASE + r'\(\) passed after [^\r\n]+\.$', log, re.M)
    valid = code == 0 and started == passed == [CASE] and events == expected_events and log.count('◇ Test run started.') == 1 and summaries == ['1'] and not bad and before == after
    return {'valid': valid, 'started': started, 'passed': passed, 'summaries': summaries, 'failureLines': bad}
command, *args = sys.argv[1:]
if command == 'self-test':
    good = '◇ Test run started.\n◇ Test ' + CASE + '() started.\n✔ Test ' + CASE + '() passed after 0.001 seconds.\n✔ Test run with 1 test passed after 0.001 seconds.\n'
    fixtures = {'pass': classify(good, 0, {'a': 'x'}, {'a': 'x'})['valid'], 'nonzero': classify(good, 1, {}, {})['valid'], 'zero': classify(good.replace('with 1 test', 'with 0 tests'), 0, {}, {})['valid'], 'extra': classify(good + '◇ Test foreign() started.\n', 0, {}, {})['valid'], 'quoted-extra': classify(good + '◇ Test "foreign" started.\n', 0, {}, {})['valid'], 'skip': classify(good + '↷ Test skipped.\n', 0, {}, {})['valid'], 'issue': classify(good + '✘ Test recorded an issue.\n', 0, {}, {})['valid'], 'changed-bytes': classify(good, 0, {'a': 'x'}, {'a': 'y'})['valid'], 'changed-external-resource': classify(good, 0, {'resourceBundleManifests': {'fixture.bundle': {'signed-resource.txt': 'before'}}}, {'resourceBundleManifests': {'fixture.bundle': {'signed-resource.txt': 'after'}}})['valid']}
    fixture_bundle = '/owned/SignaturePreparationPackageTests.xctest'
    known = fixture_bundle + ': ' + FAILURE + '\n'
    pregates = {'known-resource-error': native_pregate(1, '', known, fixture_bundle), 'pre-green': native_pregate(0, '', '', fixture_bundle), 'unrelated-error': native_pregate(1, '', 'unrelated failure', fixture_bundle), 'mixed-error': native_pregate(1, '', known + 'unrelated failure\n', fixture_bundle)}
    assert fixtures['pass'] and not any(value for key, value in fixtures.items() if key != 'pass') and pregates['known-resource-error'] and not any(value for key, value in pregates.items() if key != 'known-resource-error'), (fixtures, pregates)
    print(json.dumps({'valid': True, 'fixtures': fixtures, 'nativePregateFixtures': pregates}, indent=2))
elif command == 'prepare':
    root, script = map(Path, args)
    package = root / 'package'
    target = package / 'Tests/SignaturePreparationTests'
    target.mkdir(parents=True)
    (package / 'Package.swift').write_text(MANIFEST)
    (target / 'SignaturePreparationTests.swift').write_text(TEST)
    (target / 'signed-resource.txt').write_bytes(RESOURCE)
    write(root / 'source-contract.json', {'scriptPath': str(script), 'scriptSHA256': digest(script.read_bytes()), 'manifestSHA256': digest(MANIFEST.encode()), 'testSHA256': digest(TEST.encode()), 'resourceSHA256': digest(RESOURCE), 'testCensus': files(package / 'Tests')})
elif command == 'snapshot':
    root, bundle, label = Path(args[0]), Path(args[1]), args[2]
    package = root / 'package'
    expected = (Path((root / 'bin-path.txt').read_text().strip()) / (NAME + 'PackageTests.xctest')).resolve()
    if bundle.resolve() != expected or not bundle.resolve().is_relative_to(package.resolve()) or bundle.is_symlink(): raise SystemExit('Test bundle is not the exact owned SwiftPM product')
    executable = bundle / ('Contents/MacOS/' + NAME + 'PackageTests')
    contract = json.loads((root / 'source-contract.json').read_text())
    if digest(Path(contract['scriptPath']).read_bytes()) != contract['scriptSHA256'] or digest((package / 'Package.swift').read_bytes()) != contract['manifestSHA256'] or files(package / 'Tests') != contract['testCensus']: raise SystemExit('Generated compiler inputs or calibration driver changed')
    resources = {path.name: files(path) for path in sorted(bundle.parent.glob('*.bundle')) if path.is_dir()}
    copied_resource_hashes = [value for entries in resources.values() for path, value in entries.items() if Path(path).name == 'signed-resource.txt']
    if copied_resource_hashes != [contract['resourceSHA256']]: raise SystemExit('SwiftPM did not preserve the exact processed input resource')
    value = {'bundle': str(bundle), 'executable': str(executable), 'machOSHA256': digest(executable.read_bytes()), 'bundleManifest': files(bundle), 'resourceBundleManifests': resources, 'sourceContract': contract}
    write(root / (label + '-bundle.json'), value)
elif command == 'pregate':
    root = Path(args[0])
    code = int((root / 'native-verify-exit.txt').read_text())
    bundle = json.loads((root / 'native-bundle.json').read_text())['bundle']
    valid = native_pregate(code, (root / 'native-verify-stdout.log').read_text(), (root / 'native-verify-stderr.log').read_text(), bundle) and int((root / 'native-display-exit.txt').read_text()) == 0
    write(root / 'native-pregate.json', {'valid': valid, 'exitCode': code, 'expectedFailure': FAILURE, 'stdout': (root / 'native-verify-stdout.log').read_text(), 'stderr': (root / 'native-verify-stderr.log').read_text()})
    if not valid: raise SystemExit('Native SwiftPM signature did not reproduce the exact known resource failure')
elif command == 'classify':
    root = Path(args[0])
    before, after = [json.loads((root / (label + '-bundle.json')).read_text()) for label in ['prepared', 'after']]
    result = classify((root / 'tests.log').read_text(), int((root / 'test-exit.txt').read_text()), before, after)
    result['valid'] = result['valid'] and all(int((root / name).read_text()) == 0 for name in ['sign-exit.txt', 'prepared-verify-exit.txt', 'after-verify-exit.txt', 'prepared-display-exit.txt', 'after-display-exit.txt']) and json.loads((root / 'native-pregate.json').read_text())['valid'] is True
    result['valid'] = result['valid'] and all((root / ('prepared-display-' + channel + '.log')).read_bytes() == (root / ('after-display-' + channel + '.log')).read_bytes() for channel in ['stdout', 'stderr'])
    result.update(classification='passed-signing-preparation-calibration' if result['valid'] else 'invalid-or-failed', scope='Test harness signing preparation only. Native resource-signature failure, one explicit whole-bundle ad-hoc sign, strict verification and one standard Swift Testing case loading the exact processed Bundle.module resource. No Clarity feature proof.')
    write(root / 'result.json', result)
    print(json.dumps(result, indent=2))
    if not result['valid']: raise SystemExit(1)
else:
    raise SystemExit('Unknown proof operation')
PY
}

if [[ "${1:-}" == --self-test ]]; then
  proof self-test
  exit
fi
if [[ "$#" != 0 || "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin || "$(id -u)" == 0 ]]; then
  echo "Native calibration requires a fresh non-root GitHub-hosted Mac. Use --self-test locally." >&2
  exit 2
fi
script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
out="$RUNNER_TEMP/swiftpm-testing-signature-check"
test ! -e "$out"
mkdir -m 700 "$out"
phase=prepare
trap 'code=$?; if [[ "$code" != 0 ]]; then printf "{\"valid\":false,\"phase\":\"%s\",\"exitCode\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi' EXIT
{
  xcodebuild -version
  swift --version
  sw_vers
  uname -m
  shasum -a 256 "$script"
} > "$out/toolchain.log" 2>&1
proof prepare "$out" "$script"
args=(--package-path "$out/package" --configuration debug)
phase=build
xcrun swift build "${args[@]}" --build-tests > "$out/build.log" 2>&1
xcrun swift build "${args[@]}" --show-bin-path > "$out/bin-path.txt" 2>> "$out/build.log"
bundle="$(cat "$out/bin-path.txt")/SignaturePreparationPackageTests.xctest"
capture() {
  local label="$1"
  shift
  local observed_exit=0
  "$@" > "$out/$label-stdout.log" 2> "$out/$label-stderr.log" || observed_exit=$?
  printf '%s\n' "$observed_exit" > "$out/$label-exit.txt"
}
phase=native-pregate
proof snapshot "$out" "$bundle" native
capture native-display codesign --display --verbose=4 "$bundle"
capture native-verify codesign --verify --deep --strict "$bundle"
proof pregate "$out"
phase=prepare-signature
capture sign codesign --sign - --force --timestamp=none "$bundle"
capture prepared-display codesign --display --verbose=4 "$bundle"
capture prepared-verify codesign --verify --deep --strict "$bundle"
proof snapshot "$out" "$bundle" prepared
test "$(cat "$out/sign-exit.txt")" = 0
test "$(cat "$out/prepared-verify-exit.txt")" = 0
phase=standard-testing
capture test xcrun swift test "${args[@]}" --skip-build --enable-swift-testing --disable-xctest --no-parallel
cat "$out/test-stdout.log" "$out/test-stderr.log" > "$out/tests.log"
phase=verify
capture after-display codesign --display --verbose=4 "$bundle"
capture after-verify codesign --verify --deep --strict "$bundle"
proof snapshot "$out" "$bundle" after
phase=classify
proof classify "$out"
