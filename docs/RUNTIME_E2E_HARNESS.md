# Autonomous Runtime E2E Harness

This helper drives a real Roma build through the complete macOS path:

```text
WAV fixture -> BlackHole 2ch -> Roma microphone input
timed left Shift down/up ------> Special shortcut
Roma paste --------------------> isolated real-app text field
AX text + rendered pixels -----> user-visible timestamp
LatencyTrace ------------------> app phase timestamps
```

It is external to the production app. The helper does not add test hooks to
VoiceInk or bypass CoreAudio, global shortcuts, transcription, clipboard paste,
target-app focus, Accessibility observation, or rendered-screen verification.
The report keeps Accessibility value arrival separate from first stable screen
pixels so AX state is never presented as proof that a person could already see
the text. Pixel sampling starts at key-up, independently of AX arrival, and a
render is accepted only after two baseline-different frames are also mutually
stable. AX may arrive later without moving the earlier rendered timestamp.

## Default Matrix

- Audio: every supported fixture under `~/Downloads/roma jt builds/audio/`
- Audio lead: `1.1s` before left-Shift key-down
- Release: `150ms` after the fixture ends
- Repetitions: `3`
- Text baselines: empty, plus `[existing before]{cursor}[existing after]`
- Candidate apps: TextEdit, Safari, Google Chrome, Arc, Zed, and Visual Studio Code
- Local target policy: `runningOnly`; closed apps are skipped, never launched
- Coverage gate: at least `4` distinct candidate apps must already be running
- Rendered-text timeout: `20s`
- Rendered-text p95 budget: `250ms`
- Transcript answer: optional until supplied in the config

Each selected browser opens an isolated local tab with a uniquely titled,
controlled contenteditable. It accepts only paste-backed DOM `input` events,
records DOM `paste` and accepted-input counts in the report, and passes only
when exactly one of each occurred. This matches web apps that reject
Accessibility-only value mutation. When a cold browser keeps its app-menu Paste
command disabled, Roma refreshes that command by opening and closing its
containing app menu. If Paste remains unavailable, Roma asks the captured editor
(or one of its ancestors) to show its context menu through Accessibility. When
Chromium does not advertise that action, Roma right-clicks the AX-reported caret
only after a system hit-test resolves back to the captured editor. It accepts
only an activated menu that owns that same screen point, then presses enabled
Paste and confirms the exact
replacement before reporting delivery. Browser fallbacks stay bound to that
editor's unchanged text and selection; drift aborts without a recaptured,
keyboard-triggered, or Cmd-V CGEvent paste.
Document and
Electron editor apps open a uniquely named temporary text file. Every target
runs once empty and once with text on both sides of the insertion cursor.
Cleanup saves an empty temporary document before closing its tab/window, removes
the resource, terminates only a target process started by the harness, restores
an initially running target if closing its last isolated surface exits it, and
restores the previously frontmost app. Existing documents and pages are not used
as test targets.

Set `targetAvailabilityPolicy` to `launchIfNeeded` only on a dedicated test Mac.
The local default remains `runningOnly` to avoid memory pressure and surprise app
launches. `minimumTargetCount` controls the distinct-app coverage gate.

Runtime execution for this project is Namespace-first. Local commands below are
opt-in tools for a dedicated test Mac; CI/static checks never launch Roma or
change the frontmost application.

## Autonomous Namespace Run

Run `Prepare remote E2E stage` with:

- `target=macos`
- `macos_scenario=runtime-e2e`
- `macos_artifact_run_id=<exact green app build>`
- `macos_audio_artifact=<private Namespace ZIP containing WAV fixtures>`
- `macos_repetitions=3`
- `hold_minutes=0`

The disposable Namespace Mac installs BlackHole, Chrome, and Visual Studio Code;
opens TextEdit, Safari, Chrome, and VS Code; and keeps the harness policy at
`runningOnly`. It grants Accessibility/Input Monitoring/Microphone only inside
that ephemeral VM. The helper also receives Screen Recording solely for
pixel-level target observation. Grants remain keyed to the exact ad-hoc CDHashes
of the downloaded Roma app and the one-time-built helper. It never re-signs the
production Roma artifact.

Before sampling, the scenario waits for the real Parakeet V2 download and app
prewarm. It then runs deterministic checks, a four-app, two-baseline target probe, one
functional repetition with a relaxed latency ceiling, and the requested repeated
matrix with the `250ms` budget. A functional-smoke failure is retained but does
not suppress the repeated matrix. All JSON reports, phase stdout/stderr, TCC rows,
signatures, hashes, model/audio provenance, app logs, and restoration results are
uploaded as `remote-e2e-stage-evidence` even when a phase fails.

## Isolation Gates

Run target automation without Roma, audio, or shortcut input first:

```bash
make runtime-e2e-target-probe
```

This proves only test-tab/document discovery, focus, empty and middle-cursor AX
baselines, scoped close, and cleanup. A target-probe failure is not reported as a Roma failure.
The separate `--audio-probe` mode validates fixture decoding, transactional
BlackHole control setup, Roma device selection, and playback-process completion.
It does not prove that non-silent PCM reached Roma. Only a full case with Roma
capture/transcription trace evidence and target text proves the complete route.

## What Fails a Case

- Target app missing, not activated, unreadable through AX, or not cleared
- Existing text on either side of the insertion cursor is changed or lost
- WAV cannot play into BlackHole
- Synthetic Special left Shift is not accepted by VoiceInk
- Posted Shift hold and VoiceInk-observed hold differ by more than `150ms`
- No new `LatencyTrace` is emitted
- VoiceInk starts a trace but never completes transcription
- VoiceInk completes transcription with zero characters (`emptyTranscript`)
- VoiceInk posts no text into the target
- Clipboard changes but the target remains empty (`clipboardOnly`)
- Accessibility text arrives but stable changed pixels never render
- Rendered text exceeds the latency budget
- Expected transcript exceeds the configured word-error-rate limit
- Target tab/document or temporary resources cannot be restored

The report preserves each failure instead of dropping it from percentile
calculations. Per-app and overall summaries include total, passed, failed,
no-visible-paste count, p50, p95, and maximum visible-text latency.

An unanswered or denied microphone request is attributed to
`voiceInkMicrophonePermission`, before transcription classification. An empty
transcription is attributed to `voiceInkTranscription`, even if VoiceInk
subsequently writes or posts whitespace. It is never counted as a clipboard,
paste-delivery, or target-visibility failure.

Each case also records factual checkpoints: target prepared, audio started,
shortcut down/up posted, Roma trigger observed, app-observed shortcut hold matched,
transcription completed,
clipboard write succeeded, paste event posted, AX text observed, stable rendered
pixels observed, and target cleanup passed. `failureBoundary` names the first
unproven boundary; it does not guess which component owns the failure.

`shortcutDelivery` means the helper's posted hold and Roma's trace disagree. It
does not assume whether the synthetic injector, macOS delivery, competing input,
or Roma's monitor caused the mismatch.

Latency is split into:

- `voiceInkKeyUpToPasteEventMilliseconds`: Roma trace from shortcut key-up handler
  to paste-event post
- `visibleText.keyUpToAccessibilityTextMilliseconds`: first non-empty AX value;
  useful for paste delivery, but not proof of rendered visibility
- `visibleText.keyUpToVisibleMilliseconds`: first two stable changed pixel frames
  in the exact editable screen rectangle
- `pasteEventToVisibleMilliseconds`: remaining time from Roma's post until the
  rendered-pixel observation
- `voiceInkKeyUpToPipelineCompleteMilliseconds`: Roma post-processing and save
  completion
- `voiceInkKeyUpToInteractionSettledMilliseconds`: final recorder toggle return,
  matching the longer endpoint a human may perceive

The rendered span intentionally remains an end-to-end delivery/visibility
boundary. It includes target rendering and any occlusion inside the sampled
rectangle; the harness does not assign it to Roma, the target app, focus, or
scheduling without further evidence.

## Safety and Restoration

Before a run, the helper records:

- VoiceInk microphone mode and selected-device UID
- exact running VoiceInk bundle paths
- system default output-device UID
- BlackHole input/output mute and volume controls when supported

It then selects BlackHole for both sides, unmutes both scopes, normalizes
supported volumes for playback, and launches the exact selected Roma artifact.
On completion or handled failure it restores the original preferences, output
device, BlackHole controls, and running state. It also scans
`/tmp/roma-runtime-e2e-targets` for abandoned test tabs/documents before a run.
Journals under `/tmp/` allow recovery after an interrupted process:

```bash
make runtime-e2e-restore
```

The exact Roma app is selected in this order:

1. `voiceInkAppPath` from config
2. a running app inside the configured build directory
3. the newest matching `.app` directly under `~/Downloads/roma jt builds/`
4. another running matching app
5. the LaunchServices-installed matching app

## Build and Permissions

Build the helper only after code changes are finished:

```bash
make runtime-e2e-app
```

Grant `.local-build/Tools/RuntimeE2EHarness.app` in:

`System Settings -> Privacy & Security -> Accessibility`

`System Settings -> Privacy & Security -> Screen Recording`

Do not rebuild or re-sign afterward. `runtime-e2e-run` intentionally has no
dependency on the build/app targets so the TCC identity remains stable.

Verify readiness:

```bash
make runtime-e2e-preflight
```

Preflight reports selected and skipped target IDs and fails unless macOS 15.2+,
Accessibility, Screen Recording, fixtures, BlackHole, the exact Roma build, and the
four-running-app gate are all ready. The explicit preflight command requests any
missing Accessibility or Screen Recording grant; normal run mode never prompts.

## Run

Default full matrix:

```bash
make runtime-e2e-run
```

The default case count is `fixtures x currently-running selected apps x 2 text baselines x 3`; the
four-app minimum is enforced before Roma or audio state changes.

Custom manifest:

```bash
cp Tools/RuntimeE2EHarness/runtime-e2e.example.json /tmp/roma-runtime-e2e.json
make runtime-e2e-run RUNTIME_E2E_CONFIG=/tmp/roma-runtime-e2e.json
```

Add fixture answers by filename:

```json
{
  "expectedTranscripts": {
    "normal noisy clear.wav": "the correct words",
    "normal wispering.wav": "the correct whispered words"
  }
}
```

Use the complete example manifest rather than a partial JSON object; all fields
are explicit so experiment changes remain reviewable.

The default report is written to:

`.local-build/Tools/runtime-e2e-report.json`

## CI Boundary

`make runtime-e2e-check` runs deterministic public-interface checks, compiles the
helper, and verifies that preflight, target-probe, and run targets cannot rebuild,
delete, or re-sign the TCC app. Real GUI/audio sampling runs only in the logged-in
Namespace macOS scenario unless a person explicitly opts into a dedicated local
test Mac.
