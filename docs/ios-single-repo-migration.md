# iOS Single-Repo Migration

`VoiceInk/` is the source repo. The sibling `../VoiceInk-iOS` checkout is evidence only.

## Current Shape

- macOS app: `VoiceInk.xcodeproj`
- iOS app and keyboard targets: `iOS/VoiceInk-ios.xcodeproj`
- iOS app/keyboard shared shell code: `iOS/Shared/`
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
- transcription prompt preference loading for local Whisper and nonblank request prompts for remote/realtime providers
- post-processing request construction and output filtering
- provider catalog, provider endpoints, API key account names, and provider readiness policy
- provider API-key fallback environment-variable names
- provider credential nonblank validation for runtime API-key checks
- provider API-key verification dispatch
- provider API-key verification flag storage
- API-key environment-reference resolution and provider runtime-key lookup/fallback policy
- AI reasoning temperature, effort, and provider-specific hidden-reasoning request parameters for OpenAI-compatible post-processing
- AI-enhancement provider identity, persisted-name parsing, API-key requirement, text-enhancement selectability, connected-provider selection policy, storage keys, model-selection key naming, and mapping to shared model providers; platform shells still own storage and execution
- AI-enhancement API-key verification transport metadata; macOS still owns concrete verification clients
- AI-enhancement model defaults, static model lists, and selected-model fallback policy for macOS AI providers; platform shells still own dynamic providers such as Ollama, OpenRouter fetching, Local CLI, and Custom
- AI-enhancement provider request endpoints and API-key console URLs for macOS AI providers; platform shells still own provider UI and request execution
- transcription and AI model catalogs
- Native Apple and FluidAudio local transcription model metadata; platform shells still own availability, download, and runtime adapters
- remote transcription provider dispatch for iOS retry transcription
- mode runtime configuration and selected-mode repair
- mode provider-selection repair and draft saveability rules
- shared UserDefaults key names, including cleanup preferences, plus iOS mode persistence helpers
- current transcription model preference loading/saving/clearing; platform shells still own model availability, download/runtime state, and legacy key cleanup
- transcript status and presentation helpers
- local transcription/model/missing-audio error vocabulary shared by macOS local Whisper and iOS local retry transcription
- raw transcription output filtering for hallucination tags/brackets, optional filler words, default filler-word vocabulary, and filler-word list editing policy; iOS settings now use the same list editing policy in their platform shell
- transcription cleanup preference loading/saving/reset storage, raw-output filtering, and paragraph-formatting/punctuation/lowercase/filler-word cleanup policy
- filler-word list storage defaults and saving
- cursor-aware transcript capitalization policy; platform shells only supply cursor text and paste targets
- NaturalLanguage word-count policy for metrics and short-enhancement skip decisions
- short post-processing skip policy, stored skip configuration, and storage defaults for brief transcripts; platform shells still own UI controls and whether to apply the policy
- AI-enhancement timeout/retry storage keys, defaults, and runtime preference reads; platform shells still own request execution, provider transport, logging, and UI controls
- AI-enhancement selected-provider and per-provider selected-model preference storage, including legacy selected-provider repair; platform shells still own provider execution and dynamic model discovery
- NaturalLanguage transcript paragraph formatting policy plus text-formatting storage key/default; platform shells still own the setting UI and when formatting runs
- word-replacement ordering and text application policy; platform shells still own dictionary storage
- vocabulary, word-replacement, backup dictionary insert, and word-replacement edit planning; platform shells still own dictionary storage and persistence errors
- custom vocabulary term normalization for transcription providers; platform shells still own dictionary storage
- custom cloud transcription model generated-name and draft validation policy; platform shells still own keychain and preferences storage
- prompt trigger-word detection, trigger-word editing policy, and prompt-trigger AI-enhancement detection result construction; platform shells still own prompt persistence and enhancement state mutation
- AI-enhancement custom prompt record shape, Codable compatibility, and final-prompt wrapping; macOS still owns SwiftUI prompt rendering and prompt-store orchestration
- predefined-prompt repair/merge policy and trigger-detectable prompt filtering; macOS still owns when the prompt store is loaded and saved
- AI-enhancement custom prompt array mutation, selected-prompt repair, and selected-prompt persistence helpers; platform shells still own notifications and UI state updates
- selected-prompt repair, enable-time prompt fallback, and base prompt-text selection for AI enhancement; platform shells still own context capture and request execution
- AI-enhancement prompt-store and context-toggle storage keys; macOS still owns persistence timing, notifications, and UI orchestration
- transcription language catalog, provider language filtering, AssemblyAI realtime/batch language policy, selected-language fallback policy, language-option ordering, selected-language preference loading/saving/clearing, compatible selected-language persistence, selected-language request normalization, and the shared selected-language defaults key; platform shells still own selected-language UI and runtime streaming-mode state
- local Whisper language seed prompts and custom language-prompt storage key; platform shells still own prompt editing UI and when prompts are persisted
- stored audio-file path resolution, existing-file lookup, recordings directory, file URL construction, and recording/import/retranscription filename policy
- duration presentation
- relative timestamp presentation
- Whisper and VAD model file metadata, including platform-base Whisper model directory, model/sidecar file construction, and downloaded-state detection
- local Whisper runtime defaults for thread count, transcription temperature, and VAD thresholds
- VAD bundle resource lookup
- PCM16 sample conversion and mono 16 kHz transcription-audio constants
- OpenAI-compatible, Deepgram, Gemini, Mistral, ElevenLabs, xAI, Soniox, Speechmatics, and AssemblyAI remote transcription request/client helpers
- Cartesia API-key verification request/client helper
- shared multipart form-data construction for remote transcription clients
- shared retried upload helper for multipart remote transcription clients

Current macOS consumers of shared remote transport:

- Groq batch transcription uses `VoiceInkOpenAICompatibleTranscriptionClient`.
- Deepgram batch transcription uses `VoiceInkDeepgramTranscriptionClient`.
- Gemini batch transcription uses `VoiceInkGeminiTranscriptionClient`.
- Mistral batch transcription uses `VoiceInkMistralTranscriptionClient`.
- ElevenLabs batch transcription uses `VoiceInkElevenLabsTranscriptionClient`.
- xAI batch transcription uses `VoiceInkXAITranscriptionClient`.
- Soniox batch transcription uses `VoiceInkSonioxTranscriptionClient`.
- Speechmatics batch transcription uses `VoiceInkSpeechmaticsTranscriptionClient`.
- AssemblyAI batch transcription uses `VoiceInkAssemblyAITranscriptionClient`.
- Custom OpenAI-compatible batch transcription uses `VoiceInkOpenAICompatibleTranscriptionClient`.
- Cartesia API-key verification uses `VoiceInkCartesiaClient`; Cartesia transcription remains streaming-only in platform shell code.
- MacOS cloud-provider API-key verification uses `CloudProvider` default verification backed by `VoiceInkProviderAPIKeyVerifier`; Cartesia stays on `VoiceInkCartesiaClient` because it is streaming-only and not an iOS `VoiceInkProviderKind`.
- macOS local Whisper/model loading throws `VoiceInkEngineError` from `VoiceInkCore`; macOS error descriptions are covered by `VoiceInkEngineErrorTests`.
- macOS local Whisper and cloud transcription normalize selected request language through `VoiceInkTranscriptionLanguagePreference`.
- macOS local Whisper, cloud transcription, and AssemblyAI streaming read transcription prompts through `VoiceInkTranscriptionPromptPreference`.
- macOS batch cloud and streaming transcription use `VoiceInkProviderCredential` for runtime API-key presence checks before entering provider adapters.
- macOS API-key lookup reads fallback environment-variable names from `VoiceInkProviderAPIKeyAccount`; Keychain access remains in the macOS shell.
- macOS cloud-provider model lists are supplied by the `CloudProvider` default adapter over `VoiceInkTranscriptionModelCatalog`, so provider modules only own transport and streaming differences.
- macOS Native Apple and Parakeet model structs adapt `VoiceInkTranscriptionModelCatalog` local model specs; macOS still owns OS availability and FluidAudio download/runtime code.
- macOS language pickers use `VoiceInkLanguageCatalog.sortedOptions` so language presentation order stays shared with iOS.
- macOS recording, audio-file transcription, and retry transcription use `VoiceInkTranscriptionCleanupConfiguration` directly for shared raw-output filtering and cleanup preferences.
- macOS model definitions read supported language sets through a thin `ModelProvider` adapter backed by `VoiceInkLanguageCatalog`; the old `LanguageDictionary` wrapper is gone.
- macOS metrics dashboard duration copy uses `VoiceInkDurationPresentation`, removing the last dashboard-local duration formatter.
- macOS predefined prompt persistence adapts `VoiceInkPredefinedPrompts` into `CustomPrompt`, so stable prompt IDs and metadata live in shared core.
- macOS custom prompt final text delegates to `VoiceInkAIPrompts.finalPromptText`, so the system-instruction wrapper stays shared.
- macOS `CustomPrompt` is now a shell typealias for `VoiceInkCustomPrompt`, keeping the SwiftUI prompt-grid adapter in the macOS shell while moving the prompt record and Codable compatibility into `VoiceInkCore`.
- macOS predefined-prompt initialization now delegates to `VoiceInkCustomPromptPolicy`, and the old shell-only `PredefinedPrompts` adapter was removed.
- macOS custom prompt add/update/delete selection behavior delegates to `VoiceInkCustomPromptPolicy`; macOS `AIEnhancementService` still owns persistence timing, notifications, and SwiftUI state.
- macOS custom prompt loading, saving, and selected-prompt persistence now use `VoiceInkCustomPromptStorage`.
- macOS AI-enhancement prompt selection delegates selected-prompt repair and base prompt text to `VoiceInkCustomPromptPolicy`; macOS still appends selected-text, clipboard, screen-capture, and vocabulary context before executing provider requests.
- macOS PowerMode AI-enhancement prompt setup delegates nil-selection fallback to `VoiceInkCustomPromptPolicy`; PowerMode still owns app/website matching, AI provider/model UI, and config persistence.
- macOS prompt-trigger detection delegates result construction to `VoiceInkPromptDetectionPolicy`; macOS `PromptDetectionService` still adapts `AIEnhancementService` state and restores shell settings after enhancement.
- macOS AI-enhancement prompt-store preferences now use `VoiceInkUserDefaultsKey`, preserving the same raw storage names while making future iOS prompt-store adoption share the same keys.
- macOS AI-enhancement provider selection uses `VoiceInkAIEnhancementProviderKind` and `VoiceInkUserDefaultsKey` for persisted provider identity, selectable text-enhancement providers, model-selection keys, and API-key requirement; macOS keeps dynamic provider settings and execution adapters.
- macOS AI-enhancement stored-provider parsing delegates canonical and legacy values to `VoiceInkAIEnhancementProviderKind`; macOS still owns the actual `UserDefaults` and Power Mode config storage.
- macOS AI-enhancement connected-provider selection delegates provider readiness policy to `VoiceInkAIEnhancementProviderKind`; macOS still supplies live API-key, Ollama, and Local CLI readiness.
- macOS AI-enhancement current-model selection delegates selected-model fallback to `VoiceInkAIEnhancementProviderKind`; macOS still supplies dynamic Ollama/OpenRouter model lists and provider defaults from local settings.
- macOS AI-enhancement API-key verification dispatch reads `VoiceInkAIEnhancementProviderKind.apiKeyVerificationTransport`; macOS still owns the LLMkit and provider-specific verifier calls.
- macOS AI-enhancement provider model defaults and static model lists come from `VoiceInkAIModelCatalog`; macOS still owns provider UI, API-key storage, dynamic OpenRouter fetches, Ollama, Local CLI, and Custom provider settings.
- macOS AI-enhancement request endpoint and API-key console URLs come from the shared `VoiceInkAIModelProvider` catalog; macOS still owns Anthropic/OpenAI-compatible transport selection and provider-specific verification adapters.
- macOS and iOS provider API-key lookup delegates stored-key reference resolution and provider environment fallback policy to `VoiceInkProviderAPIKeyLookup`; platform shells still own Keychain storage and UI editing state.
- macOS and iOS recording audio filename construction delegates live recording, imported transcription, retranscription, and timestamped iOS recording naming to `VoiceInkStoredAudioFile`; platform shells still own directory choice and actual audio capture/copy/write work.
- macOS history/import row summaries and iOS note detail display use `VoiceInkTranscriptPresentation.preferredText` for the enhanced-text-first transcript display rule.
- macOS `FillerWordManager`, iOS `AppSettings`, and cleanup configuration load and save filler-word lists through `VoiceInkFillerWordPreference`; platform shells still own settings UI and toggle state.
- macOS transcription services, Power Mode, rolling preload, and iOS `AppSettings` read/write/clear selected transcription language through `VoiceInkTranscriptionLanguagePreference`; platform shells still own settings UI and language-change notifications.
- macOS paste/pipeline, Power Mode, backup import/export, `FillerWordManager`, and iOS `AppSettings` read/write/reset cleanup toggles through `VoiceInkTranscriptionCleanupPreferenceStorage`; SwiftUI setting controls still bind directly through `@AppStorage`.
- macOS `TranscriptionPipeline` reads short post-processing skip settings through `VoiceInkPostProcessingSkipConfiguration.current()` before applying `VoiceInkPostProcessingSkipPolicy`; platform shells still own the enhancement UI and the decision point.
- macOS `AIEnhancementService` reads request timeout and retry-on-timeout through `VoiceInkAIEnhancementRequestPreference`; SwiftUI setting controls still bind directly through `@AppStorage`.
- macOS `TranscriptionModelManager`, `PowerModeConfig`, `SystemInfoService`, and `StreamingKeysMigration` use `VoiceInkCurrentTranscriptionModelPreference` for the selected transcription model; the legacy `"CurrentModel"` cleanup remains macOS shell migration code.
- macOS `AIService`, `PowerModeConfig`, `PowerModeConfigView`, and `SystemInfoService` use `VoiceInkAIEnhancementProviderPreference` for selected AI provider/model storage; macOS still owns API-key lookup, Ollama/OpenRouter dynamic state, and provider execution.
- iOS retry post-processing inherits `VoiceInkAIReasoningConfig` through `VoiceInkPostProcessingClient`, aligning OpenAI-compatible reasoning controls with macOS enhancement requests.

Current iOS consumers of shared remote transport:

- `iOS/VoiceInk-ios/TranscriptionServiceFactory.swift` creates `VoiceInkRemoteTranscriptionService` for every remote `VoiceInkProviderKind`.
- `VoiceInkRemoteTranscriptionService` dispatches Groq/OpenAI/Cerebras, Deepgram, Gemini, Mistral, ElevenLabs, Soniox, Speechmatics, AssemblyAI, and xAI through shared core clients.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` routes iOS transcription through `VoiceInkTranscriptionRunProcessor`, including shared output filtering and cleanup preferences from `AppSettings`.
- `iOS/VoiceInk-ios/AppSettings.swift` and `VoiceInkTranscriptionRunProcessor` use the shared provider credential policy so whitespace-only provider keys fail as missing before provider transport runs.
- `iOS/VoiceInk-ios/AppSettings.swift` loads retry transcription cleanup configuration through `VoiceInkTranscriptionCleanupConfiguration.current()`, aligning iOS cleanup with macOS defaults while keeping settings UI/storage in the iOS shell.
- `iOS/VoiceInk-ios/AppSettings.swift` passes the shared paragraph-formatting preference into `VoiceInkTranscriptionRunProcessor`, so iOS retry transcription uses the same `VoiceInkTranscriptParagraphFormatter` policy as macOS.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` passes the iOS selected transcription language through `VoiceInkTranscriptionRunProcessor`, which normalizes auto-detect before remote/local transcription adapters receive it.
- `iOS/VoiceInk-ios/WhisperTranscriptionService.swift` passes the shared local Whisper prompt preference into the iOS whisper.cpp wrapper, falling back to `VoiceInkLocalWhisperPromptCatalog` so iOS inherits the macOS language seed prompts when no explicit prompt is stored.
- `iOS/VoiceInk-ios/ProviderAPIKeyView.swift` verifies provider keys through `VoiceInkProviderAPIKeyVerifier`.
- `iOS/VoiceInk-ios/SettingsView.swift` uses `VoiceInkLanguageCatalog.sortedOptions` for the same selected-language option ordering used by macOS.
- `iOS/VoiceInk-ios/WhisperTranscriptionService.swift` throws `VoiceInkEngineError` from `VoiceInkCore` instead of owning a separate iOS-only local Whisper error enum.
- Cartesia remains absent from iOS transcription provider selection until an iOS streaming adapter exists; it is not a batch provider.
- The bundled `VoiceInk` provider case remains decodable, but is hidden from iOS transcription and post-processing selection until a real no-key/bundled-service adapter exists. The sibling clone marked it always available while returning an empty API key, so porting that path would preserve a broken no-key mode.

Platform shells still own UI, OS permissions, audio capture, paste/keyboard behavior, keychain adapters, local model download storage, SwiftData models, and macOS-only orchestration. iOS-only shell code shared between the app and keyboard extension lives in `iOS/Shared/`, not `VoiceInkCore`; this currently includes App Group coordination and the keyboard-to-app deep-link contract.

## Sibling Clone Status

The remaining Swift files present in `../VoiceInk-iOS` but not in `VoiceInk/iOS` are old clone-side sources, except where noted:

- `AppGroupCoordinator.swift`: moved into `iOS/Shared/AppGroupCoordinator.swift`; start-recording requests now use `iOS/Shared/VoiceInkAppDeepLink.swift`, while shared App Group/Darwin notification state still handles stop requests and keyboard recording-state feedback.

- `DeepgramTranscriptionService.swift`: replaced by `VoiceInkCore` Deepgram request/client helpers and `VoiceInkRemoteTranscriptionService`.
- `GroqTranscriptionService.swift`: replaced by `VoiceInkCore` OpenAI-compatible request/client helpers and `VoiceInkRemoteTranscriptionService`.
- `OpenAICompatibleClient.swift`: replaced by `VoiceInkCore` chat DTOs/request builder/client.
- `LLMPostProcessor.swift`: replaced by `VoiceInkPostProcessingRequest`, `VoiceInkPostProcessingClient`, and `VoiceInkTranscriptionRunProcessor`.
- `RiffWaveUtils.swift`: replaced by `VoiceInkPCM16AudioSamples`.
- `DefaultModeManager.swift`: replaced by `AppSettings.ensureDefaultModeExists()` plus `Mode.defaultLocalWhisper()`.
- `Mode.swift`, `PromptTemplate.swift`, `Provider.swift`: replaced by `VoiceInkCore` mode, prompt-template, and provider catalog modules.
- `ModeSelectionView.swift`, `ModesView.swift`: obsolete iOS UI experiments; current in-repo iOS mode UI is `iOS/VoiceInk-ios/ModeConfigurationView.swift`.
- `Item.swift`: unused SwiftData template sample.

Do not copy these files back into `VoiceInk/iOS`. If behavior from one appears missing, port it into `VoiceInkCore` or the appropriate platform shell with a focused test.

## Deletion Gates

Before treating `../VoiceInk-iOS` as obsolete, verify current state from `VoiceInk/`:

1. `VoiceInk.xcworkspace` includes `iOS/VoiceInk-ios.xcodeproj`.
2. macOS and iOS projects both resolve `VoiceInkCore` from inside `VoiceInk/`.
3. `swift run VoiceInkCoreChecks` passes from `VoiceInkCore/`.
4. macOS Swift sources parse or build.
5. iOS app, keyboard, unit-test, and UI-test Swift sources parse or build.
6. `plutil -lint` passes for both project files and iOS plists/entitlements.
7. `xmllint --noout` passes for workspace and shared scheme XML.
8. A real Xcode toolchain is selected and both app targets build.

Current local blocker: this machine selects `/Library/Developer/CommandLineTools`, so `xcrun -find xcodebuild` cannot find `xcodebuild`. That toolchain also cannot import XCTest or Swift Testing, so `swift test` is not a real execution gate here; use `swift run VoiceInkCoreChecks` plus the static gates above until Xcode is selected.
