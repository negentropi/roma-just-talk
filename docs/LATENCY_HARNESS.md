# Visible Text Latency Harness

This harness measures the real delay from the observed Roma hotkey release to the
expected transcript becoming visible in the currently focused macOS text field.
It is intentionally separate from normal CI because it needs a logged-in GUI
session, Accessibility permission for the terminal, a running Roma build, and a
real target app such as TextEdit, Notes, Safari, Slack, or Zed.

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

Each sample records the focused text field's existing marker count at hotkey
release and only passes when that count increases. This prevents repeated
samples from passing on marker text left by an earlier run, while still allowing
you to launch the harness first and then focus the target app before triggering
Roma.

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
