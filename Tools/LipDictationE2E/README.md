# Actual app lip dictation proof

Run only on a fresh, disposable GitHub-hosted ARM64 macOS runner. The script refuses local Macs, root execution, a different desktop owner, or a mismatched declared app build head. It grants test permissions to the exact signed app and helper requirements on that disposable host. It does not change SIP, Gatekeeper, system-extension policy, credentials, or product code.

Before building the app or downloading models, compile, link, sign, and load the native visual helper:

```sh
python3 Tools/LipDictationE2E/run.py --build-helper-only
```

This command needs no app, model, OBS, or permission grants. It compiles the actual existing runtime helper sources and the visual entry point, verifies the signed bundle, and requires a positive native load acknowledgment. It writes `nativeHelperBuilt` on success. This establishes helper build/load evidence only. Normal voice and visual execution perform the same check before any app/model/OBS work.

Before model downloads or dictation fixtures, both signed helpers perform a real ScreenCaptureKit capture through the existing rendered-text capture session. A separate native visual-helper instance waits for the exact screen-consent dialog from Apple's signed `com.apple.UserNotificationCenter` at its system bundle path. It matches only the owned helper names, the complete private-window-picker title/body, and the unique enabled `Allow` button beside `Open System Settings`. It presses ordinary `Allow` at most once for each helper. Other prompts remain untouched.

The fresh-host preflight requires one observed matching prompt and exactly one successful `Allow` press for each helper, an actual nonempty PNG and capture receipt, then two seconds with that prompt absent. Capture completion or `CGPreflightScreenCaptureAccess()` cannot qualify unobserved initial consent. A helper that never prompts makes this fresh-consent fixture invalid and blocks the run. Driver readiness, matching requester, press count, prompt dismissal, executable hash, and PNG hash remain in `runtime-screen-*` and `visual-screen-*` receipts. The consent driver has a 45-second deadline. Failed or unfamiliar dialogs block the run before TextEdit preparation. This uses normal OS consent and does not add a privacy-setting bypass.

The capture requester remains alive after writing its real PNG and completed capture receipt. Its explicit `--consent-result` path tells it where to await the driver's final Allow-and-dismissal acknowledgment while servicing its runloop. The driver can read the completed image receipt without waiting for requester exit, so the handshake has no cycle. Both GUI launches explicitly receive the parent's validated GitHub-hosted environment values. The requester fails after a 50-second overall deadline; outer waits allow 55 seconds for the driver and 60 for the requester. Failure cleanup also covers exceptions and readiness failures, and targets only recorded PIDs whose current executable path matches the owned helper bundle.

The first gate uses the existing `RuntimeE2EHarness` dictation pipeline. A pinned public CREMA-D recording plays through BlackHole. Actual Left Shift press/release starts and stops Roma. TextEdit receives dictation into empty text and between existing markers. The existing helper independently reads Accessibility text and rendered pixels. A separate read-only SQLite reader verifies one completed history record per insertion. Camera starts and visual inference must be absent while the feature is off. The expected sentence enters only the observer, never the app or recognition model.

Voice first, after building the app at the current head:

```sh
python3 Tools/LipDictationE2E/run.py \
  --app "$HOME/Applications/roma just talk.app" \
  --app-source-head "$GITHUB_SHA"
```

`--app-source-head` declares the actual app build revision. Normal execution requires it to match the checkout and records the executable hash and signature. The calling workflow must establish the build's provenance; the argument alone does not prove it. Voice model selection uses `CurrentTranscriptionModel`, verified against `VoiceInkUserDefaultsKey.currentTranscriptionModel`, `VoiceInkCurrentTranscriptionModelPreference.modelName()`, and `TranscriptionModelManager.loadCurrentTranscriptionModel()`. The Boolean `isAIEnhancementEnabled` fixture disables AI enhancement through the key read by `VoiceInkAIEnhancementPreference`.

For a change confined to the named proof files, `--producer-run RUN_ID` verifies an existing Release artifact before reusing it. The verifier checks the producer repository, workflow, attempt, successful build/test steps, immutable artifact ID and archive digest, actual archived dependency lock, exact source comparison, bundle identity, and signature. Every changed path outside its explicit proof-file list rejects reuse. App archives remain outside the evidence directory. A bundle fingerprint and signature check after execution rejects changed app bytes.

Replay receipts keep the app build head and current proof head separate. The camera receipt must belong to the proof head. This tests the verified producer binary with current proof tools; it does not claim a fresh or reproducible build. The replay workflow retains both default-off voice cases and every visual, microphone, insertion, and cleanup gate.

Full sequence:

```sh
python3 Tools/LipDictationE2E/run.py \
  --app "$HOME/Applications/roma just talk.app" \
  --app-source-head "$GITHUB_SHA" \
  --visual
```

`--visual` runs the supported OBS camera probe with `LIP_CAMERA_PROBE_KEEP_OBS_RUNNING=1`. A failed, static, unavailable, or unapproved device cannot pass. To reuse a successful probe from the same still-running disposable host, add `--obs-summary "$RUNNER_TEMP/lip-camera-probe/summary.json"`. That receipt must say `supportedDeviceReady` and `obsRetainedForE2E=true`.

The visual helper compiles the existing runtime helper sources with one extra entry point. It reuses the real shortcut injector, owned TextEdit targets, AX/rendered observer, application identity checks, playback, output routing, and restoration. No app-specific fake camera input, recognition result, insertion hook, or private command is introduced. A small authenticated localhost OBS client changes only the probe-owned `PublicSilentVideo` input. Its private random password stays on the host and never enters logs or artifacts.

The default full sequence installs the model through the actual settings UI before provisioning OBS. Setup needs camera permission and model storage, so its UI check runs separately from camera-device provisioning. Before each shortcut, the helper reads the complete motion file's duration through local `AVURLAsset`. OBS readiness requires that duration within one millisecond of integer rounding, so a stale status from the previous media cannot qualify a differently sized new asset. OBS then pauses the loaded file, seeks to cursor zero within its one-second cloned-face lead, and verifies that the paused cursor stays at zero for at least half a second. After target preparation it checks the paused cursor again. Once the app reports recording, the helper only resumes that same input with `PLAY`, then starts matched audio with its one-second silence lead. No file replacement, restart, or seek occurs during capture. Public input settings, expected and observed media duration, mute state, cursor/state samples, and command receipt times are recorded without authentication data. The retained movie still needs real capture verification; no black frames are removed or replaced. The cases cover:

- Voice plus lips, requiring the voice result to be selected.
- Voice plus lips with independently verified zero PCM audio, requiring the visual result to be selected.
- Lip-only with the app's microphone TCC row deliberately denied on this disposable host. It still requires actual shortcut dictation, closed microphone diagnostics before camera capture, no microphone start, a visual result, and no audio file in history.
- Cancellation during visual inference through the existing double-Escape behavior.
- Turning the actual settings toggle off while recording.
- Quitting the actual app while recording.

Each positive case requires one camera session with no audio input, a matching camera close, an actual rendered/AX insertion, the logged selected recognizer, one completed history row, and no native writer timeout. Negative cases require a fresh, readable AX snapshot of the complete seeded target after the matching canceled session drains or the app exits. The text must equal its readable pre-shortcut baseline. Unreadable or changed text fails. No completed history row may remain. The last gate rejects remaining private movie files.

Positive camera cases wait for the matching successful recording drain before sampling AX and rendered pixels. They retain the confirmed pre-insertion baseline and still require stable changed pixels associated with the inserted text. Their timing fields describe detection after drain, an upper bound for this functional check. They do not measure product insertion latency.

Before camera setup, `negative-controls.json` verifies that distinction against an owned TextEdit document. The helper reads unchanged text, changes it through ordinary Command-A and Delete, then closes the document through the existing cleanup path. The unchanged snapshot must pass. Changed text and the unavailable closed target must fail acceptance. These controls do not start a recording or supply recognition text.

The microphone-denied fixture applies only to the positive lip-only case. It uses the app's exact signed requirement, records the authorized row before the case and the denied row before/after dictation, then restores and verifies the authorized row in `finally` before later cases. These receipts describe observed SQL fixture state. They do not claim to query the app's authorization API. The actual dictation result and hardware diagnostics provide the separate behavioral proof.

Evidence defaults to `$RUNNER_TEMP/lip-dictation-e2e`. Upload its JSON, logs, and PNG files after every outcome. `summary.json` distinguishes `nativeHelperBuilt`, `voiceDefaultOffVerified`, `lipDictationVerified`, and `blocked`. The 90/120-second observation limits bound functional tests. They are not product latency targets or measured performance claims.

The voice harness starts `focus-events.jsonl` before preflight, screen capture, or app launches. It records the initial frontmost application and `NSWorkspace.didActivateApplicationNotification` events, and closes the observer when the run returns or throws. Fixed phase checkpoints also snapshot the frontmost app after preflight, launch warmup, target preparation, shortcut release, and observation before cleanup, plus immediately before shortcut-down. Each JSON line contains the receipt time, system uptime, PID, bundle ID, application name, and bundle path. It reads no window titles or field contents and performs no focus polling. Notification receipt times depend on the helper servicing its runloop; they are not OS activation timestamps. Correlate phase snapshots and recorded PIDs with each case's prepared target and app logs when insertion refuses a changed target.

A failed voice case attempts one desktop PNG, with a five-second capture deadline. Failures observed before target cleanup capture the prepared desktop; cleanup-only failures capture afterward. Its `*-failure-evidence.json` receipt gives the capture phase and filename or failure. A target-only screenshot is explicitly unavailable because the prepared target does not expose a window ID or capture rectangle. These sidecars leave the existing report schema and insertion checks unchanged.

A successful run proves the current app path with a real supported virtual camera and public speech video. It does not establish physical-webcam behavior, general lip-reading accuracy, multilingual support, or accuracy outside the tested utterance. Fresh camera permission UI, denial/recovery, unplugging a physical camera, and broader recognition-quality checks remain separate gates.
