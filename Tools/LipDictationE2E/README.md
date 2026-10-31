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

`--app-source-head` is a caller declaration. The script checks it against the repository head and records the actual app executable hash and signature. The calling workflow must establish that its app build came from that head. The argument itself does not prove artifact provenance. Voice model selection uses `CurrentTranscriptionModel`, verified against `VoiceInkUserDefaultsKey.currentTranscriptionModel`, `VoiceInkCurrentTranscriptionModelPreference.modelName()`, and `TranscriptionModelManager.loadCurrentTranscriptionModel()`. The Boolean `isAIEnhancementEnabled` fixture disables AI enhancement through the key read by `VoiceInkAIEnhancementPreference`.

Full sequence:

```sh
python3 Tools/LipDictationE2E/run.py \
  --app "$HOME/Applications/roma just talk.app" \
  --app-source-head "$GITHUB_SHA" \
  --visual
```

`--visual` runs the supported OBS camera probe with `LIP_CAMERA_PROBE_KEEP_OBS_RUNNING=1`. A failed, static, unavailable, or unapproved device cannot pass. To reuse a successful probe from the same still-running disposable host, add `--obs-summary "$RUNNER_TEMP/lip-camera-probe/summary.json"`. That receipt must say `supportedDeviceReady` and `obsRetainedForE2E=true`.

The visual helper compiles the existing runtime helper sources with one extra entry point. It reuses the real shortcut injector, owned TextEdit targets, AX/rendered observer, application identity checks, playback, output routing, and restoration. No app-specific fake camera input, recognition result, insertion hook, or private command is introduced. A small authenticated localhost OBS client changes only the probe-owned `PublicSilentVideo` input. Its private random password stays on the host and never enters logs or artifacts.

The default full sequence installs the model through the actual settings UI before provisioning OBS. Setup needs camera permission and model storage, so its UI check runs separately from camera-device provisioning. Before each shortcut, the helper reads the complete motion file's duration and its single video track's `minFrameDuration` through local `AVURLAsset`. OBS readiness requires the complete duration within one millisecond of integer rounding. OBS then pauses the loaded file and seeks to zero within its one-second cloned-face lead. First-frame readiness requires PAUSED state, a cursor between zero and the measured frame duration, and the same observed cursor stable for at least half a second. The measured frame duration must be finite, positive, and within that lead. Checks before the shortcut and `PLAY` require the same prepared cursor. Once the app reports recording, the helper issues one `PLAY` and immediately starts matched audio with its one-second silence lead. It polls status for up to five seconds until actual PLAYING state and a cursor beyond the prepared first frame are observed, without resending playback commands. No file replacement, restart, or seek occurs during capture. Public receipts record the measured durations, stable observed cursor, input/mute settings, every status sample, and command times without authentication data.

Positive cases and cancellation at inference keep recording until normal audio completion and actual source-video ENDED state, then retain the existing 0.3-second tail before shortcut-up. The source-end wait is bounded by the measured full video duration plus five seconds. OBS may report null cursor and duration after ENDED; the earlier settings, full-duration, and effective-play checks identify the prepared input. Disable and quit intentionally stop partial captures. These are complete-input functional checks, with no playback-speed or product-latency claim.

OBS 33.0.1's [media getter uses the decoder's next PTS](https://github.com/obsproject/obs-studio/blob/65c320b46e1af5c7a555161aea6182cdf7a8c524/shared/media-playback/media-playback/media.c#L324-L333), and the [decoder computes next PTS as frame PTS plus duration](https://github.com/obsproject/obs-studio/blob/65c320b46e1af5c7a555161aea6182cdf7a8c524/shared/media-playback/media-playback/decode.c#L386-L407). A [paused seek preloads the first frame](https://github.com/obsproject/obs-studio/blob/65c320b46e1af5c7a555161aea6182cdf7a8c524/shared/media-playback/media-playback/media.c#L520-L545), while [preloading leaves it available for playback](https://github.com/obsproject/obs-studio/blob/65c320b46e1af5c7a555161aea6182cdf7a8c524/shared/media-playback/media-playback/media.c#L375-L394). This explains a 40 ms first-frame cursor for the video-only 25 fps fixture. It does not remove speech frames or justify black-frame trimming. The retained movie still needs real capture verification. The cases cover:

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
