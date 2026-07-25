# Visible Text Latency Harness

This harness measures the real delay from the observed Roma hotkey release to the
expected transcript becoming visible in the currently focused macOS text field.
It is intentionally separate from normal CI because it needs a logged-in GUI
session, Accessibility permission for the terminal, a running Roma build, and a
real target app such as TextEdit, Notes, Safari, Slack, or Zed.

## Latency Architecture Contract

- Pre-roll retains raw audio only; it must not start speculative transcription before key-down.
- Key-down starts the ordinary recording and streaming path.
- Granted microphone permission continues on the current recording task; it must not add a callback-to-MainActor task hop.
- With zero Power Mode configurations, skip automatic resolution and prepare the ordinary transcription session before awaiting recorder startup. If a configuration could change the model, resolve and activate it before preparing that session.
- Key-up commits an established stream when ready. If startup is still pending and the model supports recorded-file transcription, cancel that startup and use the recorded-file fallback without waiting.
- Recorder stop stays serialized on its audio setup queue, but the measured warm stop completes inline instead of adding an async continuation-resume hop.
- Streaming-only models may wait for their connection because no recorded-file fallback exists.
- Local model prewarm loads the selected runtime directly; it must not depend on transcribing a bundled UI sound.
- Whisper prewarm reuses a loaded context only when it belongs to the currently selected model.
- FluidAudio may reuse a hypothesis only when the ordinary post-key-down session produced it and it covers every captured sample; missing or incomplete hypotheses require final ASR.

Shared-core checks lock the startup-resolution and direct-prewarm policies. This harness is the end-to-end proof that those policies still produce visible text within the latency budget.

## Deep Runtime Trace

Every recording emits a bounded `LatencyTrace` timeline. Events share one trace ID,
monotonic milliseconds from shortcut key-down, time since the previous event, and
an ordered sequence number. The trace includes recorder startup/stop, Power Mode
resolution, streaming connection and backlog drain, final ASR, cleanup, paste
event posting, clipboard-restore scheduling, and persistence. Shortcut events also
report physical-event-to-main-callback and main-callback-to-handler delay, so queued
key-up work cannot disappear before the first handler timestamp. Trace tokens reject
late events from older recordings; replacing an unfinished trace emits
`trace.replaced`. Counts and state only are recorded, never transcript, URL, or
clipboard contents. FluidAudio traces also distinguish complete-hypothesis reuse
from final-ASR fallback.

Scheduler boundaries emit paired `*.executor_enqueued` and `*.executor_resumed`
events. The resume event includes `queueDelayMs`, measured from producer completion
or task creation to the first instruction running on the destination executor. This
keeps executor starvation separate from the surrounding span's actual audio, model,
network, or persistence work.

```bash
log stream --style compact \
  --predicate 'subsystem == "com.prakashjoshipax.voiceink" && category == "LatencyTrace"'
```

Use this trace before changing latency behavior. A green build, successful prewarm,
or fast ASR alone does not prove the key-up-to-visible-text path is fast.
`paste_event_posted` is only the app-to-macOS handoff. The visible-text harness below
supplies the terminal timestamp after the focused app actually exposes the new text.

## Build

```bash
make latency-harness-build
```

The binary is written to `.local-build/Tools/VisibleTextLatencyHarness`.

For a stable TCC target, build the helper app:

```bash
make latency-harness-app
```

The helper app is written to `.local-build/Tools/VisibleTextLatencyHarness.app`
with the stable bundle ID `com.happyf.roma-just-talk.VisibleTextLatencyHarness`
and local ad-hoc signing. Grant this helper app in System Settings when Codex or
another nonstandard launcher cannot be attributed cleanly by macOS.

Build the helper before granting Accessibility. After the grant, use
`latency-harness-app-run` without rebuilding so macOS keeps attributing the run
to the same helper app identity.

## Run

1. Grant Accessibility permission to the normal terminal app you run the CLI
   harness from, or grant the `VisibleTextLatencyHarness.app` helper app.
2. Start the Roma build being tested.
3. Focus a text field in the target app.
4. Use a unique phrase for `LATENCY_EXPECTED`, then dictate that exact phrase.

```bash
make latency-harness-run LATENCY_EXPECTED="roma latency marker" LATENCY_SAMPLES=10
```

Use the helper app when TCC should grant the harness itself instead of the shell:

```bash
make latency-harness-app
# Grant .local-build/Tools/VisibleTextLatencyHarness.app in System Settings.
make latency-harness-app-run LATENCY_EXPECTED="roma latency marker" LATENCY_SAMPLES=10
```

Default trigger is `left-shift`, matching the common modifier-only shortcut.
Override it when testing another shortcut:

```bash
make latency-harness-run \
  LATENCY_EXPECTED="roma latency marker" \
  LATENCY_TRIGGER=right-command \
  LATENCY_SAMPLES=10
```

Supported triggers:

- `left-shift`
- `right-shift`
- `left-command`
- `right-command`
- `left-option`
- `right-option`
- `left-control`
- `right-control`
- `key-code:<number>`
- `any-key-up`

## Pass Criteria

The harness fails when any sample does not make the expected text visible before
the timeout, or when p95 visible-text latency exceeds `440ms`. Samples at or
below `220ms` are labeled `BEST`.

Each sample records the focused text field's existing marker count when the
hotkey press is observed, before release, and only passes when that count
increases after release. This prevents repeated samples from passing on marker
text left by an earlier run without missing very fast insertions. If no matching
press is observed, the sample falls back to a release-time baseline and reports
that fallback in JSON with `baselineCapturedBeforeRelease: false`.

If the expected text reaches the clipboard but not the focused text field before
timeout, the result is classified as `clipboard-only`.

If macOS does not expose a focused `AXValue` text surface to the harness, the
sample is classified as `focused-text-unreadable` and the JSON includes the AX
error. This usually means the helper app still needs Accessibility, the target
field is not focused, or the app does not expose editable text through AXValue.

## JSON Output

For machine-readable reports:

```bash
.local-build/Tools/VisibleTextLatencyHarness \
  --expected "roma latency marker" \
  --samples 10 \
  --json-output /tmp/roma-visible-latency.json
```
