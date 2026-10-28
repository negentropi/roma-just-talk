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
assert mode == {'sourceSHA': '004c1cfd61492428c0a5caacf65b2f686de59a14', 'mode': 'ui-only', 'fullGateRequired': True}
summary = read('ui-case-summary.json')
assert len(summary['tests']) == 8
assert all(x['starts'] == 1 and len(x['results']) == 1 for x in summary['tests'].values())
assert sum(x['results'] == ['passed'] for x in summary['tests'].values()) == 7
assert len(summary['failures']) == 1 and all(x['line'] == 486 for x in summary['failures'])
rows = {x['id']: x for x in read('raw/candidate/history-seed/seed/expected-rows.json')}
copies = read('history-copy-audit.json')['receipts']
assert len(copies) == 11
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
assert len(statics) == 11
for item in statics:
    expected = rows[item['rowID']][fields[item['variant']]]
    assert item['rawStatic']['actualUTF8'] == expected['utf8']
    assert item['rawStatic']['actualUTF16'] == expected['utf16']
captured = read('additional-static-audit.json')['observed']
assert len(captured) == 10
for item in captured:
    expected = item['expected']
    assert item['actualUTF8'] == list(expected.encode('utf-8'))
    raw = expected.encode('utf-16-le')
    assert item['actualUTF16'] == [int.from_bytes(raw[i:i+2], 'little') for i in range(0, len(raw), 2)]
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
print('PASS: retained bytes; UI8once7pass1fail486; Copy11+Static11 seed-exact; source3+preview7 exact; postverify blocked; shortcut restore; frame origins. Fullgate not accepted.')
