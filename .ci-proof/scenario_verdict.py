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
    final = raw_final = (samples[-1]['text'] if samples else '') or ''
    ime_log = case.get('imeLog') or []
    action = case.get('actionUptime') or 0
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
    if scenario in ('plain', 'taps', 'early'):
        # The text came through Roma Stream's composition, not some other path.
        checks['guess shown as composition and committed by Roma Stream'] = (
            any(line.startswith('marked ') for line in ime_log) and any(line.startswith('commit ') and 'refused' not in line for line in ime_log))
    if scenario == 'us':
        checks['Roma Stream stayed out of it'] = not any(line.startswith('marked ') for line in ime_log)
    if scenario in ('plain', 'taps', 'early', 'us'):
        checks['guess visible in the field while Shift was held'] = any((s['text'] or '')[len(before_hold):].strip() for s in during)
        checks['field ends with exactly the saved transcript'] = bool(words(history)) and words(final) == words(history)
    if scenario in ('plain', 'taps', 'early'):
        # Release must feel like today's paste. Both wait for the recognizer's final pass (0.3-1.3 s on
        # hosted runners); Roma Stream's own step after it must stay as quick as a paste.
        events = {e['name']: e['totalMilliseconds'] for e in (case.get('latencyTrace') or {}).get('events') or []}
        ready, inserted = events.get('pipeline.transcribe.end'), events.get('pipeline.paste_command.end')
        added = None if ready is None or inserted is None else round(inserted - ready)
        landed = next((s['uptime'] for s in samples if s['uptime'] >= up and words((s['text'] or '')[len(before_hold):]) == words(history)), None)
        release_delay = None if landed is None else round(landed - up, 2)
        checks[f'insert adds at most 150 ms after the transcript is ready ({added} ms; release to text {release_delay} s)'] = (
            added is not None and added <= 150 and release_delay is not None)
    elif scenario in ('cancel', 'silence'):
        if scenario == 'cancel':
            checks['a guess was showing when Esc was pressed'] = bool((case.get('textAtAction') or '').strip())
        checks['no leftover text in the field'] = not final.strip()
    elif scenario == 'selectcancel':
        checks['Roma Stream declined to cover the selection'] = (
            any('text selected' in line for line in ime_log) and not any(line.startswith('marked ') for line in ime_log))
        checks['selected text survives the cancel'] = raw_final.strip() == 'keep'
    elif scenario == 'clickaway':
        # A click makes Chrome keep the guess showing at that moment as real text (as with any input
        # method). Same as live typing today: what was shown stays, nothing more is inserted anywhere.
        at_click = case.get('textAtAction') or ''
        checks['a guess was showing at the click'] = bool(words(at_click))
        checks['the click moved focus to the other field'] = case.get('focusedAfterAction') == 'Roma other field'
        checks['field keeps exactly the guess shown at the click'] = words(final) == words(at_click)
        checks['nothing inserted into the newly focused field'] = case.get('otherFieldText') is not None and not case['otherFieldText'].strip()
        checks['transcript kept in History'] = bool(words(history))
    elif scenario == 'typing':
        # Shift+X is typing a capital X, so Roma drops the dictation; the guess must not linger.
        checks['a guess was showing when X was typed'] = bool((case.get('textAtAction') or '').strip())
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
