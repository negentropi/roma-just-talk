# Remote E2E Stage

This workflow prepares the remote computer. Manual interaction remains the
default. Deterministic macOS runtime and iOS local-Whisper scenarios can run
before the optional hold.

The intended split:

1. Existing CI workflows produce reusable application artifacts.
2. Namespace downloads those artifacts and prepares a live macOS desktop.
3. A scripted scenario or a person controls the real desktop applications.
4. The stage uploads reports, screenshots, and logs after the scenario/hold.

## Start the stage

Run the `Prepare remote E2E stage` workflow manually.

Inputs:

- `target`: `macos`, `ios`, or `both`.
- `macos_artifact_run_id`: successful `Build roma just talk` workflow run containing the exact macOS artifact to exercise. Blank selects the latest green build.
- `macos_scenario`: `none` or `runtime-e2e`.
- `macos_audio_artifact`: private Namespace artifact containing the WAV fixtures; required by `runtime-e2e`.
- `macos_repetitions`: `1`, `3`, or `5` repetitions per fixture/app after the smoke run.
- `ios_artifact_run_id`: successful `VoiceInk iOS single-repo migration` workflow run containing the exact Simulator artifact. Blank selects the latest green run.
- `ios_scenario`: `none` or `local-whisper-import`.
- `hold_minutes`: 0 to 60 minutes after setup/scenario. Use `0` to upload evidence immediately.

The stage downloads the macOS artifact unchanged and does not re-sign it. The
macOS runtime scenario builds and ad-hoc signs only its external helper. The
existing iOS migration workflow packages its Xcode-signed Simulator application
as `roma.just.talk.ios-simulator.app`, preserving App Group exchange between the
app and keyboard extension.

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

Depending on `target`, the remote Mac contains:

- macOS: `~/Applications/roma just talk.app`, launched with onboarding state reset.
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

## Deterministic macOS runtime E2E scenario

Choose `target=macos`, set `macos_artifact_run_id` to the exact green build,
choose `macos_scenario=runtime-e2e`, provide the private Namespace WAV artifact,
and use `hold_minutes=0` for a fully scripted run.

The scenario:

1. installs BlackHole 2ch and Visual Studio Code on the disposable VM;
2. preserves the downloaded Roma app signature and builds the external harness once;
3. grants exact-CDHash TCC rows only on that ephemeral Mac;
4. waits for Roma's real Parakeet V2 model download and prewarm;
5. opens TextEdit, Safari, Chrome, and VS Code before the `runningOnly` harness starts;
6. proves isolated target setup/cleanup before involving Roma, audio, or Shift;
7. feeds each WAV into BlackHole, beginning audio `1.1s` before synthetic left-Shift down;
8. runs an eight-case functional smoke, then the requested repeated four-app matrix; and
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
- macOS, Xcode, and Simulator inventory.

Namespace VNC can be active while `screencapture` remains unable to see that display from the runner shell. The workflow records this condition instead of silently claiming a desktop screenshot. The VNC controller or future Computer Use skill owns macOS desktop screenshots.

## Boundaries

- iOS means iOS Simulator on the remote Mac, not a physical iPhone.
- Microphone availability is not assumed; the deterministic STT scenario uses a generated audio file.
- Manual stages do not pre-grant Accessibility, Input Monitoring, Screen Recording, or other TCC permissions.
- The `runtime-e2e` scenario grants only the exact helper/Roma permissions needed on its disposable VM and verifies the real global-shortcut/audio-input path.
- The optional local-STT scenario performs narrow AXe UI assertions; XCUITest remains a separate fast gate.
