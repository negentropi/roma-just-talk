# Global Light and Clarity implementation plan

Integration design, 2026-10-28. Initial source read at `d6397ed975ba62d03289d681e53e3bb103eff5a0`. The current global Custom/None unit must close its full gate before app integration starts. Independent Core policy preparation can be compiled beforehand without exposing new profiles or changing ordinary dictation.

Felix selected dictation polish next. This unit adds global Light, global Clarity, three Clarity styles, and actual recognition/failure metadata across recording, import and retranscription. Approved corrections and transform undo follow separately. Their storage preparation remains in [correction learning](correction-learning-design.md) and [store upgrade verification](store-upgrade-verification-design.md).

This narrows the earlier [four-profile design](cleanup-profile-design.md) and corrects its after-Power-Mode snapshot proposal. Per-mode profile/style/provider overrides and automatic style categories remain queued.

## Decision

Freeze one immutable postprocessing plan before the operation's first await. Recording captures it at accepted start, before microphone permission and this recording's Power Mode resolution. Import captures it when each queue item starts processing, not when the batch is enqueued. Retranscription captures it when invoked. The selected profile is frozen for every ordinary operation. For Light/Clarity, later style, provider and library edits affect the next operation. Custom retains its live reads.

Clarity uses the AI configuration currently selected at that capture point. This includes any Power Mode settings intentionally persisted by an earlier recording. It does not use this recording's later Power Mode AI override. There is no independent canonical global provider in the current model. The UI must say that Clarity uses the provider/model selected when dictation starts and that Power Mode AI overrides apply to Custom.

Do not derive Clarity's provider from `activeConfiguration`, the session's `originalState`, defaults reread after activation, or a fresh `AIService`. Do not change global prompt/provider settings temporarily to execute Clarity. Existing Power Mode application and Custom behavior stay intact.

## Why an after-mode capture is insufficient

These are observed source facts, not timing measurements.

- [Engine startup](../../../VoiceInk/Transcription/Engine/VoiceInkEngine.swift) captures the current profile before permission. It sets `.recording` before awaiting configuration resolution and activation. A second toggle can therefore stop and dispatch the pipeline before a snapshot placed after those awaits. Stop also invalidates the recording startup ID.
- [Mode application](../../../VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift) applies AI/cleanup preferences, awaits transcription-model resource changes, then applies language. [Resource cleanup](../../../VoiceInk/Transcription/Engine/VoiceInkEngine.swift) invalidates that same startup ID. A new preparation owner cannot assume resource cleanup means user cancellation.
- [PowerModeSessionManager](../../../VoiceInk/PowerMode/PowerModeSessionManager.swift) saves a restore snapshot at first begin. Later general settings notifications can replace the entire snapshot with current effective settings. It can contain mode-applied provider values. The recording finish policy can deliberately retain those effective settings.
- `PowerModeConfig.powerModePreferenceApplication` currently uses `isAIEnhancementEnabled` to gate both custom prompt selection and provider/model selection. Broadening that boolean for Clarity would also select Custom prompts. A later per-mode Clarity feature must split those policies.
- [Provider selection](../../../VoiceInk/Services/AIEnhancement/AIService.swift) persists settings and reads credential state. Ollama selection also launches connection/model refresh work. [Session model application](../../../VoiceInk/PowerMode/PowerModeSessionManager.swift) can await cleanup and downloaded Whisper loading. No cost or latency bound was measured here.

Keeping `.starting` until all mode work finishes is unsuitable without a different stop contract. Its current second-toggle path records a deferred stop flag and can leave capture running while preparation waits.

| Option | Complete contract | Assessment |
| --- | --- | --- |
| Freeze the global plan before permission | Capture currently selected provider and consumed settings/libraries. This run's mode AI overrides affect Custom. No new preparation wait. | Chosen. Matches the global scope and existing Writing Action capture pattern. |
| Own activation and capture after it | Stop audio promptly, then await an operation-owned preparation task before pipeline transcription. The owner survives stop, owns cancellation, and rejects stale completion. | Viable, but shared-state edits during awaits still need rules. Also requires separating resource cleanup from operation cancellation. |
| Compile effective settings from captured base plus resolved mode | Resolve a captured mode configuration into a value. Do not reconstruct the plan from mutable globals after application. Stop audio promptly; pipeline awaits the same owned plan task. Apply model/UI effects separately. | Preferred later if per-mode Clarity provider/model becomes required. Needs separate provider and Custom-prompt eligibility, plus readiness and cancellation ownership. |

The third option is more reliable than merely adding an after-mode property. It is unnecessary for this global unit. No new startup/readiness task is proposed now.

## Operation model and boundaries

Use a domain enum, not a list of independently interpreted profile flags. Names below describe responsibilities; implementation may use the repository's naming conventions.

```swift
enum DictationRunPlan {
    case custom
    case none
    case light(LightPlan)
    case clarity(ClarityPlan)
}
```

`LightPlan` contains copied enabled snippets, copied enabled replacement rules, and the explicitly stored recognition-language choice used for its English cleanup eligibility. `ClarityPlan` contains those library values, the captured Natural/Casual/Formal style, and either a valid immutable provider snapshot or a typed configuration failure. It does not contain a selected Custom prompt, trigger-word intent, screen/clipboard/selection context, or Custom filler list. A missing provider does not prevent recording; it produces the documented raw fallback after recognition.

Capture only values that the selected branch consumes. None does not need libraries or an AI snapshot. Custom remains a legacy path and continues its existing live cleanup/prompt/context behavior. Explicit Writing Actions remain independent of ordinary dictation profiles.

Expose a read-only value snapshot of enabled replacement rules through [DictionaryService](../../../VoiceInk/Services/DictionaryService.swift). Reuse [the replacement engine](../../../VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift), including its named legacy comma-alternative contract. Do not carry SwiftData model objects into the plan or consult its mutable cache during execution. Store either copied rules or a typed preparation failure in the plan. A fetch failure is not an empty library. A literal snippet match still takes precedence; otherwise failed rules preparation produces exact recognition text and a warning for Light/Clarity. Keep Custom's current cache behavior unchanged.

The global profile and style are not Power Mode state. Do not add them to mode application/restoration or post `AppSettingsDidChange` solely for a global profile/style change. Use the existing profile preference pattern. Add an optional style to settings backup, preserve the current value when an older backup omits it, and reset it to Natural. Unknown profile values still select Custom; unknown styles select Natural. No new dependencies.

The plan owns postprocessing choices only. It does not promise to freeze every ASR provider setting or change existing transcription-model startup. Light uses an explicitly stored English choice as a conservative permission to apply its grammar, not as a claim about detected speech. Power Mode can still change the ASR language; ambiguous text must remain unchanged.

## Exact processing contract

Retain the recognizer service's returned `String` before any transformation. Call it recognition text. It is not decoder tokens and does not prove what the speaker said.

| Profile | Processing and delivery |
| --- | --- |
| Custom | Existing branch, including its entry-point differences, prompt detection, context, failure and paste behavior. Capture recognition metadata without changing processing. |
| None | Existing exact recognizer-text contract. No snippets, dictionary, cleanup, AI, cursor recasing, trial prefix or added space. |
| Light | Full-utterance snippet match first. Otherwise apply the small hesitation grammar, then captured replacements. No prompt detection or AI request/context. Deliver that result literally. Failed library preparation uses exact recognition text with a warning. |
| Clarity | Full-utterance snippet match first. Otherwise apply captured replacements to a copy and send one bounded cleanup request using the frozen style/provider. Deliver a valid result literally. Failure delivers exact recognition text once and warns. |

Literal delivery for the new profiles prevents cursor recasing, trailing-space preferences or trial prefixes from making a second undocumented transformation. Reuse the existing literal-output route. Existing permission, cancellation and paste authorization checks still apply.

Snippet content takes literal precedence, including multiline content, tags, JSON and apparent instructions. It never reaches Light cleanup, replacement rules or Clarity. Apply this contract to all three new-profile entry points. Custom keeps today's differences: recording expands snippets and detects prompts, import does neither, retranscription detects prompts but does not expand snippets. See [pipeline](../../../VoiceInk/Transcription/Engine/TranscriptionPipeline.swift), [import](../../../VoiceInk/Services/AudioFileTranscriptionManager.swift), and [retranscription](../../../VoiceInk/Services/AudioFileTranscriptionService.swift).

Clarity failure must return the untouched recognition text, not dictionary output, Light output or a partly parsed provider result. This applies to missing configuration, request failure, timeout, malformed/empty output and snapshot preparation failure. Store the reason separately and show that the original was inserted. Import and retranscription retain a completed recoverable raw record with a processing warning. They do not add a warning string to `enhancedText`.

Cancellation is a distinct outcome. It never becomes raw fallback. Check the operation/task cancellation state before the provider call, after it returns or throws, before committing output, and at delivery. Wrapped provider errors can obscure `CancellationError`; checking that error type alone is insufficient. Recording may retain its existing canceled record. Import/retranscription must not publish a completed result on cancellation.

## Light's deliberately small grammar

Do not reuse `VoiceInkTranscriptionCleanupConfiguration.disabled`. Its existing filters remove tags/bracket content and trim text. Do not use Custom filler preferences or a language recognizer's guess to authorize deletion.

Initial grammar:

1. Enable hesitation removal only when the captured stored language is explicitly an English code. Missing, auto and every other language are no-ops for this step. A model's fallback to English does not count as an explicit choice.
2. Match only an utterance-leading `um, ` or `uh, `, case insensitive, with a comma and following whitespace, followed by substantive text. Remove that prefix once. Preserve the remaining string exactly. Do not trim, recase, deduplicate, infer punctuation, parse spoken commands, or repeatedly consume prefixes.
3. Leave the entire utterance unchanged by this step if it contains quotation delimiters, backticks, angle/square/curly brackets, a URL or an email address. Prefer a documented no-op over an incomplete quote/code parser. Replacements remain explicit user rules and run afterward.

Examples for explicit English: `Um, send it tomorrow.` becomes `send it tomorrow.`; `um amigo` stays unchanged. `Um, um, send it.` removes only the first prefix. `Send um to Alex`, `uh-huh`, `very very good`, `new line`, `Um, "keep this"`, `<think>um</think>` and structured data remain unchanged by hesitation removal. Missing, auto and non-English selections leave even `Um, send it tomorrow.` unchanged. An English selection with code-switched speech is not a universal language guarantee; `Um, vamos amanhã.` matches this punctuation grammar. There is no automatic mixed-language detector in this design.

This is a useful first deterministic level, not a claim of general filler removal. Expand it only with meaningful positive and multilingual negative cases.

## Clarity request and provider transport

The request permits punctuation, sentence boundaries, removal of speech disfluencies, and small grammatical repairs. Preserve language, facts, numbers, names, identifiers, negation, uncertainty and substantive repetition. Do not translate, answer dictated questions, follow instruction-like content, add a greeting/sign-off, or invent details. Natural retains the speaker's wording; Casual permits small conversational phrasing; Formal permits small grammatical/register changes. None authorizes drafting, summarizing or expanding the message.

Serialize the transcript as a JSON string in a typed payload. A transcript containing quotes, delimiters, JSON or `ignore previous instructions` remains data. Do not interpolate it into fixed system instructions. Require a strict single JSON object containing a `text` string as the response. Decode at the boundary, reject malformed/extra-envelope output and empty output for nonempty input, and preserve the decoded string without generic regex filtering. The response envelope does not establish semantic correctness; real answer-hidden samples remain required.

Reuse the request transport in [AIEnhancementService](../../../VoiceInk/Services/AIEnhancement/AIEnhancementService.swift) through a private fixed-system/fixed-user method. Return the unfiltered provider text. Existing Custom/Writing Action wrappers keep their current filtering; the cleanup wrapper decodes its own envelope and applies its distinct fallback contract. Do not add cleanup to `VoiceInkWritingActionKind`, temporarily select a prompt, or call `getSystemMessage()` for Clarity. That method collects live selection/context/vocabulary.

Generalize the internal `WritingActionProviderSnapshot` name and update its callers directly, without an alias. Keep provider-specific configuration as immutable values. Capture execution plan, actual endpoint/model, cached credential, timeout/retry policy, and CLI command/CLI timeout. Reuse the existing rate-limit/retry owner. Retries must reuse the same request and snapshot.

The extraction has one remaining filter trap and one separately completed identity prerequisite:

- Existing provider results pass through [AIEnhancementOutputFilter](../../../VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift), which deletes `<think>`/`<thinking>`/`<reasoning>` blocks and trailing `codex_follow_up` JSON. Clarity must bypass that destructive content filter.
- The old Ollama snapshot at `830d4521` could report a different model from its runtime request. The existing [OllamaService](../../../VoiceInk/Services/OllamaService.swift) now captures one immutable runtime endpoint/model for request and metadata, without selection writes or refresh. [Matched actual SDK proof](evidence/ollama-identity-40545355522/native-audit.json) passed at `1f36a746`; reuse that owner instead of repeating the fix.

The current snapshot factory reads cached credential state and preferences; it does not itself create a new `AIService` or issue a connection request. A fresh `AIService` loads credential state and is not an equivalent snapshot. Keep credentials in memory and out of records, logs and evidence.

[LocalCLIService](../../../VoiceInk/Services/AIEnhancement/LocalCLIService.swift) currently terminates on timeout but lacks a task cancellation handler. The shared extraction must preserve cancellation as cancellation and make an owned CLI process terminate on cancellation. Test that exact child process, not a process-name kill. Its termination does not prove descendants or remote work stopped. RJT must always suppress canceled delivery even if a backend ignores cancellation. Cloud SDK cancellation behavior needs source/runtime verification before claiming the remote work stopped.

## Recognition and failure storage

Add optional `Transcription` fields for recognition text, captured profile, captured Clarity style, and processing failure reason. Carry them through the completed draft/apply path and every ordinary-dictation adapter. Use optional stored scalar values with deliberate unknown-value handling; do not make old rows decode as None or invent recovered recognition text.

Keep the meaning of existing `text` and `enhancedText`. For new Light records, `text` is the deterministic processed result. For successful Clarity, `text` is the dictionary-prepared input and `enhancedText` is the decoded result. For Clarity fallback, `text` is exact recognition text and `enhancedText` is nil. Raw recognition is always separately available on newly completed ordinary records, including Custom/None. Existing AI request/model/duration fields describe the request actually executed. Store no request success metadata when no request ran.

History's existing Original remains processed text. Show a distinct recognition variant only when its new field exists. Old rows retain nil metadata and their existing labels/values. Cancellation must not leave a successful style/result claim behind.

Use the reviewed [old-product seed, closed-store clone, candidate open, explicit save, process exit and reopen procedure](store-upgrade-verification-design.md). The predecessor must use the actual product model/module/store grouping. Reject in-memory fallback and synthetic renamed legacy classes. Do not introduce versioned-schema aliases before a real old-store failure establishes their need. The local store check does not prove CloudKit account synchronization.

## Implementation ownership and acceptance

After Custom/None closes, implement these coherent units in order. Separate owners may work in parallel only after the shared value contracts are fixed.

| Owner | Files/responsibility | Evidence required before completion |
| --- | --- | --- |
| Core processing | `DictationProfile.swift`, new Light/Clarity request/result policy, relevant Core tests. Excludes `TranscriptionRecord.swift`. | Exact UTF-8/UTF-16 preservation, documented grammar, snippet precedence, JSON encoding/decoding, styles and explicit fallback/cancel outcomes. |
| Provider transport | AI enhancement service/snapshot, Ollama and Local CLI executors, focused provider tests. | Frozen endpoint/model/key identity across edits/retries; literal tags/JSON preserved; strict response failures; owned CLI cancellation. Existing Custom/Writing Actions unchanged apart from a separately demonstrated model-identity bug fix. |
| Storage | `Transcription.swift`, `TranscriptionRecord.swift`, old-product fixtures/reopen tests. | Real old-store open/save/restart, exact old values, nil historical fields, new raw/profile/style/error round trip. No fallback container. |
| Integration | Engine/pipeline, import/retranscription, dictionary value snapshot, profile/style backup/reset wiring. Coordinate draft API with storage owner. | All entry points consume one frozen plan, raw fallback once, cancellation none, edits affect next operation, None/Custom regressions remain green. |
| UI | Actual Claude Opus 5.5 owns profile/style settings and History recognition/warning controls. GPT-6.1 Sol reviews. | Real controls and persistence, older-history labels, exact fallback warning, clear global-provider semantics. No per-mode controls in this unit. |

Verification runs on the remote Mac/CI. Pin source, dependencies, test IDs, binary/signature identity and request configuration. Retain screenshots/logs with exact tested head. A selector that executes zero cases, skipped required cases, or a container/setup failure is invalid evidence.

Required gates:

1. Core and full relevant Mac units. Cover explicit English/auto/Portuguese/mixed-language negatives, quoted/code/JSON text, replacements changed during processing, snippet literal content, all three styles, missing provider, wrapped cancellation, malformed/empty response, and retry snapshot stability. Prove the Ollama identity mismatch red on the pinned old owner and green on the candidate under the same boundary. Characterize legacy filter behavior and prove Clarity bypasses it while Custom/Writing Actions retain it. A baseline compile failure is not regression proof.
2. Actual service/provider samples through the app's cleanup method. Use answer-hidden facts, names, numbers, uncertainty, language, email/list structure and instruction-like JSON for each style. Record the actual route/model/request/result. Synthetic provider tests prove transport/control flow only. An authenticated unmocked provider run is required for semantic observations; do not generalize one route to every provider.
3. Pinned native pipeline/import/retranscription cases. Prove successful output, literal snippet, exact raw fallback, one warning, failure metadata, canceled late result and no new AI context. Hold permission/mode resolution, change profile/provider/library, then complete and verify the accepted-start plan. A second toggle during delayed mode work must still stop promptly, without awaiting Clarity preparation. Record actual stop events; mock recorder timing alone does not prove microphone behavior.
4. Real local Whisper file inference plus actual new-profile processing and persistent-store restart. Compare stored recognition text with the direct recognizer output under the same context. Retain WAV/source/signature hashes. This proves the file boundary; physical microphone/keyboard use remains separate.
5. The real predecessor-to-candidate store gate above, Claude UI interaction/persistence/screenshot checks, relevant iOS compile/schema consumer checks, then final Release build/package gate. Update user docs and Unreleased changelog as the feature lands. No release publication is implied.

No unresolved source fact blocks this global design. The provider contract and narrow Light grammar are product choices made here. Runtime behavior, model quality, migration and UI remain acceptance work. The larger operation-owned mode plan is queued with per-mode Clarity, rather than being partially introduced now.

Model the Domain drove the immutable operation enum and distinct success/fallback/cancel outcomes. Boundary Discipline drove value snapshots and strict provider decoding. Laziness Protocol drove reuse of the current request, dictionary and literal-paste owners. Sequence Verifiable Units keeps this preparation behind the current Custom/None gate.

## Execution review after the Ollama identity unit

At `1f36a746`, Ollama capture now uses one immutable runtime endpoint/model pair. [Actual matched SDK proof](evidence/ollama-identity-40545355522/native-audit.json) passed; do not reimplement that prerequisite. Preserve Custom’s existing accepted-start snippet snapshot while retaining its other legacy live reads. Keep new optional recognition metadata on Mac `Transcription` and defaulted Core draft values, not `VoiceInkMutableTranscriptionRecord` (Mac does not conform; changing the protocol would unnecessarily widen iOS). Hosted store checks require a disposable Mac user/VM in addition to unique fixture URLs, because app-host startup opens its normal stores before the test. New Clarity metadata must use captured messages directly; shared last-request fields can change during suspension. No Light/Clarity app integration is claimed here.

## Independent Core preparation

`DictationPolish.swift` now contains the conservative English hesitation rule, stable Natural/Casual/Formal values, fixed JSON request messages and response decoding. Eight registered check methods cover positive cleanup, multilingual and protected-content no-ops, exact code units, instruction-like transcript data and malformed/blank responses. This preparation has not yet passed a compiler/runtime gate. It adds no selectable profile, provider call, app preference or storage field.

The Light rule preserves initial spaces/tabs and requires spaces/tabs after the comma. It leaves paragraph boundaries, non-ASCII separators and punctuation-only remainders unchanged. Its whole-utterance protection also covers bare Unicode domains and numeric dotted addresses; this intentionally favors preserving text.

Foundation owns JSON lexical syntax and duplicate-member handling. The decoder validates the resulting semantic object: exactly the decoded key `text`, a string value, and nonblank output for nonblank input. It preserves that string verbatim. This is not a custom strict JSON lexer, a duplicate-key rejection guarantee, or evidence that a model obeys the cleanup instructions.

The dedicated Core workflow runs the complete check executable with the existing Core lock forced, without app, Whisper, UI or provider setup. It records source/toolchain/pins and verifies source and lock bytes afterward. This keeps policy compilation independent of the pending native app gates.
