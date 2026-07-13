# Remote E2E Stage

This workflow prepares the remote computer. It does not define or execute an interaction scenario.

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
- `hold_minutes`: 15 to 60 minutes of Remote Display availability.

The stage performs no build. It downloads the macOS artifact unchanged and does not re-sign it. The existing iOS migration workflow packages its already-built Simulator application as `roma.just.talk.ios-simulator.app`.

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

Provisioning remains owned by this workflow. Interaction prompts and judgment remain owned by the future Computer Use skill.

## Evidence

The workflow uploads `remote-e2e-stage-evidence` containing:

- remote desktop screenshots before and after the hold window;
- Simulator screenshots when iOS is selected;
- macOS and iOS application logs;
- macOS, Xcode, and Simulator inventory.

## Boundaries

- iOS means iOS Simulator on the remote Mac, not a physical iPhone.
- Microphone availability is not assumed.
- Accessibility, Input Monitoring, Screen Recording, and other TCC permissions are not pre-granted.
- Global-shortcut and audio-input proof need a separately prepared permission and hardware strategy.
- The stage intentionally performs no scripted UI assertions. XCUITest can remain a separate fast gate if wanted later.
