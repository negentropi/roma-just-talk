# Cleanup profile integration

Design preparation for the existing Swift Mac app. Source inspected at `ebc92f1e60fdabbb9e26b2817f414d154865a9d5`. This document explains the implementation boundaries behind the [reviewed profile proposal](cleanup-profile-design.md). No profile implementation or runtime verification is claimed.

## Why the operation needs a captured plan

The proposed contract resolves a profile once per operation. None preserves the exact recognizer-returned string. Light uses conservative deterministic cleanup. Clarity uses a fixed request and returns the untouched recognition string if that request fails. Custom preserves the existing cleanup controls and operation-specific behavior.

The current operations share Core preparation, but their surrounding behavior differs.

| Operation | Observed source behavior | Proposed snapshot point |
| --- | --- | --- |
| Recording | Snippets precede cleanup, replacements, prompt detection, and enhancement. Delivery can then recase text and append a space. Cleanup and provider preferences remain live after recognition. | [VoiceInkEngine.swift](../../../VoiceInk/Transcription/Engine/VoiceInkEngine.swift), immediately after the Power Mode activation block near line 318, before the startup-stop branches. |
| Imported file | Cleanup, replacements, and optional enhancement. No snippet expansion or prompt detection. | [AudioFileTranscriptionManager.swift](../../../VoiceInk/Services/AudioFileTranscriptionManager.swift), at `processItem` entry near line 123, before audio preprocessing awaits. Each queued item captures its own plan. |
| Retranscription | Cleanup, replacements, prompt detection, and optional enhancement. No snippet expansion. | [AudioFileTranscriptionService.swift](../../../VoiceInk/Services/AudioFileTranscriptionService.swift), at `retranscribeAudio` entry near line 34, before recognition. |

Recording has stop-during-start branches near lines 322–364. Those branches can dispatch the pipeline before the later startup task exists. Capturing the profile in that task would miss those operations.

Custom retains the import differences above. Adding profiles does not authorize imported audio to start executing prompt-trigger instructions or expanding snippets. New profiles use their documented common contract without silently changing Custom.

## Proposed data shapes

Names below are proposals, not existing symbols.

- `VoiceInkDictationProfile` is a Core enum with Custom, None, Light, and Clarity carrying its style.
- `DictationRunPlan` is an immutable Mac value captured at the operation boundary. It contains the profile and the settings that the selected profile consumes. Provider availability is captured explicitly so an unavailable Clarity provider produces raw fallback after recognition.
- A Core processing result distinguishes ordinary formatted delivery, literal delivery, and Clarity raw fallback with a failure reason. This prevents later paste preparation from changing text that the profile promises to preserve.
- `Transcription` gains optional actual recognition text, the resolved profile, and a cleanup failure reason. Existing `text` retains its processed-text meaning. Old records have no recoverable recognition text.

The existing `WritingActionProviderSnapshot` already captures provider, model, key, timeout, retry policy, and independent Local CLI or Ollama instances. Its transport can serve Clarity after a bounded rename or generalization. Cleanup must not become another `WritingActionKind`. Writing actions retain their no-insertion failure contract.

The fixed request path currently accepts `VoiceInkWritingActionRequest` in `AIEnhancementService.makeRequest`. A common immutable system/user request can serve both writing actions and Clarity. Neither path needs temporary changes to the selected prompt or global context preferences.

## Source constraints that affect correctness

### Disabled cleanup is not None

[TranscriptionCleanupPreferences.swift](../../../VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift) defines `VoiceInkTranscriptionCleanupConfiguration.disabled` near line 638. Its `filterRawOutput` still removes tag blocks and bracketed content. `prepareFilteredTextForWordReplacement` trims whitespace. None must bypass these calls before any transformation.

### Literal text needs its own delivery result

[TranscriptionPipeline.swift](../../../VoiceInk/Transcription/Engine/TranscriptionPipeline.swift) separately applies cursor recasing near line 390 and final paste formatting near line 403. The latter can append a space or prepend expired-trial text. Returning raw text from cleanup alone does not establish exact insertion.

None and Clarity raw fallback need the same explicit literal-delivery protection already used by snippet output. The ordinary nonblank paste predicate checks a trimmed copy but returns the original nonblank string. It does not itself remove the source whitespace.

### Cancellation must survive the provider boundary

[TranscriptionRecord.swift](../../../VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift) defines `VoiceInkAudioFileTranscriptionDraft.completionResult` near line 229. It catches every enhancement error, including cancellation, and creates a completed draft. Imported-file processing has no cancellation check after this provider await before insertion and save.

Clarity must propagate cancellation or check it before producing fallback and before saving. Cancellation must not become a successful raw fallback. Ordinary provider failure and cancellation require different outcomes.

### History does not currently preserve recognition output

[Transcription.swift](../../../VoiceInk/Models/Transcription.swift) stores `text` and optional `enhancedText`. Recording ordinarily assigns cleaned text to `text`. The original History variant displays that field. `enhancedText` can also contain a formatted enhancement-failure message.

Actual recognition text and cleanup failure metadata therefore need separate optional fields. Historical Original values must not be relabeled as raw. Persistence acceptance includes reopening a store created by the old model, preserving its records, and reading new fields as absent.

The transcript store is local `default.store` with CloudKit disabled in [VoiceInk.swift](../../../VoiceInk/VoiceInk.swift), near line 217. Adding an optional property still needs an actual old-store upgrade check.

### None preserves the recognizer service's returned string

Native Apple transcription already trims its final result internally in [NativeAppleTranscriptionService.swift](../../../VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift), near line 103. None preserves the service-returned string. It does not promise unnormalized decoder tokens or recover text removed inside the recognizer.

### Context eligibility belongs to the captured profile

The recording startup task currently captures clipboard and screen context for ordinary dictation. None and Light make no AI request. Clarity uses a fixed bounded request. Their implementation must not inherit Custom context capture merely because a service instance exists. Cursor information needed for target validation remains separate from AI context.

## Power Mode and preference ownership

[PowerModePolicy.swift](../../../VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift) owns the relevant types and transfers.

| Existing owner | Required extension |
| --- | --- |
| `PowerModeConfig`, near line 660 | Profile initializer, CodingKeys, decoder, and encoder. Old mode JSON without the field resolves to Custom. |
| `VoiceInkPowerModeConfigurationDraft` and `FormState`, near lines 832 and 890 | Carry the same profile through editing, add, and update conversion. |
| `VoiceInkPowerModeApplicationState`, near line 1696 | Capture profile state with the existing session snapshot. |
| `CleanupRestore` and `PreferenceApplication`, near lines 1825 and 1846 | Apply and restore the profile without changing saved Custom scalar settings. |
| `PowerModeConfig.powerModePreferenceApplication`, near line 1910 | Resolve Clarity's provider even when ordinary enhancement is off. |

The last row is a required integration decision. Current code applies a mode's provider and model only when ordinary enhancement is enabled. Clarity independent of that switch would otherwise use a different provider. The implementation can include Clarity in that predicate or resolve its provider directly from immutable mode data. Custom retains its existing behavior.

[PowerModeSessionManager.swift](../../../VoiceInk/PowerMode/PowerModeSessionManager.swift) captures actual runtime values near line 91 and supplies application callbacks near line 137.

General `.AppSettingsDidChange` replaces the active session's entire `originalState`. Posting it after a profile edit could absorb active overrides into the restoration snapshot. Current global cleanup bindings save changed defaults without that notification and refresh through `UserDefaults.didChangeNotification`. The new controls need that existing behavior or an explicit field-specific baseline update.

Missing fields have different meanings at each boundary.

| Boundary | Missing profile field |
| --- | --- |
| Global preference | Custom. |
| Old Power Mode config | Custom. |
| Old backup | Leave the current preference unchanged. |
| Old persisted active-session snapshot | Skip profile restoration. Do not overwrite the current value with an invented default. |

[UserDefaultsPreferences.swift](../../../VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift) owns flattened backup fields near line 1849, payload construction near line 1894, reconstruction near line 1984, optional import near line 2165, and shared reset near line 5255. [ImportExportService.swift](../../../VoiceInk/Services/ImportExportService.swift) already obtains cleanup backup preferences. Current Mac Settings reset resets onboarding only and must not be described as a full preference reset.

## Smallest complete ownership partition

| Owner | Exclusive files and responsibility |
| --- | --- |
| Core settings owner | New profile preference/types, `TranscriptionCleanupPreferences.swift`, `PowerModePolicy.swift`, `UserDefaultsPreferences.swift`, and their Core tests. These files overlap through storage, form transfer, snapshots, backup, and reset. |
| Processing owner | `VoiceInkEngine.swift`, `TranscriptionPipeline.swift`, both audio-file services, `AIEnhancementService.swift`, `WritingActionSession.swift`, and the new run-plan/processor. This owner coordinates provider generalization and all operation entry points. |
| Persistence owner | `Transcription.swift`, `TranscriptionRecord.swift`, migration fixtures, and persistence tests. Coordinate completion-result signatures with the processing owner before parallel edits. |
| Claude Opus 5.5 | `ModelSettingsView.swift`, `PowerModeConfigView.swift`, and History controls for raw text and failure presentation. GPT-6.1 Sol reviews the result. |

`AudioCleanupSettingsView` concerns retention. Global transcript cleanup controls belong to `ModelSettingsView`.

Model the Domain shaped the captured plan and literal-delivery result. Laziness Protocol shaped reuse of existing processing, Power Mode, and backup owners. No second settings store or independent per-operation profile implementation is proposed.

## Details still proposed

The reviewed contract does not name the first Clarity styles or state whether dictionary replacements precede its fixed request. Those choices need explicit fixtures before UI implementation. Clarity failure always returns the original recognition string, including any text that a successful path would personalize.

The snapshot promise also needs a precise boundary. Acceptance explicitly freezes profile and provider while recognition waits. Current dictionary replacement rules and Custom prompts/context remain live. The implementation must document which settings it snapshots and test those settings. It must not claim that every setting is frozen unless the run plan captures every consumed value.

## Required acceptance evidence

1. Run the same actual pipeline fixture on pinned old and candidate sources. None must preserve bracket/tag text, whitespace, quoted commands, mixed scripts, emoji, enabled snippet triggers, and replacement words. Require the intended old failure and candidate success.
2. Verify literal output at the final paste boundary with cursor recasing, trailing-space preference, and expired-trial formatting enabled. Check retained raw text separately from delivery text.
3. Verify Light against protected quotes, code, URLs, email, repeated names, Traditional Chinese, and meaningful Custom filler phrases. None and Light make zero provider requests and do not activate prompt triggers.
4. Hold recognition, change profile and provider, then release recognition. The first operation uses its captured plan. The next operation uses the new preferences. Include recording startup-stop and per-item import cases.
5. Exercise Clarity missing configuration, timeout, empty output, and cancellation through recording, import, and retranscription. Failures produce one exact raw fallback where delivery applies. Cancellation produces no delivery or completed fallback record.
6. Verify Power Mode exit, switching, and persisted recovery with ordinary enhancement off and Clarity on. Confirm the mode's provider and restoration values.
7. Verify old config JSON, old persisted session data, old backup import, new backup round-trip, shared reset, and old transcript-store reopen.
8. Exercise actual settings and History controls, persistence, keyboard navigation, and failure recovery. Retain screenshots from the tested artifact. Source review does not establish these outcomes.
