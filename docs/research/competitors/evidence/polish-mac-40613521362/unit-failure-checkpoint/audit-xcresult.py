import hashlib
import json
import pathlib
import sys

registry_path, candidate_path, baseline_path, out_path = map(pathlib.Path, sys.argv[1:5])
registry = json.loads(registry_path.read_text())
candidate = json.loads(candidate_path.read_text())
baseline = json.loads(baseline_path.read_text())
assert candidate['run_id'] == registry['run_id']
assert baseline['run_id'] == 40607608894
candidate_cases = candidate.get('case_details', candidate.get('case_summaries'))
baseline_cases = baseline.get('case_details', baseline.get('case_summaries'))
assert isinstance(candidate_cases, list) and isinstance(baseline_cases, list)
result = {
    'run_id': registry['run_id'], 'head_sha': registry['head_sha'],
    'boundary': 'Concrete decoded xcresult case records, not raw console start counts',
    'candidate_decoded_sha256': hashlib.sha256(candidate_path.read_bytes()).hexdigest(),
    'baseline_result_sha256': hashlib.sha256(baseline_path.read_bytes()).hexdigest(),
    'groups': {}, 'former_failures': [],
}

def get_case(rows, identifier, status):
    matches = [case for case in rows if case['identifier'] == identifier]
    assert len(matches) == 1, (identifier, len(matches))
    case = matches[0]
    assert case['status'] == status, (identifier, case['status'])
    issues = [issue for issue in case.get('failure_summaries', case.get('failures', []))
              if isinstance(issue, dict) and issue.get('message')]
    if status == 'Success':
        assert not issues, (identifier, issues)
    assert len(case['decoded_summary_sha256']) == 64
    return {
        'identifier': identifier, 'status': case['status'], 'records': len(matches),
        'summary_reference': case['summary_reference'],
        'decoded_summary_sha256': case['decoded_summary_sha256'], 'issues': issues,
    }

for path, methods in registry['positive_registry'].items():
    group = pathlib.Path(path).stem
    # Clipboard's suite is top-level; the other suites extend VoiceInkTests.
    prefix = '' if group == 'ClipboardRestorationOwnershipTests' else 'VoiceInkTests/'
    values = []
    for method in methods:
        identifier = prefix + group + '/' + method + '()'
        value = get_case(candidate_cases, identifier, 'Success')
        if group != 'DictionaryPersistenceIsolationTests':
            value['baseline'] = get_case(baseline_cases, identifier, 'Success')
        values.append(value)
    result['groups'][path] = values

failure_groups = {
    'failedApprovalSaveKeepsExistingRulesAndUnrelatedUnsavedEdits': ('HistoryCorrectionApprovalTests', 2),
    'failedSaveRemovesOnlyImportInsertionsAndPreservesUnrelatedDirtyEdits': ('WordReplacementBackupAdapterTests', 1),
    'failedEditToggleAndDeleteRestoreOnlyTheirOwnEntry': ('WordReplacementLibraryAdapterTests', 2),
}
for method in registry['known_red_registry']:
    group, issue_count = failure_groups[method]
    identifier = 'VoiceInkTests/' + group + '/' + method + '()'
    value = get_case(candidate_cases, identifier, 'Success')
    value['baseline'] = get_case(baseline_cases, identifier, 'Failure')
    assert len(value['baseline']['issues']) == issue_count
    result['former_failures'].append(value)

assert sum(map(len, result['groups'].values())) == 41
assert len(result['former_failures']) == 3
result.update(selected_success_count=44, new_success_count=4,
              old_positive_success_count=37, formerly_failed_success_count=3)
out_path.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: value for key, value in result.items()
                  if key not in ['groups', 'former_failures']}, indent=2))
