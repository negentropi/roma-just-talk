#!/usr/bin/env python3
"""Reconcile retained original artifact bytes, cases and exact-text boundaries."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
def read(name):
    return json.loads((root / name).read_text())
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for item in read('artifact-origins.json')['retained_raw_members']:
    path = root / 'raw' / item['relative']
    assert path.stat().st_size == item['bytes']
    assert sha(path) == item['sha256'], path
for item in read('source-pins.json')['files']:
    path = root / 'source' / item['path']
    assert path.stat().st_size == item['bytes'] and sha(path) == item['sha256']
for item in read('extra-origins.json'):
    assert sha(root / 'verification-mode.json') == item['sha256']
mode = read('verification-mode.json')
assert mode == {'sourceSHA': '5ebb28bf7cdf9eab80b33032543e5af36d769a3e', 'mode': 'ui-only', 'fullGateRequired': True}
summary = read('ui-case-summary.json')
assert len(summary['tests']) == 8
assert all(x['starts'] == 1 and len(x['results']) == 1 for x in summary['tests'].values())
assert sum(x['results'] == ['passed'] for x in summary['tests'].values()) == 6
assert len(summary['failures']) == 2 and all(x['line'] == 648 for x in summary['failures'])
rows = {x['id']: x for x in read('raw/candidate/history-seed/seed/expected-rows.json')}
copies = read('history-copy-audit.json')['receipts']
assert len(copies) == 9
bycase = {}
fields = {'recognized': 'recognitionText', 'original': 'text', 'enhanced': 'enhancedText'}
for item in copies:
    actual = item['observed']
    expected = rows[item['rowID']][fields[item['variant']]]
    assert actual['actualUTF8'] == expected['utf8']
    assert actual['actualUTF16'] == expected['utf16']
    assert actual['changeCount'] != actual['previousChangeCount']
    bycase[item['case']] = item['rowID']
statics = read('static-AX-independent-audit.json')['records']
assert len(statics) == 9
for item in statics:
    expected = rows[item['rowID']][fields[item['variant']]]
    assert item['rawStatic']['actualUTF8'] == expected['utf8']
    assert item['rawStatic']['actualUTF16'] == expected['utf16']
captured = read('captured-source-static-audit.json')['observed']
assert len(captured) == 2
for item in captured:
    expected = rows[bycase[item['case']]]['recognitionText']
    assert item['actualUTF8'] == expected['utf8'] and item['actualUTF16'] == expected['utf16']
verdict = read('raw/candidate/verification-verdicts.json')
assert verdict['boundary'] == 'ui-tests' and verdict['driver_exit_code'] == 65
assert verdict['native']['classification'] == 'blocked' and verdict['native']['attempted'] is False
assert verdict['native']['phases']['seed']['result']['valid'] is True
assert verdict['native']['phases']['verify']['testAttempted'] is False
censuses = read('shortcut-censuses.json')
assert len(censuses) == 8
for case in censuses:
    phases = case['phases']
    assert all(x['synchronized'] for x in phases)
    assert next(x['keys'] for x in phases if x['phase'] == 'before') == next(x['keys'] for x in phases if x['phase'] == 'restored')
for item in read('screenshots/origins.json'):
    assert sha(root / item['file']) == item['sha256']
    assert item['source_video_sha256'] == item['original_xcresult_attachment']['payload_sha256']
print('PASS: retained bytes; UI8once6pass2fail648; Copy9+Static9+capturedStatic2 seed-exact; postverify blocked; shortcut restore; frame origins. Fullgate not accepted.')
