# Recording polish source handoff

2026-10-28. Source preparation only; no app build, unit execution, microphone, ASR or native paste proof in this handoff.

- Accepted recording start captures the consumed global postprocessing plan before permission or this recording's Power Mode resolution. Custom keeps its captured snippets and legacy live processing preferences.
- A separate accepted-run UUID survives startup invalidation/resource cleanup. Stop snapshots audio, effective transcription model, session, writing action, snippets, plan and mode metadata before awaiting the recorder.
- A newly accepted start supersedes the prior unfinished pipeline and cancels its owned provider/paste child tasks. Rejected no-model preflight leaves the earlier pipeline owner intact.
- Stale stop retains canceled History only for a verified regular file under the recording directory. It uses captured model/mode metadata and actual file duration; no invented recognition.
- Ordinary non-Custom processing uses the shared plan once. Recognition, profile, optional Clarity style and separate failure reason are saved through the completed draft. Literal output bypasses Custom paste transformations.
- Cancellation before delivery/during blank-result dismissal cannot become completed metadata or metrics. Existing semantics after actual delivery remain unchanged; delivery/Undo ownership is a separate unit.
- Fallback warning follows the paste result and cancellation checks. It says inserted only for `PasteResult.didDeliverText`; otherwise only retained, including save failure. `commandPosted` is part of the existing didDeliverText contract, not observation of a target's final text.

## Verification boundaries

`swiftc -frontend -parse` passed for the three source/test files; `git diff --check` passed. An independent read-only source review found the blank-result cancellation gap; it was fixed and covered by a controlled dismissal gate. No known-bad red/current-green execution has been performed. Missing API compilation on a baseline does not count as red proof.

`VoiceInkTests/DictationPolishPipelineTests.swift` contains 17 candidate tests. It uses the actual pipeline and engine with controlled Recorder/Registry overrides, in-memory SwiftData without group/CloudKit, finite gates, LocalCLI selection before AI service initialization, and existing CursorPaster seams. The failed-save case uses a deliberately read-only temporary store. Non-delivery clipboard mutation is restored only while its change-count ownership remains intact. These are unit boundary checks, not physical recorder or native delivery observations.

The final two cases hold cancellation's recorder stop and reset's resource cleanup, then accept a new recording before releasing the old completion. Both assert that the newer captured context survives. Context spies retain UUID markers rather than reading the clipboard or screen. The corresponding bounded guards recheck accepted-run ownership before cancel/reset finalization. A guard-only reverse patch reconstructs the prior Engine byte-for-byte for matched native execution; that comparison remains pending.

Run this serialized suite in a disposable fresh test app-host process, separate from native/UI seeds. Fake engine initialization overwrites PowerModeSessionManager.shared's private provider/service binding. Fixture cleanup restores captured preferences/configurations but cannot restore that private binding; live-host singleton cleanup is unproven.

The inherited global Power Mode restore-after-await and shared ASR resource-cleanup overlap races remain outside this unit. Stop snapshots and provider ownership do not claim to freeze all model/language effects or close every shared-resource lifecycle race.

## Frozen source hashes

- `TranscriptionPipeline.swift`: `e9229a9879a67c3b422e7a1d913c8b6386583837dc73484f28e5a0a173cd6bd9`
- `VoiceInkEngine.swift`: `eeb60b103e4c270935f8cac05d1734b0bfcfc6bc047601d47da908dbf8a8dd3c`
- `DictationPolishPipelineTests.swift`: `9633072b341513c0a3f92c8ad9fe1618407490f272e433d4f2075e6c544bb51b`
