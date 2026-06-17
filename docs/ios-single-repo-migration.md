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
- post-processing request construction and output filtering
- provider catalog, provider endpoints, API key account names, and provider readiness policy
- provider API-key verification dispatch
- API-key environment-reference resolution
- transcription and AI model catalogs
- remote transcription provider dispatch for iOS retry transcription
- mode runtime configuration and selected-mode repair
- mode provider-selection repair and draft saveability rules
- shared UserDefaults key names, including cleanup preferences, plus iOS mode persistence helpers
- transcript status and presentation helpers
- local transcription/model/missing-audio error vocabulary shared by macOS local Whisper and iOS local retry transcription
- raw transcription output filtering for hallucination tags/brackets, optional filler words, and default filler-word vocabulary
- transcription cleanup preferences and punctuation/lowercase cleanup policy
- stored audio-file path resolution, existing-file lookup, recordings directory, and file URL construction
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

Current iOS consumers of shared remote transport:

- `iOS/VoiceInk-ios/TranscriptionServiceFactory.swift` creates `VoiceInkRemoteTranscriptionService` for every remote `VoiceInkProviderKind`.
- `VoiceInkRemoteTranscriptionService` dispatches Groq/OpenAI/Cerebras, Deepgram, Gemini, Mistral, ElevenLabs, Soniox, Speechmatics, AssemblyAI, and xAI through shared core clients.
- `iOS/VoiceInk-ios/TranscriptionRetryService.swift` routes iOS transcription through `VoiceInkTranscriptionRunProcessor`, including shared output filtering and cleanup preferences from `AppSettings`.
- `iOS/VoiceInk-ios/ProviderAPIKeyView.swift` verifies provider keys through `VoiceInkProviderAPIKeyVerifier`.
- `iOS/VoiceInk-ios/WhisperTranscriptionService.swift` throws `VoiceInkEngineError` from `VoiceInkCore` instead of owning a separate iOS-only local Whisper error enum.
- Cartesia remains absent from iOS transcription provider selection until an iOS streaming adapter exists; it is not a batch provider.
- The bundled `VoiceInk` provider case remains decodable, but is hidden from iOS transcription and post-processing selection until a real no-key/bundled-service adapter exists. The sibling clone marked it always available while returning an empty API key, so porting that path would preserve a broken no-key mode.

Platform shells still own UI, OS permissions, audio capture, paste/keyboard behavior, keychain adapters, local model download storage, SwiftData models, and macOS-only orchestration. iOS-only shell code shared between the app and keyboard extension lives in `iOS/Shared/`, not `VoiceInkCore`; this currently includes App Group coordination and the keyboard-to-app deep-link contract.

## Sibling Clone Status

The remaining Swift files present in `../VoiceInk-iOS` but not in `VoiceInk/iOS` are old clone-side sources:

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
