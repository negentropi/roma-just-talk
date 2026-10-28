#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run PR review regression only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The runner must own the logged-in desktop." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/writing-pr-review-proof" "${1:-run}" "${2:-}" <<'PY'
import hashlib
import json
import os
import plistlib
import re
import shlex
import signal
import stat
import subprocess
import sys
from pathlib import Path

repo, out = map(Path, sys.argv[1:3])
mode = sys.argv[3]
bad = 'c1f3bb69356aed9abce01c43a4432c894b89c838'
prefs = 'VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift'
last = 'VoiceInk/Services/LastTranscriptionService.swift'
view = 'VoiceInk/Views/Dictionary/SpokenSnippetsView.swift'
core = 'VoiceInkCore/Sources/VoiceInkCore/SpokenSnippets.swift'
runner = 'VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift'
oracle = 'VoiceInkTests/WritingActionUndoTests.swift'
fixture = 'scripts/fixtures/WritingSnippetMutationProbe.swift'
reset_case = 'UserDefaultsPreferencesTests.testSharedPreferenceResetClearsCoreUserSettings'
busy = ['pasteLastWhileDeliveryIsBusyPreservesOwnerAndStillPastesWhenIdle',
    'pasteLastDuringUndoDoesNotReplaceItsOwnerOrInterruptRestoration',
    'emptyTapFallbackKeepsItsOwnedDeliveryHandoff']
markers = ['Paste Last must not replace the active delivery owner',
    'Paste Last must not interrupt an active Undo']
roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInkTests',
    'VoiceInkUITests', 'VoiceInk.xcodeproj', 'VoiceInk.xcworkspace', 'iOS', 'Tools',
    'Package.swift', 'Package.resolved', 'Makefile', 'LocalBuild.xcconfig']

def require(ok, message):
    if not ok: raise RuntimeError(message)

def sha(data): return hashlib.sha256(data).hexdigest()
def git(*args): return subprocess.check_output(['git', '-C', str(repo), *args])
def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def interrupted(number, _frame):
    raise SystemExit(128 + number)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)

def run(args, log, *, timeout=1200, env=None):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as stream:
        child = subprocess.Popen(args, cwd=repo, stdout=stream, stderr=subprocess.STDOUT,
            start_new_session=True, env=env)
        try: return child.wait(timeout=timeout)
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try: child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()

def mutate_body(source):
    found = re.findall(r'(?ms)^    private func mutate\(_ change: \(inout \[VoiceInkSpokenSnippet\]\) throws -> Void\) throws \{\n.*?^    \}', source)
    require(len(found) == 1, 'Production snippet mutation boundary must resolve exactly once')
    return found[0]

def native_result(text, code, lane):
    expected = dict.fromkeys(busy, 'passed')
    if lane == 'baseline':
        expected[busy[0]] = expected[busy[1]] = 'failed'
    observed = {}
    for name in busy:
        require(len(re.findall(r'Test ' + name + r'\(\) started\.', text)) == 1,
            'Each selected native case must start once: ' + name)
        values = re.findall(r'Test ' + name + r'\(\) (passed|failed) after ', text)
        require(values == [expected[name]], 'Unexpected native outcome: ' + name)
        observed[name] = values[0]
    summary = re.findall(r'Test run with (\d+) tests? in \d+ suites? (passed|failed)', text)
    require(summary == [('3', 'failed' if lane == 'baseline' else 'passed')]
        and code == (65 if lane == 'baseline' else 0), 'Native exact-count summary/exit differs')
    issues = re.findall(r'^.*recorded an issue[^\n]*', text, re.M)
    require(bool(issues) == (lane == 'baseline') and all('Expectation failed:' in line for line in issues),
        'Only behavioral assertions may fail')
    require(lane != 'baseline' or all(marker in text for marker in markers),
        'Both native ownership failures must be observed')
    require(not re.search(r'^(?:.*\.swift:\d+(?::\d+)?:\s*(?:fatal\s+)?error:|\s*error:|xcodebuild: error:)|Test session ended prematurely|failed to launch|Testing cancelled|crashed|fatal error:', text, re.M | re.I),
        'Compiler, crash or launch failures cannot count as red proof')
    return {'valid': True, 'tests': observed, 'exitCode': code, 'issues': issues}

def assertion_sites(source):
    sites = {}
    for index, name in enumerate(busy[:2]):
        method = re.search(r'(?ms)^        @Test @MainActor func ' + name + r'\(\).*?^        \}', source)
        require(method is not None, 'Native oracle method missing: ' + name)
        for marker in re.finditer(re.escape(markers[index]), method[0]):
            prefix = method[0][:marker.start()]
            start = prefix.rfind('#expect(')
            require(start >= 0, 'Intended assertion no longer uses #expect')
            line = source[:method.start() + start].count('\n') + 1
            sites[line] = name
    require(len(sites) == 3, 'Two delivery assertions and one Undo assertion required')
    return sites

def unit_identity(derived, require_unit=True):
    app = derived / 'Build/Products/Debug/roma just talk.app'
    bundles = sorted((derived / 'Build/Products').rglob('*.xctest'))
    require(bool(bundles) and (not require_unit or len([path for path in bundles if path.name == 'VoiceInkTests.xctest']) == 1),
        'Actual compiled test bundles are missing or ambiguous')
    binaries = {}
    for bundle in bundles:
        info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
        binary = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
        binaries[str(binary)] = sha(binary.read_bytes())
    files = {}
    for path in sorted(app.rglob('*')):
        if path.is_symlink(): files[str(path.relative_to(app))] = {'link': os.readlink(path)}
        elif path.is_file(): files[str(path.relative_to(app))] = {'sha256': sha(path.read_bytes())}
    return {'app': str(app), 'appFiles': files, 'testBinaries': binaries}

def snippet_result(rows, lane):
    names = ['malformed-json', 'invalid-library', 'wrong-storage-type', 'missing-library', 'valid-library']
    require([row['case'] for row in rows] == names, 'Exact five snippet transactions required')
    for row in rows[:3]:
        require((row['threw'], row['expectedLoadError'], row['originalStoragePreserved'], row['containsAddedSnippet'])
            == ((False, False, False, True) if lane == 'baseline' else (True, True, True, False)),
            'Snippet corruption was not observed at the required transaction boundary: ' + row['case'])
    require(all(row['controlPassed'] for row in rows[3:]), 'Missing/valid-library positive controls failed')
    return {'valid': True, 'transactions': rows, 'scope': 'Actual UI mutation helper plus unchanged production snippet Core source; no SwiftUI interaction.'}

def snapshot():
    result = {}
    for entry in git('ls-files', '--stage', '-z', '--', *roots).split(b'\0'):
        if not entry: continue
        metadata, raw_name = entry.split(b'\t', 1)
        git_mode, object_id, stage = metadata.decode().split()
        require(stage == '0' and git_mode in ['100644', '100755', '120000'], 'Unsupported or unmerged product source entry')
        name = os.fsdecode(raw_name)
        path = repo / name
        info = path.lstat()
        if git_mode == '120000':
            require(stat.S_ISLNK(info.st_mode), 'Tracked link changed kind: ' + name)
            data = os.fsencode(os.readlink(path))
        else:
            require(stat.S_ISREG(info.st_mode), 'Tracked source changed kind: ' + name)
            data = path.read_bytes()
        result[name] = {'gitMode': git_mode, 'gitObject': object_id, 'worktreeSHA256': sha(data),
            'executable': bool(info.st_mode & 0o111)}
    return result

def self_test():
    for lane in ['baseline', 'candidate']:
        rows = []
        for name in ['malformed-json', 'invalid-library', 'wrong-storage-type', 'missing-library', 'valid-library']:
            damaged = lane == 'baseline' and name not in ['missing-library', 'valid-library']
            rows.append({'case': name, 'threw': not damaged and name not in ['missing-library', 'valid-library'],
                'expectedLoadError': not damaged and name not in ['missing-library', 'valid-library'],
                'originalStoragePreserved': not damaged, 'containsAddedSnippet': damaged or name in ['missing-library', 'valid-library'],
                'controlPassed': name in ['missing-library', 'valid-library']})
        snippet_result(rows, lane)
        rows[0]['originalStoragePreserved'] = not rows[0]['originalStoragePreserved']
        try: snippet_result(rows, lane)
        except RuntimeError: pass
        else: raise RuntimeError('Changed snippet preservation observation accepted')
        text = '\n'.join('Test ' + name + '() started.\nTest ' + name + '() ' + ('failed' if lane == 'baseline' and i < 2 else 'passed') + ' after 0.1 seconds.' for i, name in enumerate(busy))
        if lane == 'baseline': text += '\n' + '\n'.join('Test ' + busy[i] + '() recorded an issue: Expectation failed: ' + marker for i, marker in enumerate(markers))
        text += '\nTest run with 3 tests in 2 suites ' + ('failed' if lane == 'baseline' else 'passed')
        code = 65 if lane == 'baseline' else 0
        native_result(text, code, lane)
        for invalid in [text.replace('with 3 tests', 'with 0 tests'), text + '\nerror: build failed', text + '\nTest extra() recorded an issue: unrelated', text.replace('() started.', '() skipped.')]:
            try: native_result(invalid, code, lane)
            except RuntimeError: pass
            else: raise RuntimeError('Invalid native log accepted')
    print('PR review classifiers: two positive lanes, changed preservation, wrong count, compile error, extra issue and skipped-start controls passed. Metadata only; no native or Swift execution.')

if mode == 'self-test':
    self_test()
    sys.exit(0)
if mode == 'identity':
    print(json.dumps(unit_identity(Path(sys.argv[4])), sort_keys=True))
    sys.exit(0)
require(mode == 'run' and not out.exists(), 'Use a fresh PR review evidence directory')
out.mkdir(parents=True)
if subprocess.run(['git', '-C', str(repo), 'cat-file', '-e', bad + '^{commit}'], capture_output=True).returncode != 0:
    require(run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', bad], out / 'fetch-known-bad.log', timeout=180) == 0,
        'Exact known-bad source revision is unavailable')
source_head = git('rev-parse', 'HEAD').decode().strip()
product_ref = os.environ.get('RJT_PR_REVIEW_PRODUCT_REF', source_head)
require(re.fullmatch(r'[0-9a-f]{40}', product_ref) is not None, 'Product source must be an immutable full SHA')
subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', product_ref, 'HEAD'], check=True)
subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', product_ref, 'HEAD', '--', *roots], check=True)
subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', 'HEAD', '--', *roots], check=True)
require(not git('ls-files', '--others', '--exclude-standard', '-z', '--', *roots), 'Untracked product/test sources must not enter this comparison')
original = {path: (repo / path).read_bytes() for path in [prefs, last]}
before = snapshot()
ordinary_derived = repo / '.local-build'
ordinary_identity = unit_identity(ordinary_derived, require_unit=False)
native_sites = assertion_sites((repo / oracle).read_text())
old = {path: git('show', bad + ':' + path) for path in [prefs, last, view]}
new_helper = mutate_body((repo / view).read_text())
old_helper = mutate_body(old[view].decode())
require(old_helper.replace('var library = VoiceInkSpokenSnippets.load()',
    'var library = try VoiceInkSpokenSnippets.loadForMutation()') == new_helper,
    'Snippet comparison must differ only in the actual strict-read call')
write(out / 'contract.json', {'sourceSHA': source_head, 'productRef': product_ref, 'knownBad': bad,
    'sourceManifest': before, 'swappedProductionSHA256': {path: {'baseline': sha(old[path]), 'candidate': sha(original[path])} for path in original},
    'oracleSHA256': sha((repo / oracle).read_bytes()), 'snippetHelperSHA256': {'baseline': sha(old_helper.encode()), 'candidate': sha(new_helper.encode())},
    'snippetProducerSHA256': {path: sha((repo / path).read_bytes()) for path in [core, fixture, 'VoiceInk/Notifications/AppNotifications.swift']},
    'scope': 'Matched source comparisons; fixture inserter handles app-test delivery. No physical input or normal-app UI assertion.'})

try:
    # Reset uses the complete, unchanged candidate Core oracle set in both lanes.
    expected = re.findall(r'VoiceInkCoreCheck\(name: "([^"]+)"', (repo / runner).read_text())
    require(len(expected) == len(set(expected)) and reset_case in expected, 'Core oracle registration is ambiguous')
    for lane in ['baseline', 'candidate']:
        (repo / prefs).write_bytes(old[prefs] if lane == 'baseline' else original[prefs])
        log = out / 'reset' / lane / 'checks.log'
        code = run(['swift', 'run', '--package-path', 'VoiceInkCore', '--force-resolved-versions', 'VoiceInkCoreChecks'], log)
        text = log.read_text(errors='replace')
        observed = re.findall(r'^(PASS|FAIL) ([^\n]+)$', text, re.M)
        require([name for _, name in observed] == expected, 'Every Core case must execute once in registered order')
        failed = [name for outcome, name in observed if outcome == 'FAIL']
        require(failed == ([reset_case] if lane == 'baseline' else []) and code == (1 if lane == 'baseline' else 0), 'Only the reset case may fail')
        if lane == 'baseline':
            failures = text.split('VoiceInkCoreChecks failed:\n')[-1].strip().splitlines()
            require(len(failures) == 3 and all("Reset must remove the writing shortcut's cleared marker:" in line for line in failures)
                and len(set(failures)) == 3, 'Exactly three stale clear markers must fail')
        write(out / 'reset' / lane / 'result.json', {'valid': True, 'exitCode': code, 'executed': len(observed), 'failed': failed})
    (repo / prefs).write_bytes(original[prefs])

    # Compile the actual helper body with the same complete production Core file.
    template = (repo / fixture).read_text()
    require(template.count('/* ACTUAL_MUTATION */') == template.count('/* ACTUAL_NOTIFICATION */') == 1, 'Snippet fixture slots changed')
    notification = re.findall(r'^    static let writingFeaturesDidChange = Notification\.Name\("[^"\n]+"\)$',
        (repo / 'VoiceInk/Notifications/AppNotifications.swift').read_text(), re.M)
    require(len(notification) == 1, 'Actual snippet notification declaration missing')
    for lane, helper in [('baseline', old_helper), ('candidate', new_helper)]:
        directory = out / 'snippets' / lane
        directory.mkdir(parents=True)
        main = directory / 'main.swift'
        main.write_text(template.replace('/* ACTUAL_NOTIFICATION */', notification[0]).replace('/* ACTUAL_MUTATION */', helper.replace('private func mutate(', 'func mutate(', 1)))
        executable = directory / ('snippet-transaction-' + lane)
        require(run(['xcrun', 'swiftc', str(repo / core), str(main), '-o', str(executable)], directory / 'build.log', timeout=300) == 0,
            'Snippet helper must compile successfully before observing either lane')
        isolated = directory / 'isolated-user'
        isolated.mkdir()
        env = dict(os.environ, CFFIXED_USER_HOME=str(isolated))
        require(run([str(executable)], directory / 'transactions.json', env=env, timeout=30) == 0, 'Snippet transaction process failed')
        write(directory / 'result.json', snippet_result(json.loads((directory / 'transactions.json').read_text()), lane))
    observed_inputs = []
    for lane in ['baseline', 'candidate']:
        rows = json.loads((out / 'snippets' / lane / 'transactions.json').read_text())
        observed_inputs.append([{key: row[key] for key in ['case', 'inputKind', 'inputBytesBase64']} for row in rows])
    require(observed_inputs[0] == observed_inputs[1], 'Snippet lanes must receive the same exact stored inputs')
    write(out / 'snippets/paired-inputs.json', {'valid': True, 'sameExactInputs': True, 'inputs': observed_inputs[0]})

    # Reuse the existing signed-host recipe, changing only exact test/evidence selection.
    derived = out.parent / 'writing-pr-review-unit-derived'
    require(not derived.exists(), 'Use a fresh lane-owned derived-data root')
    enum = out / 'native-discovery'
    enum.mkdir()
    enumeration = enum / 'selected-tests.json'
    recipe = (repo / 'scripts/run-macos-ci-unit-tests.sh').read_text()
    substitutions = {
        'evidence="$PWD/.local-build/onboarding-test-evidence"': 'evidence="$RJT_PR_REVIEW_EVIDENCE"',
        'probe=/tmp/roma-onboarding-diagnostic/ExternalAXProbe': 'probe="$evidence/ExternalAXProbe"',
        'app="$PWD/.local-build/Build/Products/Debug/roma just talk.app"': 'app="$RJT_PR_REVIEW_DERIVED/Build/Products/Debug/roma just talk.app"',
        '-derivedDataPath "$PWD/.local-build"': '-derivedDataPath "$RJT_PR_REVIEW_DERIVED" -clonedSourcePackagesDirPath "$RJT_PR_REVIEW_PACKAGES"'
    }
    owned_recipe = recipe
    for old_text, new_text in substitutions.items():
        require(owned_recipe.count(old_text) == 1, 'Signed-host recipe boundary changed: ' + old_text)
        owned_recipe = owned_recipe.replace(old_text, new_text)
    env = dict(os.environ, RJT_PR_REVIEW_DERIVED=str(derived), RJT_PR_REVIEW_PACKAGES=str(ordinary_derived / 'SourcePackages'),
        RJT_PR_REVIEW_DRIVER=str(repo / 'scripts/run-writing-pr-review-regression.sh'))
    require(owned_recipe.count('test_exit=0\n') == 1, 'Signed-host build/provision boundary changed')
    build_prefix = owned_recipe.split('test_exit=0\n')[0]
    (enum / 'build-and-provision.sh').write_text(build_prefix)
    (repo / last).write_bytes(old[last])
    require(run(['bash', '-c', build_prefix, str(repo / 'scripts/run-macos-ci-unit-tests.sh')], enum / 'build.log',
        timeout=1200, env=dict(env, RJT_PR_REVIEW_EVIDENCE=str(enum))) == 0,
        'Lane-owned unit host must build successfully before discovering tests')
    arguments = ['-project', 'VoiceInk.xcodeproj', '-scheme', 'VoiceInk', '-configuration', 'Debug', '-destination', 'platform=macOS',
        '-derivedDataPath', str(derived), '-xcconfig', 'LocalBuild.xcconfig', '-parallel-testing-enabled', 'NO', '-only-testing:VoiceInkTests']
    require(run(['xcodebuild', 'test-without-building', *arguments, '-enumerate-tests', '-test-enumeration-style', 'flat',
        '-test-enumeration-format', 'json', '-test-enumeration-output-path', str(enumeration)], enum / 'enumeration.log', timeout=180) == 0,
        'Native test enumeration failed')
    value = json.loads(enumeration.read_text())
    require(not value.get('errors'), 'Native enumeration contains errors')
    enabled = [test['identifier'] for plan in value.get('values', []) for test in plan.get('enabledTests', [])]
    selected = []
    for name in busy:
        found = [identifier for identifier in enabled if identifier.endswith('/' + name + '()') and 'WritingActionUndoTests' in identifier]
        require(len(found) == 1, 'Busy oracle must resolve uniquely: ' + name)
        selected.append(found[0])
    for lane in ['baseline', 'candidate']:
        directory = out / 'native' / lane
        directory.mkdir(parents=True)
        (repo / last).write_bytes(old[last] if lane == 'baseline' else original[last])
        changed = owned_recipe
        require(changed.count('-only-testing:VoiceInkTests\n') == 1, 'Unit target selection boundary changed')
        changed = changed.replace('-only-testing:VoiceInkTests\n',
            '\n'.join('  ' + shlex.quote('-only-testing:' + identifier) for identifier in selected) + '\n')
        additions = {
            'fingerprint > "$evidence/identity-before.txt"': 'fingerprint > "$evidence/identity-before.txt"\n'
                'bash "$RJT_PR_REVIEW_DRIVER" identity "$RJT_PR_REVIEW_DERIVED" > "$evidence/native-binary-before.json"',
            'test_exit=0\n': 'xcodebuild test-without-building "${build_arguments[@]}" -enumerate-tests '
                '-test-enumeration-style flat -test-enumeration-format json '
                '-test-enumeration-output-path "$evidence/selected-tests.json" > "$evidence/enumeration.log" 2>&1\ntest_exit=0\n',
            'fingerprint > "$evidence/identity-after.txt"': 'fingerprint > "$evidence/identity-after.txt"\n'
                'bash "$RJT_PR_REVIEW_DRIVER" identity "$RJT_PR_REVIEW_DERIVED" > "$evidence/native-binary-after.json"\n'
                'cmp "$evidence/native-binary-before.json" "$evidence/native-binary-after.json"'
        }
        for old_text, new_text in additions.items():
            require(changed.count(old_text) == 1, 'Signed-host execution boundary changed: ' + old_text)
            changed = changed.replace(old_text, new_text)
        (directory / 'signed-unit-recipe.sh').write_text(changed)
        write(directory / 'recipe.json', {'sourceSHA256': sha(recipe.encode()), 'executedSHA256': sha(changed.encode()),
            'selected': selected, 'changes': list(substitutions), 'addedIdentityAndEnumerationChecks': list(additions), 'derivedData': str(derived),
            'signingAndTCC': 'Unchanged existing fresh-host provisioning and before/after fingerprint checks.'})
        code = run(['bash', '-c', changed, str(repo / 'scripts/run-macos-ci-unit-tests.sh')], directory / 'tests.log', timeout=1200,
            env=dict(env, RJT_PR_REVIEW_EVIDENCE=str(directory)))
        text = (directory / 'tests.log').read_text(errors='replace')
        result = native_result(text, code, lane)
        enumeration = json.loads((directory / 'selected-tests.json').read_text())
        narrowed = [test['identifier'] for plan in enumeration.get('values', []) for test in plan.get('enabledTests', [])]
        disabled = [test.get('identifier') for plan in enumeration.get('values', []) for test in plan.get('disabledTests', [])]
        require(not enumeration.get('errors') and len(narrowed) == 3 and sorted(narrowed) == sorted(selected)
            and not set(selected).intersection(disabled), 'Actual lane must enumerate exactly the three selected tests')
        observed_sites = []
        for issue in result['issues']:
            match = re.search(r'Test (\w+)\(\) recorded an issue at .*WritingActionUndoTests\.swift:(\d+):\d+:.*Expectation failed:', issue)
            require(match is not None and native_sites.get(int(match[2])) == match[1], 'Unexpected native failure site')
            observed_sites.append(int(match[2]))
        require(lane != 'baseline' or set(observed_sites) == set(native_sites), 'Each intended native failure site must execute')
        write(directory / 'result.json', dict(result, intendedFailureSites=native_sites, observedFailureSites=observed_sites,
            binaryIdentity=unit_identity(derived)))
        executable = derived / 'Build/Products/Debug/roma just talk.app/Contents/MacOS/roma just talk'
        closed = subprocess.run(['lsof', '-F', 'pn', '--', str(executable)], text=True, capture_output=True, timeout=30)
        write(directory / 'closed-host.json', {'executable': str(executable), 'exitCode': closed.returncode, 'stdout': closed.stdout, 'stderr': closed.stderr})
        require(closed.returncode == 1 and not closed.stdout.strip(), 'Native host executable must have no remaining open handles')
finally:
    for path, data in original.items(): (repo / path).write_bytes(data)
    after = snapshot()
    write(out / 'source-after.json', after)
    require(after == before, 'PR review comparison changed candidate source or package pins')
    require(not git('ls-files', '--others', '--exclude-standard', '-z', '--', *roots), 'Comparison added untracked product/test inputs')
    require(unit_identity(ordinary_derived, require_unit=False) == ordinary_identity, 'Ordinary unit/UI host artifacts changed')
write(out / 'result.json', {'valid': True, 'classification': 'matched-pr-review-regression-passed', 'sourceSHA': source_head,
    'productRef': product_ref, 'knownBad': bad, 'candidateSourcesRestored': True,
    'scope': ['reset-clear-markers', 'actual-snippet-helper-transaction', 'Paste-Last-delivery-and-Undo-ownership'],
    'limits': ['Snippet probe executes Foundation/helper/Core data handling, not SwiftUI.', 'Busy tests use the real public service/controller with the existing test inserter, not native editor input.']})
PY
