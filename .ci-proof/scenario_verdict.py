"""PROTOTYPE verdict for the Roma Stream input method across everyday and edge-case holds."""
import json
import re
import sys
from pathlib import Path

evidence = Path(sys.argv[1])
STREAM = 'com.negentropi.inputmethod.RomaStream'


def words(text):
    return re.sub(r"[^a-z0-9']+", ' ', (text or '').lower().replace('’', "'")).split()


results, passed = [], True
for spec in (evidence / 'runs.txt').read_text().split():
    fixture, target, mode, *rest = spec.split(':')
    scenario = rest[0] if rest else 'plain'
    report = json.loads((evidence / f'probe-{fixture}-{target}-{mode}-{scenario}.json').read_text())
    case = (report.get('cases') or [{}])[-1]
    samples = case.get('samples') or []
    down, up = case.get('keyDownUptime') or 0, case.get('keyUpUptime') or 0
    final = (samples[-1]['text'] if samples else '') or ''
    history = ((case.get('historyRows') or [{}])[-1].get('ZTEXT') or '')
    during = [s for s in samples if down < s['uptime'] < up]
    sources_during = sorted({s.get('inputSource') or '?' for s in during})
    checks = {
        'probe ran without error': not report.get('fatalError') and not case.get('error'),
        'input source restored after release': case.get('inputSourceAfter') == case.get('inputSourceBefore') != STREAM,
    }
    if scenario in ('plain', 'typing', 'clickaway'):
        checks['Roma Stream was the input source during the hold'] = STREAM in sources_during
    if scenario == 'plain':
        checks['guess visible in the field while Shift was held'] = any((s['text'] or '').strip() for s in during)
        checks['field ends with exactly the saved transcript'] = bool(words(history)) and words(final) == words(history)
    elif scenario in ('cancel', 'silence'):
        checks['no leftover text in the field'] = not final.strip()
    elif scenario == 'clickaway':
        checks['no leftover guess in the field that lost focus'] = not final.strip()
        checks['final text landed in the field focused at release'] = bool(words(history)) and words(case.get('otherFieldText')) == words(history)
    elif scenario == 'typing':
        checks['the typed X survived'] = 'X' in final
        checks['the transcript is in the field once'] = bool(words(history)) and ' '.join(words(final)).count(' '.join(words(history)[-4:])) == 1
    ok = all(checks.values())
    passed &= ok
    results.append({'run': spec, 'checks': checks, 'final': final, 'other': case.get('otherFieldText'), 'history': history,
                    'sourcesDuringHold': sources_during, 'before': case.get('inputSourceBefore'), 'after': case.get('inputSourceAfter')})
    print(f'== {spec}')
    for name, value in checks.items():
        print(f"  {'PASS' if value else 'FAIL'}  {name}")
    print(f'  sources during hold: {sources_during}; before={case.get("inputSourceBefore")} after={case.get("inputSourceAfter")}')
    print(f'  final field: {final!r}')
    if case.get('otherFieldText') is not None:
        print(f'  other field: {case.get("otherFieldText")!r}')
    print(f'  history: {history!r}')
(evidence / 'scenario-verdict.json').write_text(json.dumps({'passed': passed, 'results': results}, indent=2))
print('VERDICT:', 'PASS' if passed else 'FAIL')
sys.exit(0 if passed else 1)
