#!/usr/bin/env python3
"""Read original hosted observations on /data; recompute the pinned classifier."""
import ast
import hashlib
import json
import math
import stat
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath

root = Path(__file__).resolve().parent
head = '2ebdfd1772e3f45f9fe1fe4e2787af7fbfc53ea2'
run_id = 40617652407
branch = 'ci/rjt-language-selection-probe-c41d72fc-01a17bef'
digest = lambda b: hashlib.sha256(b).hexdigest()
load = lambda p: json.loads(p.read_text())
expected = load(root / 'git-source-expectations.json')
assert expected['head'] == head and len(expected['source_sha256']) == 612
run = load(root / 'run-final.json')
assert run['databaseId'] == run_id and run['headSha'] == head and run['headBranch'] == branch
assert run['status'] == 'completed' and run['conclusion'] == 'success'
assert len(run['jobs']) == 1 and run['jobs'][0]['conclusion'] == 'success'
required = ['Bind unchanged language view, probe fixture and canonical packages',
    'Prepare static Whisper for linkage without model weights', 'Build isolated host and observe current English selection',
    'Verify typed preferences, positive controls and closed-host evidence', 'Upload language observations and source receipts']
for name in required:
    assert sum(s['name'] == name and s['conclusion'] == 'success' for s in run['jobs'][0]['steps']) == 1
artifacts = load(root / 'artifacts.json')['artifacts']
for a in artifacts:
    assert a['workflow_run']['id'] == run_id and a['workflow_run']['head_sha'] == head
    assert a['workflow_run']['head_branch'] == branch
metadata = [a for a in artifacts if a['name'] == 'roma.language-selection-probe-observations']
assert len(metadata) == 1
metadata = metadata[0]
archive = root / 'observations.zip'
raw = archive.read_bytes()
assert len(raw) == metadata['size_in_bytes'] and 'sha256:' + digest(raw) == metadata['digest']
download = load(root / 'download-receipt.json')
assert download['download_count'] == 1 and download['artifact_id'] == metadata['id'] and download['run_id'] == run_id
assert download['zip_bytes'] == len(raw) and download['zip_sha256'] == digest(raw)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and len(z.namelist()) == len(set(z.namelist())) == 52
    for i in z.infolist():
        name = PurePosixPath(i.filename)
        assert not name.is_absolute() and '..' not in name.parts and not stat.S_ISLNK(i.external_attr >> 16)
        b = z.read(i.filename)
        assert download['members'][i.filename] == {'bytes': len(b), 'sha256': digest(b)}
    obj = lambda n: json.loads(z.read(n))
    c = obj('contract.json')
    assert c['source_sha'] == head and c['github_run_id'] == str(run_id)
    assert c['cases'] == ['same-current-english', 'changed-japanese', 'changed-english']
    assert obj('source-before.json') == obj('source-after.json') == expected['source_sha256']
    assert c['language_view_sha256'] == expected['source_sha256']['VoiceInk/Views/AI Models/LanguageSelectionView.swift']
    assert c['language_view_sha256'] == 'a74fb78c6bc4dc38b15d616de8fd93740717ee04fceb5caac2e2e450745616c7'
    generated = {}
    for n in ['LanguageSelectionProbeHost.swift', 'LanguageSelectionProbeOracle.swift']:
        assert digest(z.read('source/' + n)) == expected['source_sha256']['scripts/fixtures/' + n]
        generated['VoiceInk/' + n] = digest(z.read('source/' + n))
    assert generated == c['generated_sources_sha256']
    build_roots = ['VoiceInk', 'VoiceInkCore', 'VoiceInkNVIDIA', 'VoiceInkQwen', 'VoiceInk.xcodeproj', 'iOS', 'Makefile', 'LocalBuild.xcconfig']
    candidate = {n: h for n, h in expected['source_sha256'].items()
        if n in build_roots or any(n.startswith(p + '/') for p in build_roots)} | generated
    assert obj('candidate-source.json') == candidate
    compile_inputs = obj('compile-inputs.json')
    swift_paths = sorted(n for n in candidate if n.startswith('VoiceInk/') and n.endswith('.swift') and n != 'VoiceInk/VoiceInk.swift')
    assert compile_inputs['source_paths'] == swift_paths and compile_inputs['excluded_source_files'] == ['VoiceInk.swift']
    assert compile_inputs['build_settings_sha256'] == digest(z.read('build-settings.json'))
    assert set(compile_inputs['response_file_settings']) == {'arm64'}
    assert len(compile_inputs['swift_file_lists_sha256']) == 1
    lock = z.read('packages/canonical.Package.resolved')
    lock_sha = digest(lock)
    assert lock_sha == c['lock_sha256'] == expected['source_sha256']['VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']
    pins = json.loads(lock)['pins']
    assert len(pins) == len({p['identity'] for p in pins}) == 41
    packages = obj('packages-before.json')
    assert packages['lock_sha256'] == lock_sha and set(packages['packages']) == {p['identity'] for p in pins}
    for pin in pins:
        actual = packages['packages'][pin['identity']]
        assert actual['revision'] == pin['state']['revision'] and len(actual['tree']) == 40
        assert all(line.startswith(' ') for line in actual['recursive_gitlinks'])
    assert obj('packages/candidate-strict-resolve.json') == {'exit_code': 0, 'canonical_lock_unchanged': True}
    identity = obj('identity-before.json')
    assert identity == obj('identity-after.json')
    signature = obj('signature/result.json')
    assert signature['classification'] == 'verified-adhoc-macos-test-host' and signature['signature'] == 'adhoc'
    assert signature['strict_deep_verification_passed'] is True and signature['library_validation_disabled'] is True
    assert signature['executable_path'] == identity['executable_path'] and signature['numeric_code_directory_flags'] == 2
    assert signature['executable_sha256'] == identity['app_files_sha256']['Contents/MacOS/roma just talk']
    assert z.read('host-requirement.txt').decode().strip() == identity['designated_requirement']
    tcc = obj('tcc-before.json')
    assert tcc == obj('tcc-after.json') and len(tcc) == 3
    assert {r['service'] for r in tcc} == {'kTCCServiceAccessibility', 'kTCCServiceScreenCapture'}
    assert all(r['client'] == 'com.negentropi.RomaJustTalk' and r['client_type'] == 0 and r['auth_value'] == 2 for r in tcc)
    assert len({r['requirement'] for r in tcc}) == 1 and bool(tcc[0]['requirement'])
    live, closed, outcome = obj('host-live.json'), obj('host-closed.json'), obj('host-outcome.json')
    assert live['exit_code'] == 0 and live['host']['executable_path'] == identity['executable_path']
    assert identity['executable_path'] in live['host']['mapped_text_paths']
    assert live['spawned_identity'] == {k: live['host'][k] for k in ['started_at', 'executable_path']}
    assert closed['host'] == live['host'] and closed['valid'] is True and closed['error'] is None
    assert closed['exact_executable_census_empty'] is True and closed['exact_executable_has_no_open_descriptors'] is True
    assert outcome['classification'] == 'valid-observation' and outcome['exit_code'] == 0
    assert all(outcome[k] is None for k in ['native_failure', 'monitor_error', 'closure_error', 'candidate_error'])
    assert outcome['native_issues'] == [] and outcome['observed_completed_cases'] == c['cases']
    configuration = obj('configuration.json')
    assert configuration['command_line_arguments'] == [] and 'SelectedLanguage' not in configuration['seed_preferences']
    proof = str(Path(identity['app_path']).parents[3])
    assert configuration['working_directory'] == configuration['RJT_LANGUAGE_SELECTION_EVIDENCE']
    assert configuration['LLVM_PROFILE_FILE'] == configuration['working_directory'] + '/profile-%p.profraw'
    profile = 'native/profile-' + str(live['host']['pid']) + '.profraw'
    assert profile in z.namelist() and len(z.read(profile)) > 0
    driver = (root / 'verify-language-selection-probe.py').read_bytes()
    assert digest(driver) == expected['source_sha256']['scripts/verify-language-selection-probe.py']
    tree = ast.parse(driver)
    names = {'receipt_errors', 'classify_native'}
    selected = ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names], type_ignores=[])
    namespace = {'json': json, 'math': math, 'struct': struct, 'digest': digest,
        'bundle_id': 'com.negentropi.RomaJustTalk', 'cases': c['cases'], 'native': root / 'artifact/native', 'output': root / 'artifact'}
    exec(compile(selected, 'pinned-observation-classifier', 'exec'), namespace)
    actual = namespace['classify_native'](identity, live['host'])
    assert actual['valid'] is True and actual == obj('native-classification.json')
    native = obj('native/result.json')
    assert native['primaryPersisted'] is True and native['positiveControlsPassed'] is True and native['exitCode'] == 0
    complete = obj('complete-result.json')
    assert complete['valid'] is True and complete['classification'] == 'passed' and complete['source_sha'] == head
    assert complete['native_receipt_sha256'] == digest(z.read('native/result.json'))
    result = obj('result.json')
    assert result['valid'] is True and result['classification'] == 'passed' and result['source_sha'] == head
    assert result['classification_sha256'] == digest(z.read('native-classification.json'))
    members = [{'path': i.filename, 'bytes': i.file_size, 'sha256': digest(z.read(i.filename)),
        'retained': not i.filename.endswith('.profraw')} for i in z.infolist()]
    receipt = {'classification': 'same-current-english-persists-on-tested-component', 'run_id': run_id,
        'url': run['url'], 'head': head, 'branch': branch, 'native_exit': 0, 'primary_persisted': True,
        'positive_controls_passed': True, 'source_files': len(expected['source_sha256']),
        'candidate_files': len(candidate), 'compiled_app_swift_inputs': len(swift_paths),
        'actual_package_trees': 41, 'fresh_signed_tcc_rows': len(tcc), 'host_pid': live['host']['pid'],
        'host_closed': True, 'screenshots': 7, 'artifact_id': metadata['id'], 'artifact_bytes': len(raw),
        'artifact_sha256': digest(raw), 'crc_members': len(members), 'download_count': 1,
        'archive_remote': str(archive), 'native_receipt_sha256': digest(z.read('native/result.json')),
        'baseline': native['baseline'], 'cases': native['cases'],
        'limits': ['Unchanged LanguageSelectionView.full component host with real unloaded model metadata only.',
            'No production UI fix or same-value Picker bug was established.',
            'Changed-language controls use Accessibility actions; requested off-scroll items are not physical clicks.',
            'No engine, ASR, provider, model usability/download, full Models composition, physical input or release proof.',
            'Raw runtime profile remains remote and is omitted from compact source evidence.',
            'Build/native log artifact not downloaded; compilation and before/after checks are bound workflow/driver receipts.']}
    (root / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (root / 'artifact-members.json').write_text(json.dumps(members, indent=2) + '\n')
    print(json.dumps({k: receipt[k] for k in ['classification', 'native_exit', 'source_files', 'candidate_files',
        'compiled_app_swift_inputs', 'actual_package_trees', 'host_pid', 'screenshots', 'artifact_sha256']}))
