# Remote E2E Stage

This workflow prepares the remote computer. Manual interaction remains the default,
and an optional deterministic iOS local-Whisper scenario can run before the hold.

The intended split:

1. Existing CI workflows produce reusable application artifacts.
2. Namespace downloads those artifacts and prepares a live macOS desktop.
3. A person or future Computer Use skill controls the desktop through Remote Display.
4. The stage uploads screenshots and logs after the interaction window closes.

## Start the stage

Run the `Prepare remote E2E stage` workflow manually.

Inputs:

- `target`: `macos`, `ios`, or `both`.
- `macos_artifact_run_id`: successful `Build roma just talk` workflow run containing the exact macOS artifact to exercise. Blank selects the latest green build.
- `ios_artifact_run_id`: successful `VoiceInk iOS single-repo migration` workflow run containing the exact Simulator artifact. Blank selects the latest green run.
- `ios_scenario`: `none` or `local-whisper-import`.
- `hold_minutes`: 0 to 60 minutes after setup/scenario. Use `0` to upload evidence immediately.

The stage performs no build. It downloads the macOS artifact unchanged and does not re-sign it. The existing iOS migration workflow packages its unsigned, Simulator-entitled application as `roma.just.talk.ios-simulator.app`, preserving App Group exchange between the app and keyboard extension.

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
- macOS, Xcode, and Simulator inventory.

Namespace VNC can be active while `screencapture` remains unable to see that display from the runner shell. The workflow records this condition instead of silently claiming a desktop screenshot. The VNC controller or future Computer Use skill owns macOS desktop screenshots.

## Boundaries

- iOS means iOS Simulator on the remote Mac, not a physical iPhone.
- Microphone availability is not assumed; the deterministic STT scenario uses a generated audio file.
- Accessibility, Input Monitoring, Screen Recording, and other TCC permissions are not pre-granted.
- Global-shortcut and audio-input proof need a separately prepared permission and hardware strategy.
- The optional local-STT scenario performs narrow AXe UI assertions; XCUITest remains a separate fast gate.
