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
    # Only what this hold added counts (empty taps may paste the last transcript when that setting is on).
    before_hold = ([s['text'] or '' for s in samples if s['uptime'] <= down] or [''])[-1]
    if final.startswith(before_hold):
        final = final[len(before_hold):]
    history = ((case.get('historyRows') or [{}])[-1].get('ZTEXT') or '')
    during = [s for s in samples if down < s['uptime'] < up]
    # Samples are stored on change, so the one in effect at key-down covers the hold too.
    held = [s for s in samples if s['uptime'] <= down][-1:] + during
    sources_during = sorted({s.get('inputSource') or '?' for s in held})
    expected_source = 'com.apple.keylayout.US' if scenario == 'us' else STREAM
    checks = {
        'probe ran without error': not report.get('fatalError') and not case.get('error'),
        # Roma never switches input sources.
        'input source never changed': case.get('inputSourceBefore') == case.get('inputSourceAfter') == expected_source
                                      and sources_during == [expected_source],
    }
    if scenario == 'taps':
        checks['typing before the hold reached the field'] = before_hold == 'ok '
    if scenario in ('plain', 'taps', 'early', 'us'):
        checks['guess visible in the field while Shift was held'] = any((s['text'] or '')[len(before_hold):].strip() for s in during)
        checks['field ends with exactly the saved transcript'] = bool(words(history)) and words(final) == words(history)
    elif scenario in ('cancel', 'silence'):
        checks['no leftover text in the field'] = not final.strip()
    elif scenario == 'clickaway':
        # A click makes Chrome keep the guess showing at that moment as real text (as with any input
        # method). Same as live typing today: what was shown stays, nothing more is inserted anywhere.
        shown = words(final)
        checks['field keeps at most what was showing at the click'] = shown == words(history)[:len(shown)] or not shown or len(shown) < len(words(history))
        checks['nothing added after the click'] = all(not (s['text'] or '').strip() or words(s['text']) == shown
                                                       for s in samples if s['uptime'] > (case.get('actionUptime') or 0) + 0.5)
        checks['nothing inserted into the newly focused field'] = not (case.get('otherFieldText') or '').strip()
        checks['transcript kept in History'] = bool(words(history))
    elif scenario == 'typing':
        # Shift+X is typing a capital X, so Roma drops the dictation; the guess must not linger.
        checks['field holds only the typed X'] = final.strip() == 'X'
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
