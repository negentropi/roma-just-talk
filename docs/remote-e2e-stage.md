# Remote E2E Stage

This workflow prepares the remote computer. Manual interaction remains the
default. The macOS distribution scenario preserves the downloaded artifact's
security state. Deterministic macOS smoke, full runtime, and iOS local-Whisper
scenarios can run before the optional hold.

The intended split:

1. Existing CI workflows produce reusable application artifacts.
2. Namespace downloads those artifacts and prepares a live macOS desktop.
3. A scripted scenario or a person controls the real desktop applications.
4. The stage uploads reports, screenshots, and logs after the scenario/hold.

## Start the stage

Run the `Prepare remote E2E stage` workflow manually.

Inputs:

- `target`: `macos`, `ios`, or `both`.
- `macos_artifact_run_id`: successful `Build roma just talk` workflow run containing the exact macOS artifact to exercise. Blank requires a green build from the stage tooling's exact source SHA.
- `runtime_helper_run_id`: optional build run containing the current Sonoma-compatible runtime helper. Whether selected or discovered, the helper must come from the stage tooling's exact source SHA, so a historical app artifact can use the current trusted test oracle.
- `macos_runner`: GitHub runner label backed by the requested macOS image. Use a separate pinned label for each OS lane.
- `macos_expected_version`: exact `sw_vers -productVersion` required by the test. Blank records but does not enforce the version.
- `macos_expected_build`: exact `sw_vers -buildVersion` required by `distribution-e2e`.
- `developer_dir`: optional Xcode app developer directory for that runner. Blank uses the runner's selected compatible Xcode.
- `macos_scenario`: `none`, `runtime-smoke`, `runtime-e2e`, or `distribution-e2e`.
- `macos_audio_artifact`: private Namespace artifact containing WAV fixtures. Full runtime requires it. Smoke uses a pinned public CC-BY-4.0 [podscripter FLEURS fixture](https://huggingface.co/datasets/podscripter-project/test-fixtures) when blank.
- `macos_repetitions`: `1`, `3`, or `5` repetitions per fixture/app after the smoke run.
- `ios_artifact_run_id`: successful `VoiceInk iOS single-repo migration` workflow run containing the exact Simulator artifact. Blank selects the latest green run.
- `ios_scenario`: `none` or `local-whisper-import`.
- `hold_minutes`: 0 to 60 minutes after setup/scenario. `distribution-e2e` consumes this window while waiting for Safari, Finder, and Gatekeeper interaction and therefore rejects `0`.

The stage downloads the macOS artifact unchanged and does not re-sign it. CI
builds and ad-hoc signs the external runtime helper once, then the selected Mac
runs that prebuilt helper without compiling it. The stage rejects app and helper
run IDs unless they are completed, successful, non-PR runs of
`voiceink-build.yml` from this repository. The helper must match the checked-out
stage tooling SHA. The app build, helper build, and distribution stage must also
report distinct Namespace runner instance names. The stage records its boot
session, then the distribution script independently requires absent Roma
preferences, TCC rows, installed copies, running processes, and model state.
Its evidence ties both
artifacts to their workflow run and source SHA. The
existing iOS migration workflow packages its Xcode-signed Simulator application
as `roma.just.talk.ios-simulator.app`, preserving App Group exchange between the
app and keyboard extension.

Runner profiles may attach the persistent runtime-model cache. Direct
`nscloud-macos-*` image labels require a previously absent cache path under that
job's runner-temporary directory and record the pre-state before creating it, so
an exact image lane never depends on a cache-volume label or preloaded model.
Both keep model files outside FluidAudio's live model directory until the first
distribution launch has passed.

The public smoke fixture's source, license, and re-encoding notice are recorded
in [the runtime harness guide](RUNTIME_E2E_HARNESS.md#autonomous-namespace-run).

Wait for the `Remote desktop ready` job to print `REMOTE E2E STAGE READY`. In Namespace, open that GitHub job and select **Remote Display**.

The direct CLI path is preferred for future Computer Use:

```bash
scripts/open-remote-e2e-stage.sh <github-run-id>
```

Local requirements: authenticated `nsc` and `jq`. See [Namespace CLI installation](https://namespace.so/docs/reference/cli/installation) and [`nsc vnc`](https://namespace.so/docs/reference/cli/vnc).

The helper uses `nsc github job list` and `nsc github job describe` to find the running job's Namespace instance ID, then executes:

```bash
nsc vnc <instance-id>
```

Omit the run ID only when one remote E2E stage is running. The helper then selects the newest matching stage.

## Prepared desktop

Depending on `target` and scenario, the remote Mac contains:

- ordinary macOS stage: `~/Applications/roma just talk.app`, launched with onboarding state reset;
- macOS distribution E2E: the untouched app below a newly mounted APFS volume under `/Volumes`, where Finder extracted it;
- iOS: a booted iPhone Simulator with `roma just talk` installed and launched.
- `~/Desktop/REMOTE E2E STAGE READY.txt`: human-readable handoff.
- `~/Desktop/Remote E2E Stage`: link to the machine-readable stage directory.
- `~/Desktop/Finish Remote E2E Stage.command`: ends the hold window early.

The stable future-agent contract is:

1. Run `scripts/open-remote-e2e-stage.sh <github-run-id>` to open the VNC client.
2. Wait for `Remote E2E Stage/READY` on the remote desktop.
3. Read `Remote E2E Stage/stage-manifest.json`.
4. Interact with the visible applications.
5. Save additional evidence into the manifest's `evidenceDirectory`.
6. Run `Finish Remote E2E Stage.command`.

Provisioning remains owned by this workflow. Manual interaction prompts and judgment
remain owned by Computer Use; the optional local-STT path is owned by the deterministic script.

## Download-to-launch distribution E2E

Choose `target=macos`, select `macos_scenario=distribution-e2e`, provide the
exact successful build run, set the runner label for the intended OS lane, set
`macos_expected_version` and `macos_expected_build` to the affected release,
and allow 30 to 60 minutes of interaction time. The distribution lane refuses
to start without both exact values.

This is not the installed-app runtime test with quarantine added afterward. It
starts on a fresh Apple Silicon runner and fails if Roma preferences, Roma TCC
rows, FluidAudio model state, an installed copy, a running process, disabled
Gatekeeper assessments, the wrong architecture, or the wrong exact macOS
product or build version already exist. The persistent model cache stays outside
FluidAudio's live directory until the downloaded app passes its initial
Gatekeeper and App Translocation launch.

The workflow downloads both forms of the selected Actions artifact:

1. the outer ZIP a person receives from the GitHub Actions web download; and
2. the inner `roma.just.talk.app.zip` after GitHub's artifact wrapper is removed.

It requires the outer ZIP hash to match GitHub's recorded artifact digest and
proves that the inner ZIP in the distributed wrapper matches the CLI download
before the user path starts. The scenario then:

1. asks GitHub's authenticated artifact endpoint for a short-lived download redirect for that exact artifact ID, opens the redirect in Safari, and downloads it to a newly mounted APFS volume. The redirect itself is never saved in evidence. APFS preserves the framework symlinks in the signed app bundle;
2. requires Safari quarantine and byte equality with the untouched outer ZIP already fetched from the selected Actions run;
3. asks the operator to double-click the outer ZIP in Finder, requires human confirmation that Finder and Archive Utility performed the extraction, and proves the exact inner ZIP inherited Safari quarantine;
4. asks the operator to double-click the inner ZIP, requires the same human confirmation for that separate extraction, proves the app inherited quarantine and still passes strict deep signature verification, and compares its minimum macOS version with the exact runner version;
5. hashes every regular file and symlink in the extracted app, performs the first launch while Gatekeeper still rejects it, and requires the operator to confirm the visible "Not Opened" dialog before using Privacy & Security, Open Anyway;
6. starts an approval-window process and log monitor before Open Anyway, requires the operator to confirm that the approved first-launch UI is visible and responsive, then requires the first observed PID to report finished AppKit launch, run through App Translocation as native ARM64, remain runnable without `SIGCONT`, map every bundle-relative Mach-O dependency discovered recursively from the active ARM64 executable graph, survive a stability interval without dyld or signature errors, and leave the full app bundle byte-identical to its pre-launch manifest. A second Roma PID, new Roma crash report, or approval-window dyld error invalidates the run; and
7. records that first-process verdict, then deliberately starts separate prewarm and transcription relaunches of the same extracted artifact. Every observed Roma PID must be recorded by the helper, run through App Translocation with the same executable hash, pass the same recursive signature and mapped-code checks through process exit, and have an explicit test-requested termination. A new crash report or unaccounted process invalidates the run. The lane also compares the complete file-and-symlink bundle manifest before and after runtime and writes a separate transcription verdict.

CI builds the runtime helper with a macOS 14.0 deployment target. Before changing
TCC or starting Roma runtime work, the target Mac runs that exact packaged helper
executable with `--help`, requires its own clean exit and expected output,
and records the host product version, build, architecture, helper hash, and
minimum OS. The helper uses the ScreenCaptureKit content-filter screenshot API
available on Sonoma, so the functional smoke keeps its rendered-pixel proof on
macOS 14 instead of falling back to Accessibility text alone. The selected Mac
never compiles this Swift 6.2 helper.

Open the running Namespace job's Remote Display as soon as the log prints
`DISTRIBUTION E2E BROWSER ACTION REQUIRED`. Follow
`~/Desktop/GATEKEEPER ACTION REQUIRED.txt`; the file updates at each manual
boundary. No script clicks Open Anyway, clears quarantine, modifies SIP, or
re-signs the app.

The four Desktop confirmation commands are human evidence. Run the two Finder
commands only after using Finder and Archive Utility for their named extraction.
Run the Gatekeeper command only after seeing and dismissing the actual "Not
Opened" dialog. Run the final command only after the approved Roma process shows
responsive first-launch UI. The verifier still checks the same PID and fails if
it stopped, died, did not finish AppKit launch, or did not run through App
Translocation.

Run Sonoma and Tahoe as separate jobs. A moving selector such as `14.x` or
`26.x` is useful for coverage but is not proof for 14.2.1 or 26.4.1 unless the
recorded product and build versions equal the requested release. The exact
identity check fails before Safari launches when the runner image is wrong. The
current app target is macOS 14.4, so an exact 14.2.1 lane will stop at the app
compatibility checkpoint until the separate Sonoma deployment work lands. That
failure must not be reported as a signing result.

## Fast macOS hypothesis check

Choose `target=macos`, set `macos_artifact_run_id` to an exact green build,
choose `macos_scenario=runtime-smoke`, leave `macos_audio_artifact` blank, and
use `hold_minutes=0`. The runner fetches the pinned public fixture through
Namespace's immutable-URL cache and verifies its SHA-256 before playback. Pass a
private Namespace WAV artifact only when a hypothesis needs that exact audio.

This lane answers whether a runtime idea survives one named quick-release fixture
of at most eight seconds in TextEdit and Safari, with both empty and existing-text
insertion. It runs the same
preflight, isolated target probe, real app, BlackHole route, Special shortcut,
trace, rendered-text, cleanup, and restoration checks as the full scenario. It
does not provide repeated latency or four-app coverage. Treat it as hypothesis
evidence, then run `runtime-e2e` on the final candidate.

When only `Tools/RuntimeE2EHarness`, its runtime scripts, or these docs changed,
reuse the last exact app build. Do not rebuild macOS or run iOS verification for
an unchanged app. Any app, shared-core, project, entitlement, build-setting, or
dependency change needs a new exact app artifact first.

The remote stage records a failed scenario without ending its cache-owning job,
uploads the evidence, and lets Namespace save the model cache. A separate
verdict job then fails the workflow. Red hypotheses therefore keep the same
failure signal while still warming the next run. Empty cache-volume forks do not
block on FluidAudio's model download. The runner verifies a pinned 22-file model
manifest and fetches only missing files through Namespace's immutable-URL cache
across four workers in parallel with machine setup.

## Deterministic macOS runtime E2E scenario

Choose `target=macos`, set `macos_artifact_run_id` to the exact green build,
choose `macos_scenario=runtime-e2e`, provide the private Namespace WAV artifact,
and use `hold_minutes=0` for a fully scripted run.

The scenario:

1. installs BlackHole 2ch, Chrome, and Visual Studio Code on the disposable VM;
2. preserves the downloaded Roma app signature and builds the external harness once;
3. grants exact-CDHash TCC rows only on that ephemeral Mac;
4. verifies the pinned public Parakeet V2 files and waits for Roma's real prewarm;
5. opens TextEdit, Safari, Chrome, and VS Code before the `runningOnly` harness starts;
6. proves isolated target setup/cleanup before involving Roma, audio, or Shift;
7. feeds each WAV into BlackHole, beginning audio `1.1s` before synthetic left-Shift down;
8. runs a four-case TextEdit/Safari smoke using one short fixture, then the requested repeated four-app matrix; and
9. uploads factual phase checkpoints and the first unproven boundary without assigning blame to Roma or the harness.

The TCC database writes are intentionally remote-only. They are not a local setup
mechanism and disappear with the Namespace VM.

## Deterministic iOS local STT scenario

Choose `target=ios`, set `ios_artifact_run_id` to the exact green build, choose
`ios_scenario=local-whisper-import`, and use `hold_minutes=0` for a fully scripted run.

The scenario:

1. installs AXe on the ephemeral Namespace runner when needed;
2. atomically downloads, verifies, and copies the pinned `ggml-base.bin` model into the app container;
3. generates a 16 kHz mono speech fixture with macOS `say`;
4. launches the actual app with onboarding complete and opens the fixture through the app's external-file route;
5. lets fresh-Simulator system banners settle, then uses AXe accessibility labels to start transcription and open transcript detail;
6. requires the normalized expected phrase and `Completed` state in the visible UI;
7. verifies a non-empty canonical WAV header and matching declared data length; and
8. uploads provenance, success or failure state, screenshots, accessibility trees, hashes, and logs.

This proves the built Simulator app's external-open, import, WAV preparation,
local Whisper, persistence, queue completion, and transcript-detail path. It does
not prove live microphone capture, recorder pre-roll, keyboard handoff, or physical-device routing.

## Evidence

The workflow uploads `remote-e2e-stage-evidence` containing:

- Simulator screenshots when iOS is selected;
- macOS and iOS application logs;
- macOS runtime preflight, target-probe, smoke, full report, failure-boundary summary, TCC rows, exact signatures/hashes, audio/model provenance, and restoration logs;
- distribution source and browser hashes, GitHub's artifact digest, exact artifact ID and sanitized redirect host, outer and inner quarantine records, APFS volume inventory, per-extraction human confirmations, Finder and Archive Utility process/log evidence, Gatekeeper assessments, approval-window PID events and crash-report baseline, source and translocated executable identity, native ARM64 process identity, recursively discovered active-slice code, observed mapped bundle code, signatures, process states, and unified logs;
- every runtime Roma PID, its translocated launch identity, lifetime mapped-code evidence, explicit termination intent, and pre/post crash-report inventories;
- app and runtime-helper workflow run IDs, source SHAs, workflow identity, archive and executable hashes, plus the helper's target-host loadability result;
- macOS, Xcode, and Simulator inventory.

Namespace VNC can be active while `screencapture` remains unable to see that display from the runner shell. The workflow records this condition instead of silently claiming a desktop screenshot. The VNC controller or future Computer Use skill owns macOS desktop screenshots.

## Boundaries

- iOS means iOS Simulator on the remote Mac, not a physical iPhone.
- Microphone availability is not assumed; the deterministic STT scenario uses a generated audio file.
- Manual stages do not pre-grant Accessibility, Input Monitoring, Screen Recording, or other TCC permissions.
- `distribution-e2e` requires a person or authorized Computer Use session for Safari's site-download prompt, both Finder extractions, and Gatekeeper Open Anyway. Missing interaction times out and fails.
- Both macOS runtime scenarios grant only the exact helper/Roma permissions needed on their disposable VM and verify the real global-shortcut/audio-input path.
- The optional local-STT scenario performs narrow AXe UI assertions; XCUITest remains a separate fast gate.
