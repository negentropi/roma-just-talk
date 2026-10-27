#!/usr/bin/env bash
set -euo pipefail

proof() {
  python3 - "$@" <<'PY'
import collections
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path

DRIVER = 'scripts/run-clarity-service-check.sh'
WORKFLOW = '.github/workflows/voiceink-clarity-service-check.yml'
LOCK = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
TEST = 'VoiceInkTests/ClarityProviderTests.swift'
TEST_HASH = '85580bed6dda374494026bfd44fccd898dbc04b2cf1e8167e68f0742de03a054'
SERVICE_HASH = '986b0c1fae4a939faec9eed4c46a8c6065f6ed5489a922ed337d88994a06bb98'
SOURCES = [
    'VoiceInk/Services/AIEnhancement/AIService.swift',
    'VoiceInk/Services/AIEnhancement/AIEnhancementService.swift',
    'VoiceInk/Services/AIEnhancement/LocalCLIService.swift',
    'VoiceInk/Services/OllamaService.swift',
    'VoiceInk/Services/APIKeyManager.swift',
    'VoiceInk/Services/KeychainService.swift',
    'VoiceInk/Services/CustomVocabularyService.swift',
    'VoiceInk/Services/ScreenCaptureService.swift',
    'VoiceInk/Services/SelectedTextService.swift',
    'VoiceInk/Models/VocabularyWord.swift',
    'VoiceInk/Notifications/AppNotifications.swift'
]
CASES = [
    'clarityPreservesLiteralProviderJSONAndCodeUnits',
    'claritySameOutputRetainsCapturedRequestMetadata',
    'clarityRejectsMalformedAndBlankProviderResponses',
    'claritySnapshotKeepsCapturedCLICommandAndProvider',
    'claritySnapshotKeepsCapturedCLITimeout',
    'writingActionsRetainLegacyFilteringAndEmptyPolicies',
    'clarityCancellationDoesNotReturnLateOutput'
]
WRAPPER = 'import Testing\n@Suite(.serialized) struct VoiceInkTests {}\n'
digest = lambda data: hashlib.sha256(data).hexdigest()
def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])
def source(repo, revision, path):
    return git(repo, 'show', revision + ':' + path)
def files(root):
    return {str(path.relative_to(root)): digest(path.read_bytes()) for path in sorted(root.rglob('*')) if path.is_file()}
def pins(raw):
    payload = json.loads(raw)
    values = payload['pins']
    mapped = {pin['identity']: pin for pin in values}
    if len(values) != len(mapped): raise ValueError('Duplicate dependency identities')
    return mapped

def classify(log, exit_code):
    starts = re.findall(r'^◇ Test ([A-Za-z_][A-Za-z_0-9]*)\(\) started\.$', log, re.M)
    passes = re.findall(r'^✔ Test ([A-Za-z_][A-Za-z_0-9]*)\(\) passed after [^\r\n]+\.$', log, re.M)
    summaries = re.findall(r'^✔ Test run with (\d+) tests?(?: in (\d+) suites?)? passed after [^\r\n]+\.$', log, re.M)
    events = [line for line in log.splitlines() if re.match(r'^[◇✔✘↷] Test ', line) and not re.match(r'^[◇✔] Test run ', line)]
    accepted = [line for line in events if re.fullmatch(r'◇ Test [A-Za-z_][A-Za-z_0-9]*\(\) started\.|✔ Test [A-Za-z_][A-Za-z_0-9]*\(\) passed after .+\.', line)]
    failures = re.findall(r'^.*(?:✘|↷|recorded an issue|recorded \d+ issues?|\bTest .+ skipped|\berror:|Fatal error|fatal error|\bTEST FAILED\b|\bTest run .+ failed).*$' , log, re.M)
    valid = exit_code == 0 and log.count('◇ Test run started.') == 1 and len(summaries) == 1 and summaries[0][0] == '7' and collections.Counter(starts) == collections.Counter(CASES) and collections.Counter(passes) == collections.Counter(CASES) and events == accepted and not failures
    return {'valid': bool(valid), 'classification': 'passed-seven-clarity-service-tests' if valid else 'invalid-or-failed', 'exitCode': exit_code, 'expectedTests': CASES, 'startedTests': starts, 'passedTests': passes, 'summaries': summaries, 'failureLines': failures, 'unrecognizedTestEvents': [line for line in events if line not in accepted]}

def self_test():
    good = '◇ Test run started.\n' + ''.join('◇ Test ' + name + '() started.\n✔ Test ' + name + '() passed after 0.1 seconds.\n' for name in CASES) + '✔ Test run with 7 tests in 2 suites passed after 6.1 seconds.\n'
    values = {
        'seven-pass': (good, 0, True),
        'native-failure-exit': (good, 1, False),
        'zero-tests': ('◇ Test run started.\n✔ Test run with 0 tests passed after 0.1 seconds.\n', 0, False),
        'missing-start': (good.replace('◇ Test ' + CASES[0] + '() started.\n', ''), 0, False),
        'missing-pass': (good.replace('✔ Test ' + CASES[0] + '() passed after 0.1 seconds.\n', ''), 0, False),
        'wrong-name': (good.replace(CASES[0], 'unrelatedTest'), 0, False),
        'duplicate-test': (good.replace('◇ Test run started.\n', '◇ Test run started.\n◇ Test ' + CASES[0] + '() started.\n✔ Test ' + CASES[0] + '() passed after 0.1 seconds.\n'), 0, False),
        'extra-test': (good + '◇ Test unrelated() started.\n✔ Test unrelated() passed after 0.1 seconds.\n', 0, False),
        'skip': (good.replace('✔ Test ' + CASES[0] + '() passed after 0.1 seconds.', '↷ Test ' + CASES[0] + '() skipped.'), 0, False),
        'issue': (good + '✘ Test ' + CASES[0] + '() recorded an issue at Test.swift:1.\n', 0, False),
        'build-error': (good + '/tmp/Clarity.swift:1: error: compilation failed\n', 0, False),
        'no-summary': (good[:good.index('✔ Test run with')], 0, False),
        'wrong-summary-count': (good.replace('with 7 tests', 'with 8 tests'), 0, False),
        'two-runs': (good + good, 0, False),
        'foreign-display-name': (good + '◇ Test "other" started.\n', 0, False),
        'whitespace-unknown-event': (good + '✘ Test failed.\n', 0, False)
    }
    observed = {name: classify(log, code)['valid'] for name, (log, code, expected) in values.items()}
    assert all(observed[name] == expected for name, (_, _, expected) in values.items()), observed
    print(json.dumps({'valid': True, 'classifierFixtures': observed}, indent=2))

command, *args = sys.argv[1:]
if command == 'self-test':
    self_test()
elif command == 'prepare':
    repo, out, revision = Path(args[0]), Path(args[1]), args[2]
    if git(repo, 'rev-parse', 'HEAD').decode().strip() != revision: raise SystemExit('Candidate HEAD mismatch')
    relevant = [*SOURCES, TEST, 'VoiceInkCore', 'VoiceInkNVIDIA', LOCK, DRIVER, WORKFLOW]
    subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', 'HEAD', '--', *relevant], check=True)
    if git(repo, 'ls-files', '--others', '--exclude-standard', '--', *relevant).strip(): raise SystemExit('Untracked relevant source is forbidden')
    git(repo, 'ls-files', '--error-unmatch', DRIVER, WORKFLOW, TEST)
    oracle = source(repo, revision, TEST)
    if digest(oracle) != TEST_HASH or re.findall(rb'@Test\s+@MainActor\s+func\s+(\w+)\(', oracle) != [name.encode() for name in CASES]: raise SystemExit('Exact seven-test oracle changed')
    if digest(source(repo, revision, SOURCES[1])) != SERVICE_HASH: raise SystemExit('Reviewed Clarity service implementation changed')
    package = out / 'package'
    app = package / 'Sources/VoiceInk'
    tests = package / 'Tests/VoiceInkTests'
    app.mkdir(parents=True)
    tests.mkdir(parents=True)
    for path in SOURCES: (app / Path(path).name).write_bytes(source(repo, revision, path))
    (tests / 'ClarityProviderTests.swift').write_bytes(oracle)
    (tests / 'Namespace.swift').write_text(WRAPPER)
    dependency_root = package / 'Dependencies'
    dependency_root.mkdir()
    archive = git(repo, 'archive', revision, 'VoiceInkCore', 'VoiceInkNVIDIA')
    with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
        members = stream.getmembers()
        if any(Path(item.name).is_absolute() or '..' in Path(item.name).parts or Path(item.name).parts[0] not in ['VoiceInkCore', 'VoiceInkNVIDIA'] or not (item.isfile() or item.isdir()) for item in members): raise SystemExit('Unexpected real dependency archive entry')
        stream.extractall(dependency_root, members=members)
    canonical = source(repo, revision, LOCK)
    canonical_pins = pins(canonical)
    nvidia = pins(source(repo, revision, 'VoiceInkNVIDIA/Package.resolved'))
    identities = set(nvidia) | {'llmkit', 'selectedtextkit', 'axswift', 'keysender'}
    if len(canonical_pins) != 41 or len(nvidia) != 22 or len(identities) != 26 or identities - canonical_pins.keys(): raise SystemExit('Reviewed canonical41/NVIDIA22/service26closure changed')
    retained = {name: canonical_pins[name] for name in sorted(identities)}
    dependencies = ['.package(path: "Dependencies/VoiceInkCore")']
    for pin in retained.values():
        state = pin['state']
        requirement = ('branch: ' + json.dumps(state['branch'])) if 'branch' in state else ('exact: ' + json.dumps(state['version'])) if 'version' in state else ('revision: ' + json.dumps(state['revision']))
        dependencies.append('.package(url: ' + json.dumps(pin['location']) + ', ' + requirement + ')')
    manifest = '// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: "ClarityServiceCheck", platforms: [.macOS(.v14)], dependencies: [\n' + ',\n'.join(dependencies) + '\n], targets: [\n.target(name: "VoiceInk", dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore"), .product(name: "LLMkit", package: "LLMkit"), .product(name: "SelectedTextKit", package: "SelectedTextKit")]),\n.testTarget(name: "VoiceInkTests", dependencies: ["VoiceInk", .product(name: "VoiceInkCore", package: "VoiceInkCore")])\n], swiftLanguageVersions: [.v5])\n'
    (package / 'Package.swift').write_text(manifest)
    seeded = json.dumps({'pins': list(retained.values()), 'version': 2}, indent=2, sort_keys=True) + '\n'
    (package / 'Package.resolved').write_text(seeded)
    tracked = git(repo, 'ls-files', '-z', '--', *relevant).split(b'\0')
    original = {name.decode(): digest(source(repo, revision, name.decode())) for name in tracked if name}
    contract = {'version': 1, 'sourceSHA': revision, 'sourceInputs': original, 'appSources': {path: original[path] for path in SOURCES}, 'testSourceSHA256': TEST_HASH, 'serviceSourceSHA256': SERVICE_HASH, 'namespace': 'VoiceInk', 'testNamespace': 'VoiceInkTests', 'namespaceWrapperSHA256': digest(WRAPPER.encode()), 'expectedTests': CASES, 'generatedSources': files(package / 'Sources'), 'generatedTests': files(package / 'Tests'), 'dependencySources': files(dependency_root), 'packageManifestSHA256': digest(manifest.encode()), 'seededLockSHA256': digest(seeded.encode()), 'canonicalLockSHA256': digest(canonical), 'expectedPins': retained, 'omittedIdentities': sorted(set(canonical_pins) - identities), 'scope': 'Seven unchanged Clarity service tests through standard Swift Testing. Eleven unchanged app source files and full real Core/NVIDIA source closure. Local deterministic commands only. No app lifecycle, UI, microphone, TCC, authenticated AI provider or live editor delivery proof.'}
    write(out / 'source-contract.json', contract)
    write(out / 'source-before.json', original)
    (out / 'canonical-Package.resolved').write_bytes(canonical)
    (out / 'seeded-Package.resolved').write_text(seeded)
elif command == 'pins':
    out, phase = Path(args[0]), args[1]
    contract = json.loads((out / 'source-contract.json').read_text())
    raw = (out / 'package/Package.resolved').read_bytes()
    observed = pins(raw)
    valid = observed == contract['expectedPins']
    write(out / ('pins-' + phase + '.json'), {'valid': valid, 'lockSHA256': digest(raw), 'expectedPins': contract['expectedPins'], 'observedPins': observed})
    if not valid: raise SystemExit('Temporary package resolution changed canonical dependency pins')
    if phase == 'before-build': (out / 'resolved-before-build.json').write_bytes(raw)
    elif raw != (out / 'resolved-before-build.json').read_bytes(): raise SystemExit('Frozen resolved metadata changed during build/tests')
elif command == 'verify':
    repo, out, phase = Path(args[0]), Path(args[1]), args[2]
    package = out / 'package'
    contract = json.loads((out / 'source-contract.json').read_text())
    observed = {path: digest((repo / path).read_bytes()) for path in contract['sourceInputs']}
    if observed != contract['sourceInputs'] or git(repo, 'rev-parse', 'HEAD').decode().strip() != contract['sourceSHA']: raise SystemExit('Source inputs changed during service proof')
    for name, key in [('Sources', 'generatedSources'), ('Tests', 'generatedTests'), ('Dependencies', 'dependencySources')]:
        if files(package / name) != contract[key]: raise SystemExit('Generated source bytes or exact path census changed: ' + name)
    if digest((package / 'Package.swift').read_bytes()) != contract['packageManifestSHA256']: raise SystemExit('Temporary package manifest changed')
    write(out / ('source-' + phase + '.json'), observed)
    write(out / 'source-verification.json', {'valid': True, 'sourceSHA': contract['sourceSHA'], 'testSourceSHA256': TEST_HASH, 'serviceSourceSHA256': SERVICE_HASH})
elif command == 'binary':
    out, binary, phase = Path(args[0]), Path(args[1]), args[2]
    bundle = binary / 'ClarityServiceCheckPackageTests.xctest'
    executable = bundle / 'Contents/MacOS/ClarityServiceCheckPackageTests'
    if not executable.is_file(): raise SystemExit('Standard SwiftPM Clarity test executable is absent')
    resources = {path.name: files(path) for path in sorted(binary.glob('*.bundle')) if path.is_dir()}
    value = {'bundlePath': str(bundle), 'executablePath': str(executable), 'executableSHA256': digest(executable.read_bytes()), 'bundleManifest': files(bundle), 'resourceBundleManifests': resources}
    write(out / ('test-binary-' + phase + '.json'), value)
    if phase == 'after' and value != json.loads((out / 'test-binary-before.json').read_text()): raise SystemExit('Test executable, bundle or resource bytes changed')
    if phase == 'after': write(out / 'identity-verification.json', {'valid': True, **value})
elif command == 'classify':
    out, exit_code = Path(args[0]), int(args[1])
    result = classify((out / 'tests.log').read_text(), exit_code)
    result['sourceSHA'] = json.loads((out / 'source-contract.json').read_text())['sourceSHA']
    result['scope'] = json.loads((out / 'source-contract.json').read_text())['scope']
    result['valid'] = result['valid'] and all(json.loads((out / name).read_text()).get('valid') is True for name in ['source-verification.json', 'identity-verification.json', 'pins-after.json'])
    if not result['valid']: result['classification'] = 'invalid-or-failed'
    write(out / 'result.json', result)
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
  echo "Use --self-test locally. Native proof requires a fresh non-root GitHub-hosted Mac." >&2
  exit 2
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
test "$(git -C "$repo" rev-parse HEAD)" = "$GITHUB_SHA"
out="$RUNNER_TEMP/clarity-service-check"
test ! -e "$out"
mkdir -m 700 "$out"
phase=prepare
trap 'code=$?; if [[ "$code" != 0 ]]; then printf "{\"valid\":false,\"phase\":\"%s\",\"exitCode\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi' EXIT
{
  git -C "$repo" rev-parse HEAD
  xcodebuild -version
  swift --version
  sw_vers
  uname -m
} > "$out/toolchain.log" 2>&1
proof prepare "$repo" "$out" "$GITHUB_SHA"
package="$out/package"
args=(--package-path "$package" --configuration debug --force-resolved-versions --skip-update)
phase=normalize-resolved-metadata
xcrun swift package --package-path "$package" --skip-update resolve > "$out/resolve.log" 2>&1
proof pins "$out" before-build
proof verify "$repo" "$out" prepared
phase=build
xcrun swift build "${args[@]}" --build-tests > "$out/build.log" 2>&1
proof pins "$out" after-build
xcrun swift build "${args[@]}" --show-bin-path > "$out/bin-path.txt" 2>> "$out/build.log"
bin="$(cat "$out/bin-path.txt")"
test_bundle="$bin/ClarityServiceCheckPackageTests.xctest"
test_executable="$test_bundle/Contents/MacOS/ClarityServiceCheckPackageTests"
codesign --verify --strict "$test_executable" > "$out/signature-verification-before.log" 2>&1
codesign --display --verbose=4 "$test_executable" > "$out/signature-before.txt" 2>&1
proof binary "$out" "$bin" before
proof verify "$repo" "$out" before-tests
phase=tests
test_exit=0
xcrun swift test "${args[@]}" --skip-build --enable-swift-testing --disable-xctest --no-parallel --xunit-output "$out/tests.xml" > "$out/tests.log" 2>&1 || test_exit=$?
printf '%s\n' "$test_exit" > "$out/test-exit-code.txt"
phase=verify
codesign --verify --strict "$test_executable" > "$out/signature-verification-after.log" 2>&1
codesign --display --verbose=4 "$test_executable" > "$out/signature-after.txt" 2>&1
cmp "$out/signature-before.txt" "$out/signature-after.txt"
proof binary "$out" "$bin" after
proof pins "$out" after
proof verify "$repo" "$out" after
phase=classify
proof classify "$out" "$test_exit"
