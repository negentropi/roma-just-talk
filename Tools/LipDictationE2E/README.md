# Actual app lip dictation proof

Run only on a fresh, disposable GitHub-hosted ARM64 macOS runner. The script refuses local Macs, root execution, a different desktop owner, or a mismatched declared app build head. It grants test permissions to the exact signed app and helper requirements on that disposable host. It does not change SIP, Gatekeeper, system-extension policy, credentials, or product code.

Before building the app or downloading models, compile, link, sign, and load the native visual helper:

```sh
python3 Tools/LipDictationE2E/run.py --build-helper-only
```

This command needs no app, model, OBS, or permission grants. It compiles the actual existing runtime helper sources and the visual entry point, verifies the signed bundle, and requires a positive native load acknowledgment. It writes `nativeHelperBuilt` on success. This establishes helper build/load evidence only. Normal `--visual` execution performs the same check before any app/model/OBS work.

The first gate uses the existing `RuntimeE2EHarness` unchanged. A pinned public CREMA-D recording plays through BlackHole. Actual Left Shift press/release starts and stops Roma. TextEdit receives dictation into empty text and between existing markers. The existing helper independently reads Accessibility text and rendered pixels. A separate read-only SQLite reader verifies one completed history record per insertion. Camera starts and visual inference must be absent while the feature is off. The expected sentence enters only the observer, never the app or recognition model.

Voice first, after building the app at the current head:

```sh
python3 Tools/LipDictationE2E/run.py \
  --app "$HOME/Applications/roma just talk.app" \
  --app-source-head "$GITHUB_SHA"
```

`--app-source-head` is a caller declaration. The script checks it against the repository head and records the actual app executable hash and signature. The calling workflow must establish that its app build came from that head. The argument itself does not prove artifact provenance. Voice model selection uses `CurrentTranscriptionModel`, verified against `VoiceInkUserDefaultsKey.currentTranscriptionModel`, `VoiceInkCurrentTranscriptionModelPreference.modelName()`, and `TranscriptionModelManager.loadCurrentTranscriptionModel()`.

Full sequence:

```sh
python3 Tools/LipDictationE2E/run.py \
  --app "$HOME/Applications/roma just talk.app" \
  --app-source-head "$GITHUB_SHA" \
  --visual
```

`--visual` runs the supported OBS camera probe with `LIP_CAMERA_PROBE_KEEP_OBS_RUNNING=1`. A failed, static, unavailable, or unapproved device cannot pass. To reuse a successful probe from the same still-running disposable host, add `--obs-summary "$RUNNER_TEMP/lip-camera-probe/summary.json"`. That receipt must say `supportedDeviceReady` and `obsRetainedForE2E=true`.

The visual helper compiles the existing runtime helper sources with one extra entry point. It reuses the real shortcut injector, owned TextEdit targets, AX/rendered observer, application identity checks, playback, output routing, and restoration. No app-specific fake camera input, recognition result, insertion hook, or private command is introduced. A small authenticated localhost OBS client changes only the probe-owned `PublicSilentVideo` input. Its private random password stays on the host and never enters logs or artifacts.

The actual settings UI installs the model. The camera receives a static face while capture starts. Once the app reports recording, OBS plays the complete public motion clip with a one-second still lead. Matched audio contains the same one-second silence lead. The cases cover:

- Voice plus lips, requiring the voice result to be selected.
- Voice plus lips with independently verified zero PCM audio, requiring the visual result to be selected.
- Lip-only with the app's microphone TCC row deliberately denied on this disposable host. It still requires actual shortcut dictation, closed microphone diagnostics before camera capture, no microphone start, a visual result, and no audio file in history.
- Cancellation during visual inference through the existing double-Escape behavior.
- Turning the actual settings toggle off while recording.
- Quitting the actual app while recording.

Each positive case requires one camera session with no audio input, a matching camera close, an actual rendered/AX insertion, the logged selected recognizer, one completed history row, and no native writer timeout. Negative cases require no inserted text and no completed history row. The last gate rejects remaining private movie files.

The microphone-denied fixture applies only to the positive lip-only case. It uses the app's exact signed requirement, records the authorized row before the case and the denied row before/after dictation, then restores and verifies the authorized row in `finally` before later cases. These receipts describe observed SQL fixture state. They do not claim to query the app's authorization API. The actual dictation result and hardware diagnostics provide the separate behavioral proof.

Evidence defaults to `$RUNNER_TEMP/lip-dictation-e2e`. Upload its JSON, logs, and PNG files after every outcome. `summary.json` distinguishes `nativeHelperBuilt`, `voiceDefaultOffVerified`, `lipDictationVerified`, and `blocked`. The 90/120-second observation limits bound functional tests. They are not product latency targets or measured performance claims.

A successful run proves the current app path with a real supported virtual camera and public speech video. It does not establish physical-webcam behavior, general lip-reading accuracy, multilingual support, or accuracy outside the tested utterance. Fresh camera permission UI, denial/recovery, unplugging a physical camera, and broader recognition-quality checks remain separate gates.
