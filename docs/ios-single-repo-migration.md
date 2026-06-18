# iOS Single-Repo Migration

`VoiceInk/` is the source repo. The sibling `../VoiceInk-iOS` checkout is evidence only.

## Current Shape

- macOS app: `VoiceInk.xcodeproj`
- iOS app and keyboard targets: `iOS/VoiceInk-ios.xcodeproj`
- iOS app/keyboard shared shell code: `iOS/Shared/`
- iOS unit/UI test target sources: `iOS/VoiceInk-iosTests/`, `iOS/VoiceInk-iosUITests/`
- iOS non-Swift app artifacts: `iOS/VoiceInk-ios/PrivacyInfo.xcprivacy`, `iOS/VoiceInk-ios/Assets.xcassets/`, and `iOS/VoiceInk-ios/Resources/ggml-silero-v5.1.2.bin`
- shared Swift package: `VoiceInkCore/`
- workspace entry for both app projects: `VoiceInk.xcworkspace`

Both app projects reference the in-repo package:

- macOS package path: `VoiceInkCore`
- iOS package path: `../VoiceInkCore` from `iOS/`

No shared code should be added at the parent `faster-wisperflow/` workspace level.

## Shared Core

`VoiceInkCore` currently owns these cross-platform modules:

- prompt templates and prompt text
- predefined prompt IDs, labels, prompt text, icons, descriptions, and system-instruction flags
- custom prompt system-instruction wrapping
- transcription prompt preference loading/saving, selected-language local Whisper prompt fallback, and nonblank request prompts for remote/realtime providers
- post-processing request construction and output filtering
- post-processing/enhancement failure presentation text and enhancement notification title truncation
- AI-enhancement error vocabulary, user-facing descriptions, HTTP status classification, Foundation transport-network classification, and retry/backoff decision policy; platform shells still own provider transport, provider-specific error mapping, sleep timing, and logging
- provider catalog, provider endpoints, API key account names, provider readiness/selectability policy, and transcription empty-output policy
- provider API-key fallback environment-variable names
- provider credential nonblank validation for runtime API-key checks
- provider API-key draft verification candidate and save-after-verify policy for iOS provider-key entry
- provider API-key verification dispatch, including stored-key reference/fallback resolution before verification
- provider API-key verification flag storage
- provider API-key state policy for stored-key lookup, runtime-key resolution, verification reset on key changes, and readiness calculation; platform shells still own Keychain storage and UI editing state
- API-key display obfuscation policy; platform shells still own where stored keys are read and rendered
- API-key environment-reference resolution and typed provider runtime-key lookup/fallback policy
- AI reasoning temperature, effort, and provider-specific hidden-reasoning request parameters for OpenAI-compatible post-processing
- AI-enhancement provider identity, persisted-name parsing, API-key requirement, text-enhancement selectability, connected-provider selection policy, storage keys, model-selection key naming, and mapping to shared model providers; platform shells still own storage and execution
- AI-enhancement API-key verification route metadata; native provider checks use shared verifier clients while macOS keeps model-specific Anthropic/OpenRouter/OpenAI-compatible verification
- AI-enhancement model defaults, static model lists, and selected-model fallback policy for macOS AI providers; platform shells still own dynamic providers such as Ollama, OpenRouter fetching, Local CLI, and Custom
- AI-enhancement provider request endpoints and optional API-key console URLs for macOS AI providers; platform shells still own provider UI and request execution
- dynamic AI-provider preference storage for Ollama base URL/model, Custom provider base URL/model, and cached OpenRouter models; platform shells still own provider execution, network refresh, and UI state
- transcription and AI model catalogs
- transcription provider recorded-file capability, including Cartesia as streaming-only
- Native Apple and FluidAudio local transcription model metadata; platform shells still own availability, download, and runtime adapters
- remote transcription provider dispatch for iOS retry transcription
- mode runtime configuration, default local mode selection, provider-change and stale model repair, selected-mode repair, mode-based transcription language availability, and selected-language repair
- mode provider-selection repair and draft saveability rules
- shared UserDefaults key names, including cleanup preferences, plus iOS mode persistence helpers with stale model repair on load
- shared preference default state and UserDefaults registration values for core-owned keys; platform shells still choose platform-specific defaults such as selected language/current model and register OS-specific keys
- onboarding completion, iOS audio-session timeout, and core-owned user preference reset storage; platform shells still own first-run flow, audio-session lifecycle, keychain clearing, file deletion, and settings UI bindings
- current transcription model preference loading/saving/clearing; platform shells still own model availability, download/runtime state, and legacy key cleanup
- transcript status, default transcript fallback copy, canceled-transcript paste eligibility, presentation helpers, and localized standard transcript search semantics
- error-description presentation fallback for shared record and shell failure text
- local transcription/model/missing-audio error vocabulary shared by macOS local Whisper and iOS local retry transcription
- streaming word-agreement confirmation policy for stable partial transcription, including confidence gates, sentence-boundary confirmation, reset behavior, and rolling-preload configuration; platform shells still own provider token adapters, ASR runtime calls, audio buffering, and event delivery
- streaming final-commit timeout policy for cloud providers versus local FluidAudio finalization; platform shells still map runtime provider identity to the shared timeout source
- streaming transcription event vocabulary for session, partial, committed, and error events; platform shells still adapt provider-specific event streams
- streaming transcription error vocabulary and user-facing descriptions; macOS still maps `LLMkit` transport errors into the shared streaming taxonomy
- per-model transcription streaming preference key/default/read/write policy and streaming eligibility for unsupported, streaming-only, and batch-capable streaming models; platform shells still own provider runtime adapters and settings UI
- streaming preference/model-name migration for legacy per-model streaming keys, removed realtime model selections, and stored Power Mode transcription model JSON; platform shells still own when startup migrations run
- rolling-buffer preload settings, per-model preload key/default policy, configuration normalization, power-state model, rolling audio lead-in retention, and preload allow/deny policy for global mode, per-model opt-out, cloud auto-disable, and low-battery local-model guards; macOS still owns IOKit power probing, rolling audio source delivery, VAD, runtime diagnostics, and model/provider adapters
- special-shortcut empty-tap fallback policy for press-duration threshold, pending fallback lifetime, completed-state checks, and empty raw/enhanced transcript eligibility; macOS still owns pending fallback state and cursor paste
- special-shortcut key-evidence policy for typed-through and unreliable-key fail-closed decisions; macOS still owns AppKit/CGEvent monitoring and evidence collection
- recording-state vocabulary, rolling-preload preview eligibility, shortcut-action eligibility, recorder UI toggle mapping, and recorder-session shortcut activity policy; platform shells still own recorder windows, timers, audio capture, and OS-specific session state
- raw transcription output filtering for hallucination tags/brackets, optional filler words, default filler-word vocabulary, and filler-word list editing policy; iOS settings now use the same list editing policy in their platform shell
- transcription cleanup preference loading/saving/reset storage, editable cleanup settings snapshots, raw-output filtering, filtered-text preparation, and paragraph-formatting/punctuation/lowercase/filler-word cleanup policy
- filler-word list storage defaults and saving
- cursor-aware transcript capitalization policy; platform shells only supply cursor text and paste targets
- NaturalLanguage word-count policy for metrics and short-enhancement skip decisions
- session-metric calculation policy for enhanced-text word counting, non-positive duration cleanup, and transcription speed factor; platform shells still own SwiftData metric insertion and migration scheduling
- dashboard metrics summary and derived productivity math for time saved, words per minute, and keystrokes saved; platform shells still own metric queries, caching, and rendering
- performance-analysis aggregation for transcription/enhancement model averages, speed factor, speed-factor display text, and average-processing-time display text; platform shells still own queries, filters, system information, and rendering
- short post-processing skip policy, stored skip configuration, and storage defaults for brief transcripts; platform shells still own UI controls and whether to apply the policy
- AI-enhancement timeout/retry storage keys, defaults, and runtime preference reads; platform shells still own request execution, provider transport, logging, and UI controls
- AI-enhancement selected-provider and per-provider selected-model preference storage, including legacy selected-provider repair; platform shells still own provider execution and dynamic model discovery
- transcription auto-cleanup enabled/retention preference storage and cutoff-date policy; platform shells still own SwiftData deletion and settings UI bindings
- audio-file auto-cleanup enabled/retention preference storage and cutoff-date policy; platform shells still own SwiftData queries, file deletion, timers, and settings UI bindings
- NaturalLanguage transcript paragraph formatting policy plus text-formatting storage key/default; platform shells still own the setting UI and when formatting runs
- word-replacement ordering, text application policy, and iOS UserDefaults persistence; macOS still owns SwiftData dictionary storage
- vocabulary, word-replacement, backup dictionary insert, word-replacement edit planning, and dictionary draft submit rules; platform shells still own macOS SwiftData dictionary storage and persistence errors
- custom vocabulary term normalization for transcription providers and iOS UserDefaults persistence; macOS still owns SwiftData vocabulary storage
- custom cloud transcription model draft normalization, generated-name, required-field, and validation policy; platform shells still own keychain and preferences storage
- prompt trigger-word detection, trigger-word draft validation/editing policy, and prompt-trigger AI-enhancement detection result construction; platform shells still own prompt persistence and enhancement state mutation
- AI-enhancement prompt context assembly for selected text, clipboard, current-window text, custom vocabulary prompt text, and custom vocabulary tags; platform shells still own OS access, capture, and vocabulary storage
- AI-enhancement custom prompt record shape, Codable compatibility, and final-prompt wrapping; macOS still owns SwiftUI prompt rendering and prompt-store orchestration
- predefined-prompt repair/merge policy and trigger-detectable prompt filtering; macOS still owns when the prompt store is loaded and saved
- AI-enhancement custom prompt array mutation, selected-prompt repair, and selected-prompt persistence helpers; platform shells still own notifications and UI state updates
- selected-prompt repair, enable-time prompt fallback, and base prompt-text selection for AI enhancement; platform shells still own context capture and request execution
- AI-enhancement prompt-store and context-toggle storage keys; macOS still owns persistence timing, notifications, and UI orchestration
- transcription language catalog, provider language filtering, AssemblyAI realtime/batch language policy, selected-language fallback policy, language-option ordering, selected-language preference loading/saving/clearing, compatible selected-language persistence, selected-language request normalization, and the shared selected-language defaults key; platform shells still own selected-language UI and runtime streaming-mode state
- transcription language-source policy for Whisper, Native Apple, FluidAudio, shared provider catalogs, AssemblyAI realtime/batch language selection, and all-language fallback; platform shells still adapt their model/provider enums and live streaming preferences
- local Whisper language seed prompts and custom language-prompt storage; platform shells still own prompt editing UI and when prompts are persisted
- stored audio-file path resolution, existing-file lookup, availability/missing-audio presentation, recordings directory, file URL construction, recording/import/retranscription filename policy, and record-level resolved/existing/delete helpers
- supported media extension and UTType import policy for audio/video files
- transcription CSV header, row formatting, and CSV escaping; platform shells still own save panels and record-source mapping
- power-mode display formatting for transcript metadata and exports
- power-mode app/website/default matching, website URL normalization, and save validation; macOS still owns OS app/website detection, SwiftUI editing/alerts, active-session application, shortcuts, and config persistence
- duration presentation
- relative timestamp presentation
- Whisper and VAD model file metadata, including platform-base Whisper model directory creation, downloaded local-model file records, runtime model-name to downloaded-file resolution, model/sidecar file construction, downloaded-state detection, bootstrap-model availability, Core ML support policy, final `.bin` install/replacement, and model/sidecar deletion
- local Whisper runtime defaults and runtime configuration for request-language normalization, prompt, thread count, transcription temperature, VAD enablement, VAD model path eligibility, and VAD thresholds
- VAD bundle resource lookup
- PCM16 sample conversion, mono 16 kHz transcription-audio format constants, WAV file sample loading, normalized mono sample mixing for Whisper input, float-to-PCM16 output sample conversion, interleaved Float32 live-capture conversion to mono PCM16 with optional linear resampling, and sample-aligned PCM16 data chunking, including bit depth, endian, and integer/float sample policy
- audio-meter decibel normalization and smoothing math; platform shells still own capture, timers, and visualizer rendering
- audio playback timeline progress, waveform sample progress, and clamped seek-time math; platform shells still own `AVAudioPlayer`, gestures, hover state, and playback UI
- OpenAI-compatible, Deepgram, Gemini, Mistral, ElevenLabs, xAI, Soniox, Speechmatics, and AssemblyAI remote transcription request/client helpers
- shared remote transcription provider dispatch plus batch request option defaults for provider-specific prompt, vocabulary, timeout, retry, and formatting parameters
- Cartesia API-key verification request/client helper
- shared multipart form-data construction for remote transcription clients
- shared retried upload helper for multipart remote transcription clients

Current macOS consumers of shared remote transport:

- macOS batch cloud transcription uses `CloudProvider` default dispatch into `VoiceInkRemoteTranscriptionService` for Groq, Deepgram, Gemini, Mistral, ElevenLabs, xAI, Soniox, Speechmatics, and AssemblyAI; `CloudProviderRegistry` now maps shared provider identity to macOS streaming factories, and empty-response policy comes from `VoiceInkProviderKind`.
- `VoiceInkRemoteTranscriptionService` and `VoiceInkRemoteTranscriptionOptions.batchDefaults` preserve macOS provider-specific batch options such as Groq JSON/temperature/retry settings, Deepgram paragraph/timeout settings, and vocabulary/prompt forwarding for providers that already used them.
- Custom OpenAI-compatible batch transcription uses `VoiceInkOpenAICompatibleTranscriptionClient`.
- Cartesia API-key verification uses `VoiceInkProviderAPIKeyVerifier` through `VoiceInkTranscriptionModelProvider`; Cartesia transcription remains streaming-only in platform shell code.
- MacOS cloud-provider API-key verification uses `CloudProvider` default verification backed by `VoiceInkProviderAPIKeyVerifier`; provider-specific streaming adapters still own transcription execution.
- macOS local Whisper/model loading throws `VoiceInkEngineError` from `VoiceInkCore`; macOS error descriptions are covered by `VoiceInkEngineErrorTests`.
- macOS local Whisper and cloud transcription normalize selected request language through `VoiceInkTranscriptionLanguagePreference`.
- macOS local Whisper, cloud transcription, AssemblyAI streaming, and `WhisperPrompt` read/write transcription prompts through `VoiceInkTranscriptionPromptPreference`; local Whisper transcription uses the shared selected-language prompt fallback helper.
- macOS local Whisper reads `VoiceInkWhisperRuntimeConfiguration` to assemble language, prompt, thread count, temperature, and VAD settings before adapting them into whisper.cpp; FluidAudio VAD gating still reads `VoiceInkVADPreference`, preserving the existing `IsVADEnabled` storage key while sharing the default and lookup policy with iOS.
- macOS `WhisperPrompt` loads/saves custom local-Whisper language prompts through `VoiceInkLocalWhisperPromptCatalog`; macOS and iOS local Whisper fallback prompts now read stored custom prompts through the shared catalog.
- macOS `AudioProcessor` delegates AVAudioFile channel averaging and normalization for Whisper samples plus float-to-PCM16 WAV sample conversion to `VoiceInkPCM16Audio`; macOS still owns AVAudioFile reading, sample-rate conversion, and WAV writing.
- macOS local Whisper, macOS FluidAudio, and iOS local Whisper load WAV-file PCM16 samples through `VoiceInkPCM16Audio`; platform shells still own model/context lifetime and provider-specific error mapping.
- macOS `CoreAudioRecorder` delegates interleaved Float32 device-sample mixing, optional linear resampling, and PCM16 clipping to `VoiceInkPCM16Audio`; macOS still owns CoreAudio buffers, pre-roll buffering, file writes, and live chunk delivery.
- macOS pre-roll streaming and buffered-snapshot streaming split mono PCM16 data through `VoiceInkPCM16Audio.monoPCM16Chunks`; macOS still owns streaming sessions, callbacks, and quick-release orchestration.
- macOS batch cloud and streaming transcription use `VoiceInkProviderCredential` for runtime API-key presence checks before entering provider adapters.
- macOS API-key lookup reads fallback environment-variable names from `VoiceInkProviderAPIKeyAccount`; Keychain access remains in the macOS shell.
- macOS cloud-provider model lists are supplied by the `CloudProvider` default adapter over `VoiceInkTranscriptionModelCatalog`; the old standalone cloud-model adapter file is folded into `CloudProvider`, so the macOS shell only owns streaming factories and platform storage context.
- macOS cloud-provider recorded-file support is derived from `VoiceInkTranscriptionModelProvider.supportsRecordedFileTranscription`, so Cartesia remains streaming-only without a shell-only override.
- macOS Native Apple and Parakeet model structs adapt `VoiceInkTranscriptionModelCatalog` local model specs; macOS still owns OS availability and FluidAudio download/runtime code.
- macOS language pickers use `VoiceInkLanguageCatalog.sortedOptions` so language presentation order stays shared with iOS.
- macOS recording, audio-file transcription, and retry transcription use `VoiceInkTranscriptionCleanupConfiguration` directly for shared raw-output filtering and cleanup preferences.
- macOS model definitions read supported language sets through a thin `ModelProvider` adapter backed by `VoiceInkLanguageCatalog`; the old `LanguageDictionary` wrapper is gone.
- macOS metrics dashboard duration copy uses `VoiceInkDurationPresentation`, removing the last dashboard-local duration formatter.
- macOS predefined prompt persistence adapts `VoiceInkPredefinedPrompts` into `VoiceInkCustomPrompt`, so stable prompt IDs and metadata live in shared core.
- macOS custom prompt final text delegates to `VoiceInkAIPrompts.finalPromptText`, so the system-instruction wrapper stays shared.
- macOS uses `VoiceInkCustomPrompt` directly, keeping the SwiftUI prompt-grid adapter in the macOS shell while moving the prompt record and Codable compatibility into `VoiceInkCore`.
- macOS predefined-prompt initialization now delegates to `VoiceInkCustomPromptPolicy`, and the old shell-only `PredefinedPrompts` adapter was removed.
- macOS custom prompt add/update/delete selection behavior delegates to `VoiceInkCustomPromptPolicy`; macOS `AIEnhancementService` still owns persistence timing, notifications, and SwiftUI state.
- macOS custom prompt loading, saving, and selected-prompt persistence now use `VoiceInkCustomPromptStorage`.
- macOS AI-enhancement prompt selection delegates selected-prompt repair and base prompt text to `VoiceInkCustomPromptPolicy`; macOS still appends selected-text, clipboard, screen-capture, and vocabulary context before executing provider requests.
- macOS PowerMode AI-enhancement prompt setup delegates nil-selection fallback to `VoiceInkCustomPromptPolicy`; PowerMode still owns OS app/website detection, AI provider/model UI, active-session application, shortcuts, and config persistence.
- macOS `PowerModeManager` and `PowerModeConfigView` call `VoiceInkPowerModePolicy` directly for URL normalization, app/website/default matching, enabled-rule checks, and save validation; macOS uses `VoiceInkPowerModeValidationError` directly while keeping the stored `PowerModeConfig` shape and SwiftUI alert as shell code.
- macOS prompt-trigger detection delegates result construction to `VoiceInkPromptDetectionPolicy`; macOS `AIEnhancementService` now adapts the shared detection result directly into shell prompt state, and the old shell-only `PromptDetectionService` adapter was removed.
- macOS AI-enhancement prompt-store preferences now use `VoiceInkUserDefaultsKey`, preserving the same raw storage names while making future iOS prompt-store adoption share the same keys.
- macOS AI-enhancement provider selection uses `VoiceInkAIEnhancementProviderKind` directly plus `VoiceInkUserDefaultsKey` for persisted provider identity, selectable text-enhancement providers, model-selection keys, and API-key requirement; macOS keeps dynamic provider settings and execution adapters.
- macOS AI-enhancement stored-provider parsing delegates canonical and legacy values to `VoiceInkAIEnhancementProviderKind`; macOS still owns the actual `UserDefaults` and Power Mode config storage.
- macOS AI-enhancement connected-provider selection delegates provider readiness policy to `VoiceInkAIEnhancementProviderKind`; macOS still supplies live API-key, Ollama, and Local CLI readiness.
- macOS AI-enhancement current-model selection delegates selected-model fallback to `VoiceInkAIEnhancementProviderKind`; macOS still supplies dynamic Ollama/OpenRouter model lists and provider defaults from local settings.
- macOS AI-enhancement API-key verification dispatch reads `VoiceInkAIEnhancementProviderKind.apiKeyVerificationRoute`; native provider checks route through `VoiceInkProviderAPIKeyVerifier`, while Anthropic, OpenRouter, OpenAI-compatible, and Custom keep macOS LLMkit model-specific verification.
- macOS AI-enhancement provider model defaults and static model lists come from `VoiceInkAIModelCatalog`; macOS still owns provider UI, API-key storage, dynamic OpenRouter fetches, Ollama, Local CLI, and Custom provider settings.
- macOS AI-enhancement request endpoint and API-key console URLs come from the shared `VoiceInkAIModelProvider` and `VoiceInkAIEnhancementProviderKind` catalogs; macOS still owns Anthropic/OpenAI-compatible transport selection, provider-specific verification adapters, and SwiftUI rendering.
- macOS AI-enhancement failures throw `VoiceInkAIEnhancementError`, classify HTTP status and retryable Foundation transport-network failures through core, and route retry decisions through `VoiceInkAIEnhancementRetryState` from `VoiceInkCore`; macOS still owns LLMkit/Ollama/Local CLI error mapping, sleep timing, and logging.
- macOS `AIService`, `OllamaService`, and `APIKeyManagementView` read/write dynamic Ollama, Custom provider, and OpenRouter model cache preferences through `VoiceInkDynamicAIProviderPreference`; macOS still owns the dynamic-provider clients and keeps the existing caller-specific Ollama fallback models.
- macOS and iOS provider API-key lookup delegates stored-key reference resolution and provider environment fallback policy to `VoiceInkProviderAPIKeyLookup`; typed iOS provider callers use `VoiceInkProviderKind`, while dynamic macOS provider-name callers keep the string overload. Platform shells still own Keychain storage and UI editing state.
- macOS and iOS provider API-key screens use `VoiceInkSecretPresentation` for stored-key display obfuscation while keeping platform-specific key storage and verification flows.
- macOS and iOS recording audio filename construction delegates live recording, imported transcription, retranscription, and timestamped iOS recording naming to `VoiceInkStoredAudioFile`; platform shells still own directory choice and actual audio capture/copy/write work.
- macOS and iOS `Transcription` SwiftData models conform to `VoiceInkStoredAudioRecord`, so record-level audio URL resolution, availability checks, missing-audio fallback text, existence checks, and deletion use the same shared interface while each shell still supplies its recording directory.
- macOS open-file routing and audio-file transcription queue validation delegate supported audio/video file checks to `VoiceInkSupportedMedia`; platform shells still own open panels, drag/drop providers, and transcription queue state.
- macOS CSV export delegates header, row formatting, and escaping to `VoiceInkTranscriptionCSVExporter`; macOS still owns `NSSavePanel` and mapping SwiftData `Transcription` records into export records.
- macOS transcript details and CSV export delegate power-mode display formatting to `VoiceInkPowerModePresentation`.
- macOS and iOS local Whisper model directory creation, local `.bin` listing, download URL/file path lookup, runtime selected-model file resolution, final downloaded-file installation, bootstrap-model availability, Core ML support checks, and model deletion delegate to `VoiceInkWhisperModelFiles`; macOS uses `VoiceInkWhisperLocalModelFile` directly while platform shells still own download progress, UI, and runtime model state.
- macOS waveform playback and iOS note audio playback use `VoiceInkAudioPlaybackTimeline` for clamped progress and seek math; platform shells still own `AVAudioPlayer`, hover/drag gestures, and rendering.
- macOS and iOS local Whisper and macOS rolling preload resolve the Silero VAD bundle resource directly through `VoiceInkVADModelFiles`; the old shell-only VAD model manager adapters were removed.
- macOS `FluidAudioStreamingProvider` runs stable partial-transcript confirmation through `WordAgreementEngine` in `VoiceInkCore`; `FluidAudioWordTimingAdapter` remains a macOS shell adapter because it imports the FluidAudio token type.
- macOS streaming sessions choose final-commit wait time through `VoiceInkStreamingFinalCommitTimeout`, preserving the shorter local FluidAudio finalization path and the longer cloud-provider timeout.
- macOS cloud streaming providers use `VoiceInkStreamingTranscriptionEvent` directly; `StreamingTranscriptionProvider` keeps the single `LLMkit` event forwarding adapter while FluidAudio emits local ASR events directly.
- macOS cloud streaming providers use `VoiceInkStreamingTranscriptionError` directly for shared streaming error descriptions; `StreamingTranscriptionProvider` keeps the macOS `LLMkit` adapter and deletes provider-local duplicate error mappers.
- macOS `TranscriptionServiceRegistry`, `TranscriptionModel`, streaming model-card toggles, and streaming-key migration use `VoiceInkTranscriptionStreamingPreference`; macOS still adapts `TranscriptionModel` and `CloudProvider` into the shared streaming preference snapshot.
- macOS startup calls `VoiceInkStreamingKeysMigration` directly before model loading, so old streaming flags and removed realtime model names are repaired in shared core while app launch ordering remains macOS-owned.
- macOS rolling-buffer preload settings, backup import/export, app defaults, settings UI, diagnostics, and coordinator preload gates use `VoiceInkRollingBufferPreloadSettings` and `VoiceInkRollingBufferPreloadPolicy` directly; macOS still owns IOKit power-state reads, VAD startup, rolling audio source delivery, and quick-release diagnostics storage.
- macOS rolling-buffer lead-in retention uses `VoiceInkRollingAudioBuffer` for max-byte trimming and chunk/data snapshots; macOS still owns the audio source stream, VAD windows, preload sessions, and quick-release orchestration.
- macOS special shortcut empty-tap fallback delegates short-press and empty-completed-transcript eligibility to `VoiceInkSpecialShortcutEmptyFallbackPolicy`; `LastTranscriptionService` still owns SwiftData lookup and cursor paste.
- macOS special shortcut key-up handling delegates unsafe key-evidence discard decisions to `VoiceInkSpecialShortcutKeyEvidencePolicy`; `ShortcutMonitor` still owns macOS keyboard event collection and now passes `VoiceInkShortcutPressContext` directly.
- macOS recorder state and UI toggle actions now use `VoiceInkRecordingState` and `VoiceInkRecorderUIToggleAction` directly; `RecordingShortcutManager`, `RecorderUIManager`, and rolling preload use shared state gates while macOS owns recorder UI/window execution.
- macOS `AppDefaults` registers core-owned default values through `VoiceInkDefaultSettings`, while keeping macOS-specific defaults such as selected language, current model, Launch at Login, shortcuts, and UI behavior in the shell.
- macOS history/import row summaries, macOS audio-file row action text, and iOS note detail display use `VoiceInkTranscriptPresentation` for the enhanced-text-first transcript display rule and shared empty-content fallback copy.
- `VoiceInkTranscriptPresentation.matchesSearch` mirrors macOS history predicate search semantics, keeping iOS note filtering accent-insensitive through shared core while macOS SwiftData predicates keep their local query shape.
- macOS last-transcription paste eligibility and iOS note-row status text use `VoiceInkTranscriptPresentation` defaults for canceled/empty/pending/failed transcript presentation; platform shells still own colors, icons, retry controls, and paste execution.
- macOS `FillerWordManager`, iOS `AppSettings`, and cleanup configuration load and save filler-word lists through `VoiceInkFillerWordPreference`; macOS and iOS setting surfaces use `VoiceInkFillerWords.normalizedWord` for add-button draft validation while platform shells still own settings UI and toggle state.
- iOS app launch and first-time setup read/write/reset onboarding completion through `VoiceInkOnboardingPreference`; the onboarding views and recording-after-onboarding flow stay in the iOS shell.
- iOS `AppSettings` reads/writes/resets audio-session timeout through `VoiceInkAudioSessionTimeoutPreference`; `AudioSessionManager` and timeout UI stay in the iOS shell.
- iOS `AppSettings.resetAll()` restores in-memory reset values from `VoiceInkDefaultSettings.iOS` and clears persisted core settings through `VoiceInkSharedPreferenceReset`, including modes, onboarding, verification flags, transcription prompt/language/model settings, cleanup settings, AI-enhancement provider/model settings, dynamic provider caches, custom prompts, VAD, and filler-word overrides; the iOS shell still owns keychain and file deletion.
- macOS transcription services, Power Mode, rolling preload, and iOS `AppSettings` read/write/clear selected transcription language through `VoiceInkTranscriptionLanguagePreference`; platform shells still own settings UI and language-change notifications.
- macOS `TranscriptionModel` exposes shared language options and fallback repair through `VoiceInkTranscriptionLanguageSupport`; macOS still adapts `ModelProvider`, keeps custom-model stored language lists, and reads per-model AssemblyAI streaming preference state. The standalone `TranscriptionLanguageSupport` wrapper is deleted.
- macOS paste/pipeline, audio-file transcription, Power Mode, backup import/export, `FillerWordManager`, and iOS `AppSettings` read/write/reset cleanup toggles through `VoiceInkTranscriptionCleanupPreferenceStorage` and `VoiceInkTranscriptionCleanupSettings`; macOS transcription paths and iOS retry share `VoiceInkPreparedTranscriptionText` for filtered text, word-replacement input, and final cleaned output. SwiftUI setting controls still bind directly through `@AppStorage`.
- iOS `AppSettings` stores word-replacement rules through `VoiceInkWordReplacementPreference`, validates additions through `VoiceInkDictionaryPolicy`, and passes sorted rules into `VoiceInkTranscriptionRunProcessor`; macOS still owns SwiftData dictionary storage and cache invalidation.
- iOS `AppSettings` stores custom vocabulary terms through `VoiceInkCustomVocabularyPreference`, normalizes them through `VoiceInkCustomVocabularyTerms`, and passes them through `VoiceInkTranscriptionRunProcessor` into `VoiceInkAudioTranscriptionService`; macOS still owns SwiftData vocabulary storage and provider-specific streaming dictionary adapters.
- macOS `TranscriptionPipeline` reads short post-processing skip settings through `VoiceInkPostProcessingSkipConfiguration.current()` before applying `VoiceInkPostProcessingSkipPolicy`; platform shells still own the enhancement UI and the decision point.
- macOS `SessionMetricRecorder` and `SessionMetricMigrationService` calculate word count, positive durations, and speed factor through `VoiceInkSessionMetricPolicy`; macOS still owns duplicate-record checks, SwiftData insertion, migration scheduling, and metric notifications, while iOS records now conform to the same metric source interface for future stats.
- macOS `MetricsContent` accumulates dashboard words/duration and derives time saved, words per minute, and keystrokes saved through `VoiceInkDashboardMetrics`; macOS still owns SwiftData loading, cache lifetime, accessibility status, and dashboard rendering.
- macOS `PerformanceAnalyzer` and `ModelPerformancePanel` delegate transcription/enhancement model grouping, averages, speed-factor calculation, speed-factor display text, and average-processing-time display text to `VoiceInkPerformanceAnalyzer`; macOS still owns SwiftData queries, time filters, system-info lookup, and SwiftUI rendering, while iOS records already conform to the same performance record interface.
- macOS `AIEnhancementService` reads request timeout and retry-on-timeout through `VoiceInkAIEnhancementRequestPreference`; SwiftUI setting controls still bind directly through `@AppStorage`.
- macOS `TranscriptionModelManager`, `PowerModeConfig`, and `SystemInfoService` use `VoiceInkCurrentTranscriptionModelPreference` for the selected transcription model; the shared streaming-keys migration also repairs stored model names through the same preference, while the legacy `"CurrentModel"` cleanup remains macOS shell migration code.
- macOS `AIService`, `PowerModeConfig`, `PowerModeConfigView`, and `SystemInfoService` use `VoiceInkAIEnhancementProviderPreference` for selected AI provider/model storage; macOS still owns API-key lookup, Ollama/OpenRouter dynamic state, and provider execution.
- macOS `AIEnhancementService` delegates selected-text, clipboard, current-window, custom-vocabulary prompt text, and custom-vocabulary tag assembly to `VoiceInkAIEnhancementPromptBuilder`/`VoiceInkAIEnhancementVocabularyContext`; macOS still owns Accessibility, pasteboard, screen capture, and SwiftData vocabulary collection.
- macOS prompt-trigger restoration uses `VoiceInkPromptDetectionResult` state helpers, so temporary trigger-selected prompts restore the original selected prompt even when the original selection was nil.
- macOS recorder and audio-file transcription enhancement failures use `VoiceInkPostProcessingFailurePresentation` for stored failure text and notification title truncation while preserving their current error-description source.
- macOS audio-file transcription retry and failure surfaces now use `VoiceInkErrorDescription`, matching iOS record failure text and shared run-processor failures while keeping shell ownership of notifications and queue state.
- macOS audio-file import/retranscription uses `VoiceInkEngineError` for no-model-selected and missing-stored-audio failures, and no longer keeps unused shell-only observable transcription state.
- macOS audio-file import and retranscription records now persist the shared `.completed` transcription status explicitly, matching the recorder pipeline and iOS shared record updater while keeping SwiftData model storage in the macOS shell.
- macOS audio-file import and retranscription use `VoiceInkPostProcessingSkipPolicy`, matching the recorder pipeline and iOS run processor short-transcript skip behavior while preserving macOS prompt-trigger override on retry.
- macOS `TranscriptionAutoCleanupService`, `ImportExportService`, `BackupImporter`, `SystemInfoService`, and app startup read/write transcription auto-cleanup preferences through `VoiceInkTranscriptionAutoCleanupPreference`; settings UI still binds directly through `@AppStorage`.
- macOS `AudioCleanupManager`, audio cleanup settings, backup import/export, app defaults, and system diagnostics read/write audio-file cleanup preferences through `VoiceInkAudioCleanupPreference`; macOS still owns transcript queries, file deletion, cleanup timers, and the UI.
- iOS retry post-processing inherits `VoiceInkAIReasoningConfig` through `VoiceInkPostProcessingClient`, aligning OpenAI-compatible reasoning controls with macOS enhancement requests.
- iOS retry post-processing failure text is produced through `VoiceInkPostProcessingFailurePresentation`, keeping the existing `"Post-processing failed:"` prefix shared with core tests.

Current iOS consumers of shared remote transport:

- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` creates `VoiceInkRemoteTranscriptionService` for remote providers and the iOS local Whisper adapter for `.localWhisper`.
- `VoiceInkRemoteTranscriptionService` dispatches Groq/OpenAI/Cerebras, Deepgram, Gemini, Mistral, ElevenLabs, Soniox, Speechmatics, AssemblyAI, and xAI through shared core clients.
- Provider-initialized `VoiceInkRemoteTranscriptionService.transcribeAudioFile` now derives file transcription options from the same `VoiceInkRemoteTranscriptionOptions.batchDefaults` policy used by macOS batch cloud transcription, while direct transport initialization keeps prompt-only custom behavior.
- `VoiceInkAudioTranscriptionService` is transcription-only; API-key verification is kept in `VoiceInkProviderAPIKeyVerifier` so retry transcription adapters do not expose a dead verification interface.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` routes iOS transcription through `VoiceInkTranscriptionRunProcessor`, including shared output filtering, provider transcription empty-output policy, cleanup preferences from `AppSettings`, a macOS-order word-replacement hook before post-processing, and shared mutable-record transitions for completed and failed retry results.
- iOS retry now applies stored-audio retranscription success and failure state through the shared `VoiceInkMutableTranscriptionRecord` + `VoiceInkStoredAudioRecord` default, leaving the iOS shell responsible only for settings and provider adapters.
- `VoiceInkTranscriptionRunProcessor` now measures transcription and successful post-processing durations in shared core, and `VoiceInkMutableTranscriptionRecord.applyCompletedRunResult(_:)` persists them, so iOS retry/background transcription records feed the same metric and performance fields as macOS records.
- iOS `Transcription` records conform to both `VoiceInkSessionMetricSource` and `VoiceInkDashboardMetricRecord`, inheriting dashboard word/audio values from the shared session metric policy; `iOS/VoiceInk-ios/NotesListView.swift` builds its note-list word/audio summary through `VoiceInkDashboardMetricsAccumulator`, so the iOS shell consumes the same dashboard metric interface as macOS.
- `iOS/VoiceInk-ios/NotesListView.swift` also derives its fastest-model note-list summary and speed-factor display text from `VoiceInkPerformanceAnalyzer`, so iOS consumes the same shared model performance interface as the macOS metrics panels while keeping the iOS UI shell separate.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` passes `VoiceInkPostProcessingSkipConfiguration.current()` into `VoiceInkTranscriptionRunProcessor`, so iOS retry transcription follows the same short-transcript post-processing skip policy as macOS unless a prompt trigger explicitly forces post-processing.
- `iOS/VoiceInk-ios/AppSettings.swift` and `VoiceInkTranscriptionRunProcessor` use the shared provider credential policy so whitespace-only provider keys fail as missing before provider transport runs.
- `iOS/VoiceInk-ios/AppSettings.swift` loads retry transcription cleanup configuration through `VoiceInkTranscriptionCleanupConfiguration.current()`, aligning iOS cleanup with macOS defaults while keeping settings UI/storage in the iOS shell.
- `iOS/VoiceInk-ios/AppSettings.swift` passes the shared paragraph-formatting preference into `VoiceInkTranscriptionRunProcessor`, so iOS retry transcription uses the same `VoiceInkTranscriptParagraphFormatter` policy as macOS.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` passes the iOS selected transcription language through `VoiceInkTranscriptionRunProcessor`, which normalizes auto-detect before remote/local transcription adapters receive it.
- `iOS/VoiceInk-ios/WhisperTranscriptionService.swift` passes the shared selected-language local Whisper prompt helper into the iOS whisper.cpp wrapper and returns empty local transcripts unchanged, so iOS inherits the macOS language seed prompts and the shared local empty-output policy.
- `iOS/VoiceInk-ios/WhisperTranscriptionService.swift` resolves the selected mode's local Whisper model path through `VoiceInkWhisperModelFiles`, preserving today's base-model behavior while keeping future local model selection on the shared runtime-model contract.
- `iOS/VoiceInk-ios/LibWhisper.swift` reads `VoiceInkWhisperRuntimeConfiguration` to assemble language, prompt, thread count, temperature, and VAD settings before adapting them into whisper.cpp, so missing settings use the shared macOS default while keeping iOS whisper.cpp execution in the iOS shell.
- `iOS/VoiceInk-ios/AudioRecorder.swift` maps AVFoundation recorder settings from `VoiceInkPCM16Audio`, so iOS live recording uses the same 16 kHz mono, 16-bit little-endian integer format contract as macOS local transcription while keeping capture/session lifecycle in the iOS shell.
- macOS `Recorder` and iOS `AudioRecorder` normalize audio-meter decibels through `VoiceInkAudioMeterLevel`; macOS still owns smoothing state/timer delivery, and iOS still owns the visible level history.
- iOS `RecordingManager` uses `VoiceInkRecordingState` directly, currently using the shared `.idle`/`.recording` subset while preserving iOS-specific permission, sheet, App Group, and audio-session behavior in the shell.
- `iOS/VoiceInk-ios/VoiceInk-ios/Transcription.swift` supplies its Documents/Recordings directory through `VoiceInkStoredAudioRecord`, so iOS note detail, retry transcription, and deletion share the same record-level audio-file behavior as macOS.
- `iOS/VoiceInk-ios/ProviderAPIKeyView.swift` verifies stored provider keys through `VoiceInkProviderAPIKeyVerifier` and delegates draft-key verification/save-after-verify policy to `VoiceInkProviderAPIKeyDraft`; `iOS/VoiceInk-ios/AppSettings.swift` delegates stored/runtime key state, readiness, and verification reset-on-change behavior to `VoiceInkProviderAPIKeyState`. macOS provider-key screens still use `VoiceInkProviderCredential.nonBlank` for draft-key submit enablement, so shared core owns blank-key policy before transport verification without changing platform key-storage behavior.
- `iOS/VoiceInk-ios/AppSettings.swift` and `ModeConfigurationView.swift` delegate active-mode transcription language availability, provider-change model repair, and selected-language repair to the shared `Mode` policy; `SettingsView` keeps only the SwiftUI option rendering.
- `VoiceInkTranscriptionRunProcessor` callers receive runtime mode configurations with stale transcription and post-processing model IDs repaired by `Mode`, so persisted iOS mode records cannot bypass the shared provider model-selection policy.
- `VoiceInkModeStorage.loadModes()` repairs stale transcription and post-processing model IDs before `AppSettings` exposes loaded modes to iOS UI or retry transcription.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` passes the selected transcription language and local Whisper prompt into `VoiceInkTranscriptionRunProcessor`, so runtime transcription input is explicit and the iOS local Whisper adapter does not read app preferences directly.
- `iOS/VoiceInk-ios/WhisperTranscriptionService.swift` throws `VoiceInkEngineError` from `VoiceInkCore` instead of owning a separate iOS-only local Whisper error enum.
- Cartesia remains absent from iOS transcription provider selection until an iOS streaming adapter exists; it is not a batch provider.
- The bundled `VoiceInk` provider case remains decodable and ready as a bundled service, but shared provider selectability keeps it hidden from iOS transcription and post-processing selection until a real no-key/bundled-service adapter exists. The sibling clone marked it always available while returning an empty API key, so porting that path would preserve a broken no-key mode.

Platform shells still own UI, OS permissions, audio capture, paste/keyboard behavior, keychain adapters, local model download storage, SwiftData models, and macOS-only orchestration. iOS-only shell code shared between the app and keyboard extension lives in `iOS/Shared/`, not `VoiceInkCore`; this currently includes App Group recording-state keys, stale-recording expiry policy, Darwin notification names, and the keyboard-to-app deep-link contract.

iOS app-local storage roots are kept in `iOS/VoiceInk-ios/VoiceInkIOSStorageDirectories.swift`: the iOS shell owns the Documents/Caches base directories, while `VoiceInkCore` still owns recordings/model subdirectory names and file policies.

## Sibling Clone Status

The remaining Swift files present in `../VoiceInk-iOS` but not in `VoiceInk/iOS` are old clone-side sources, except where noted. `scripts/verify-ios-single-repo-migration.sh` now fails if any of these obsolete app-target duplicates are copied back under `iOS/VoiceInk-ios/`.

- `AppGroupCoordinator.swift`: moved into `iOS/Shared/AppGroupCoordinator.swift`; start-recording requests now use `iOS/Shared/VoiceInkAppDeepLink.swift`, while shared App Group/Darwin notification state still handles stop requests and keyboard recording-state feedback.

- `DeepgramTranscriptionService.swift`: replaced by `VoiceInkCore` Deepgram request/client helpers and `VoiceInkRemoteTranscriptionService`.
- `GroqTranscriptionService.swift`: replaced by `VoiceInkCore` OpenAI-compatible request/client helpers and `VoiceInkRemoteTranscriptionService`.
- `OpenAICompatibleClient.swift`: replaced by `VoiceInkCore` chat DTOs/request builder/client.
- `LLMPostProcessor.swift`: replaced by `VoiceInkPostProcessingRequest`, `VoiceInkPostProcessingClient`, and `VoiceInkTranscriptionRunProcessor`.
- `TranscriptionServiceFactory.swift`: replaced by `VoiceInkTranscriptionRunProcessor` service-provider injection plus the iOS local Whisper adapter and shared `VoiceInkRemoteTranscriptionService`.
- `RiffWaveUtils.swift`: replaced by `VoiceInkPCM16AudioSamples`.
- `VADModelManager.swift`: replaced by direct `VoiceInkVADModelFiles.sileroPath()` calls from the macOS/iOS Whisper shells and macOS rolling preload.
- `DefaultModeManager.swift`: replaced by `AppSettings.ensureDefaultModeExists()` plus `Mode.defaultModesAndSelection()`.
- `Mode.swift`, `PromptTemplate.swift`, `Provider.swift`: replaced by `VoiceInkCore` mode, prompt-template, and provider catalog modules.
- `ModeSelectionView.swift`, `ModesView.swift`: obsolete iOS UI experiments; current in-repo iOS mode UI is `iOS/VoiceInk-ios/ModeConfigurationView.swift`.
- `Item.swift`: unused SwiftData template sample.
- `VoiceInk_iosTests.swift`, `VoiceInk_iosUITests.swift`, `VoiceInk_iosUITestsLaunchTests.swift`: kept in the in-repo iOS target as real migration/runtime smoke coverage; the old stock-template assertions from the sibling clone should not be copied back.

Do not copy these files back into `VoiceInk/iOS`. If behavior from one appears missing, port it into `VoiceInkCore` or the appropriate platform shell with a focused test.

## Deletion Gates

Before treating `../VoiceInk-iOS` as obsolete, verify current state from `VoiceInk/`:

Run the bundled static verifier first:

```bash
scripts/verify-ios-single-repo-migration.sh
```

When real Xcode, app dependencies, and the iOS platform are installed, run the same verifier with app builds enabled:

```bash
scripts/verify-ios-single-repo-migration.sh --full-build
```

1. `VoiceInk.xcworkspace` includes `iOS/VoiceInk-ios.xcodeproj`.
2. macOS and iOS projects both resolve `VoiceInkCore` from inside `VoiceInk/`.
3. `VoiceInk/` is the git root for this work, and the abandoned parent-level Swift package shape (`../VoiceInkCore`, `../Package.swift`, `../Sources/VoiceInkCore`, `../Tests/VoiceInkCoreTests`) remains absent.
4. `VoiceInkCore` stays platform-neutral: no AppKit, UIKit, SwiftUI, SwiftData, AVFoundation, CoreAudio, IOKit, FluidAudio, KeyboardKit, LLMkit, WhisperKit, or whisper.cpp module imports in shared sources or core checks.
5. macOS and iOS app product/display names stay `roma just talk`, and the iOS record deep-link scheme stays `voiceink`.
6. `swift run VoiceInkCoreChecks` passes from `VoiceInkCore/`.
7. macOS Swift sources parse or build.
8. iOS app, keyboard, unit-test, and UI-test Swift sources parse or build.
9. `plutil -lint` passes for both project files and iOS plists/entitlements.
10. `xmllint --noout` passes for workspace and shared scheme XML.
11. iOS shared shell files are present under `iOS/Shared/`: `AppGroupCoordinator.swift`, `VoiceInkAppDeepLink.swift`, and `VoiceInkAppGroupRecordingBridge.swift`.
12. iOS non-Swift app artifacts are present: privacy manifest, app icon catalog files, and bundled Silero VAD resource.
13. Obsolete clone-side Swift duplicates remain absent from `iOS/VoiceInk-ios/`.
14. When `../VoiceInk-iOS` exists, every sibling-only Swift file under `VoiceInk-ios/` is one of the documented obsolete/replaced files above.
15. Legacy same-file clone shims remain absent from the in-repo iOS app and keyboard: `TranscriptionServiceFactory`, `LLMPostProcessor`, the old local `RecordingState`, raw `voiceink://record` URL construction, `Open VoiceInk` keyboard copy, and old `AppSettings` effective-provider/model accessors.
16. A real Xcode toolchain is selected and both app targets build.

Current local blocker: `xcode-select -p` points to `/Library/Developer/CommandLineTools`, and the previously used external Xcode volume is not mounted. Full target builds are still environment-blocked until a real Xcode is selected; macOS `VoiceInk` also needs `/Users/atalphalnmomhappyhouse/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework`, and iOS `VoiceInk-ios` needs the iOS 26.2 platform installed. Until those are present, use `swift run VoiceInkCoreChecks` plus the static parse/lint gates above for local proof.
