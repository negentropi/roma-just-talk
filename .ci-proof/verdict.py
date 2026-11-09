"""Judge the live-typing probe reports: text during the hold when on, none until key-up when off."""
import json
import re
import sys
from pathlib import Path

evidence = Path(sys.argv[1])
MINIMUM_HOLD_MS = {'long': 8000, 'short': 3000, 'user': 8000}
BUNDLE = {'textedit': 'com.apple.TextEdit', 'chrome': 'com.google.Chrome'}


def words(text):
    return re.sub(r"[^a-z0-9']+", ' ', (text or '').lower().replace('’', "'")).split()


def word_error_rate(hypothesis, truth):
    previous = list(range(len(hypothesis) + 1))
    for i, expected in enumerate(truth, 1):
        current = [i]
        for j, actual in enumerate(hypothesis, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (expected != actual)))
        previous = current
    return previous[-1] / max(1, len(truth))


def live_typed(trace):
    for event in (trace or {}).get('events', []):
        if event['name'] == 'pipeline.live_typing_finished':
            match = re.search(r'typed=(true|false)', event.get('details', ''))
            return None if not match else match.group(1) == 'true'
    return None


def assess(fixture, target, mode):
    reference = (evidence / f'fixture-{fixture}.txt').read_text()
    report = json.loads((evidence / f'probe-{fixture}-{target}-{mode}.json').read_text())
    case = report['cases'][-1] if report.get('cases') else {}
    checks = {}
    summary = {'fixture': fixture, 'target': target, 'mode': mode, 'fatalError': report.get('fatalError'), 'caseError': case.get('error'), 'checks': checks}
    checks['probe ran without error'] = not report.get('fatalError') and not case.get('error') and case.get('role') == 'measured'
    down, up = case.get('keyDownUptime'), case.get('keyUpUptime')
    samples = case.get('samples', [])
    if down is None or up is None or not samples:
        checks['key-down, key-up and samples recorded'] = False
        return summary
    nonempty = [s for s in samples if (s['text'] or '').strip()]
    during_hold = [s for s in nonempty if down < s['uptime'] < up]
    # Samples are stored on change, so the one in effect at key-down also covers the hold.
    held = [s for s in samples if s['uptime'] <= down][-1:] + [s for s in samples if down < s['uptime'] < up]
    at_key_up = next((s['text'] or '' for s in reversed(samples) if s['uptime'] <= up), '')
    final = samples[-1]['text'] or ''
    history = (case.get('historyRows') or [{}])[-1].get('ZTEXT') or ''
    trace = case.get('latencyTrace')
    first = nonempty[0]['uptime'] if nonempty else None
    summary.update({
        'holdMilliseconds': round((up - down) * 1000),
        'firstTextAfterKeyDownMilliseconds': None if first is None else round((first - down) * 1000),
        'firstTextAfterKeyUpMilliseconds': None if first is None else round((first - up) * 1000),
        'firstTextAfterAudioStartMilliseconds': None if first is None or case.get('audioStartUptime') is None
            else round((first - case['audioStartUptime']) * 1000),
        'distinctTextValuesDuringHold': len({s['text'] for s in during_hold}),
        'textAtKeyUp': at_key_up,
        'finalText': final,
        'historyText': history,
        'liveTypedFromTrace': live_typed(trace),
        'finalVsHistoryWER': round(word_error_rate(words(final), words(history)), 3),
        'finalVsSpokenScriptWER': round(word_error_rate(words(final), words(reference)), 3),
        'frontmostDuringHold': sorted({s['frontmostBundleID'] or '<none>' for s in held}),
    })
    checks['Roma observed the shortcut and settled'] = bool(trace) and any(
        e['name'].startswith('shortcut.key_down') for e in trace['events']) and any(
        e['name'] == 'ui.engine_toggle.end' for e in trace['events'])
    checks[f"hold lasted at least {MINIMUM_HOLD_MS[fixture] // 1000} s"] = summary['holdMilliseconds'] >= MINIMUM_HOLD_MS[fixture]
    checks[f'{target} stayed frontmost during the hold'] = summary['frontmostDuringHold'] == [BUNDLE[target]]
    checks['final field text is non-empty'] = bool(words(final))
    checks['history saved the dictation'] = bool(words(history))
    # A remainder pasted on top of live-typed words would inflate the field past the saved transcript.
    checks['final field matches saved transcript (no duplicated words)'] = (
        summary['finalVsHistoryWER'] <= 0.15 and len(words(final)) <= len(words(history)) + 2)
    if mode == 'on':
        audio_end = case.get('audioFinishedUptime') or up
        last_change = max((s['uptime'] for s in during_hold), default=None)
        summary['lastHoldChangeBeforeAudioEndMilliseconds'] = None if last_change is None else round((audio_end - last_change) * 1000)
        summary['shrinksDuringHold'] = sum(1 for a, b in zip(held, held[1:]) if len(b['text'] or '') < len(a['text'] or ''))
        checks['field had text while Shift was still held'] = bool(during_hold)
        checks['trace reports live typing'] = summary['liveTypedFromTrace'] is True
        # The bug the user hit: live typing stopped seconds into a long dictation.
        checks['live text kept streaming until speech ended (last change < 3.5 s before audio end)'] = (
            last_change is not None and audio_end - last_change < 3.5)
        # The bug the user hit: release left half a sentence in the field.
        checks['field ends with exactly the saved transcript'] = words(final) == words(history) and bool(words(history))
    else:
        checks['field stayed empty until key-up'] = not during_hold and not at_key_up.strip()
        checks['first text appeared after key-up'] = first is not None and first > up
        checks['trace reports no live typing'] = summary['liveTypedFromTrace'] is False
    return summary


results = [assess(*spec.split(':')) for spec in (evidence / 'runs.txt').read_text().split()]
passed = all(r['checks'] and all(r['checks'].values()) for r in results)
verdict = {'passed': passed, 'results': results}
(evidence / 'verdict.json').write_text(json.dumps(verdict, indent=2) + '\n')
for result in results:
    print(f"== fixture={result['fixture']} target={result['target']} typeWhileSpeaking={result['mode']}")
    for name, ok in result['checks'].items():
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    for key in ('holdMilliseconds', 'firstTextAfterKeyDownMilliseconds', 'firstTextAfterKeyUpMilliseconds',
                'firstTextAfterAudioStartMilliseconds', 'liveTypedFromTrace', 'finalVsHistoryWER', 'finalVsSpokenScriptWER', 'lastHoldChangeBeforeAudioEndMilliseconds', 'shrinksDuringHold', 'textAtKeyUp', 'finalText', 'historyText'):
        print(f"  {key}: {result.get(key)!r}")
print('VERDICT:', 'PASS' if passed else 'FAIL')
sys.exit(0 if passed else 1)
