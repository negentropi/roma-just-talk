# Ollama writing snapshot identity

Source investigation at `d6397ed975ba62d03289d681e53e3bb103eff5a0`. No runtime reproduction, build, model inference, authentication, or production change occurred. This document designs the next proof unit. The current Custom/None gate remains separate.

## Finding and compatibility boundary

Writing Action history can describe a different Ollama model from the model sent to Ollama. This follows from the actual request owners, but the HTTP mismatch has not yet been observed.

`writingActionProviderSnapshot()` records `AIService.currentModel` and independently constructs `OllamaService()`. The execution plan passes its captured model into the Ollama closure, but that closure ignores the argument. The fresh service sends its own `selectedModel`. `performWritingAction` reports the snapshot's model in result metadata.

The two persisted model keys are case-sensitive and distinct:

| Owner | Exact key | No-key behavior |
| --- | --- | --- |
| Generic `AIService.selectedModels[.ollama]` | `OllamaSelectedModel` | `currentModel` falls back to the dynamic key, then `mistral`. |
| `OllamaService.selectedModel` | `ollamaSelectedModel` | The service uses the named legacy fallback `llama2`. |

The settings picker updates only `OllamaService.selectedModel` and the lowercase key. The menu bar calls `AIService.selectModel`, which updates both keys and the in-memory generic dictionary. Model refresh updates only the lowercase key and service. Ollama explicitly preserves a nonempty generic model even when that model is unavailable.

Therefore these source-derived outcomes need request-level reproduction:

| Initial state | Snapshot metadata | Current outgoing model |
| --- | --- | --- |
| Both model keys absent | `mistral` | `llama2` |
| Generic key `old-model`, dynamic key `new-model` | `old-model` | `new-model` |
| Both keys `chosen-model` | `chosen-model` | `chosen-model` |

The legacy fallback is an observed source contract. `legacyOllamaServiceSelectedModelFallback` names it. `ProviderCatalog.postProcessingDefaultModel` also consumes it. Existing Core tests assert caller-specific defaults. The tests alone do not establish historical intent, but actual production callers establish why replacing every `llama2` default would broaden this fix.

The current clone already freezes its endpoint and selected model after snapshot construction. Later preference edits do not mutate that independent object. Test that behavior as a preservation control. Do not report endpoint drift as an existing demonstrated defect.

## Smallest correct change

The domain value is one immutable Ollama request configuration containing the endpoint string and actual runtime model name. Keep it with `OllamaService`, which already owns request validation and generation. Reuse its real `OllamaClient.generate` transport. No new protocol, mock client, test-only alias, or provider hierarchy is needed.

Capture the endpoint through `ollamaBaseURL()` and the model through `ollamaRuntimeSelectedModel()`, once, without an intervening suspension. Use that same model for the execution plan, wire request, and result metadata. This preserves Writing Actions' current endpoint/model choice, including the legacy no-key request. It also respects the model selected by the dedicated settings picker when the generic dictionary is stale.

Give the existing service an explicit configuration or initializer path. Initialize stored properties directly. Do not create a service and assign `selectedModel` or `baseURL` afterward. Their `didSet` observers persist global preferences. The fixed writing executor must consume captured values rather than reread preferences. The ordinary mutable service remains the settings owner and delegates generation through the same implementation.

Keep ordinary Custom dictation, caller-specific defaults, model refresh, and settings persistence unchanged in this proof unit. Changing the settings picker to save both model keys is a separate decision. Forcing the snapshot to use `AIService.currentModel` would alter real model selection when the dedicated settings picker changed only the dynamic key.

Prove this identity fix before renaming the writing snapshot or extracting Clarity transport. The same driver must compile against the old and candidate writing APIs. A compatibility alias added only to make the old test compile would hide the sequencing problem.

## Request-level red and green design

Use one unchanged `@MainActor` driver against baseline `d6397ed975ba62d03289d681e53e3bb103eff5a0` and the candidate. Compile the actual `AIService`, `AIEnhancementService`, `OllamaService`, and pinned `LLMkit`. Call the existing `writingActionProviderSnapshot()` and `performWritingAction` APIs. Do not substitute the service or assert only snapshot property equality.

Run on a fresh GitHub-hosted Mac with a unique signed probe bundle identity and no app lifecycle. Reuse the narrow Local CLI probe's source/dependency hashing, in-memory `VocabularyWord` store, context-disabled defaults, and signed artifact receipt. Reuse its compilation structure, not its Local CLI semantic oracle.

Start two owned loopback HTTP listeners on ephemeral ports A and B. Record every method, path, request body, and local endpoint. Return public synthetic output `RJT ollama identity receipt.` through the real SDK response decoder. The intended endpoints are `/api/tags` and `/api/generate`, but their exact path construction and response fields must first be verified from the resolved pinned SDK source. Unexpected paths and missing requests fail the run. A bounded listener timeout is a setup failure, not evidence of the reported mismatch.

Install volatile defaults selecting Local CLI before constructing `AIService`, as in the existing probe. Switch the real instance to `.ollama` after initialization. The source proves that this provider has no credential storage name, so credential resolution does not evaluate its saved-key loader. Do not enumerate `connectedProviders`, which does query saved keys. Switching to Ollama starts asynchronous connection and model refresh work. Serve an empty model list so refresh cannot write a replacement model. Keep these requests visible in the receipt. Do not omit or race away the refresh effect.

Run each initial-state case in a fresh probe identity so no case inherits another case's preferences. Create a fresh AI service so its generic dictionary comes from that case's defaults. Keep ordinary enhancement and screen/clipboard context disabled. Capture the snapshot at endpoint A, then change volatile endpoint/model preferences to endpoint B and `later-model` before executing it. Call the real `selectModel("later-model")` menu path too, so the live generic dictionary describes that intentional new selection. Record its deliberate persistence separately. Leave the held snapshot unchanged.

The two failing cases and one control share these assertions:

1. The real request arrives at A exactly once and never at B. Its model is the initial runtime model in the table above.
2. Its prompt and system fields equal the `VoiceInkWritingActionRequest` values byte for byte after JSON decoding. It contains the expected `think` and temperature policy from the real service.
3. The result text is exactly `RJT ollama identity receipt.` and its model metadata equals the literal expected runtime model.
4. A new snapshot sends a subsequent request to B with `later-model` and matching metadata. The previous snapshot continues to identify A and its original model.
5. Capture, request execution, and retry handling do not modify the unique bundle's persistent preference domain. Compare before and after each capture and request, excluding the explicitly recorded provider/model selection writes.

Expected baseline failure is precise. Both missing-key and divergent-key cases reach A and return the synthetic text, but their result model metadata differs from the literal expected wire model. The coherent stored-model control passes on both baseline and candidate. If baseline never sends the request or fails to decode the response, fix the fixture or environment before claiming regression proof.

Add a separate retry control only when the extraction changes retry wiring. Have A hold a first request beyond the captured timeout, edit preferences during that wait, then permit the retry. Both captured bodies must retain the same endpoint, model, prompt, and timeout policy. Server-side delay must exercise the real timeout classification rather than assume an HTTP 408 means SDK timeout. This control requires SDK error-mapping inspection before implementation.

Retain exact source SHAs, unchanged driver hash, app source hashes, dependency pin receipt, source hashes after build, signature identity, exact case IDs, captured requests, result metadata, preference comparisons, and process exit statuses. Reject skipped cases and baseline compilation failures. Synthetic HTTP responses establish routing, identity, and isolation. They do not establish Ollama model quality, real server compatibility, microphone behavior, or editor delivery.

## Source owners and remaining check

| Source | Evidence |
| --- | --- |
| [AIEnhancementService.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:149) | Snapshot at 149, ignored model at 235, result metadata at 421. |
| [AIService.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInk/Services/AIEnhancement/AIService.swift:47) | Generic current model at 47, initialization at 78, provider refresh at 95, model selection at 120, runtime setter at 283. |
| [OllamaService.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInk/Services/OllamaService.swift:8) | Persisting observers at 8 and 14, defaults at 24, refresh at 54, actual model sent at 88. |
| [APIKeyManagementView.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInk/Views/AI%20Models/APIKeyManagementView.swift:154) | Dedicated Ollama picker calls the runtime setter. |
| [MenuBarView.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInk/Views/MenuBarView.swift:117) | Menu model selection calls the generic model-selection plan. |
| [AIProviderCatalog.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift:1922) | Credential loader at 1958, named defaults at 1969, no-key Ollama at 2043, default model at 2127, unavailable-model preservation at 2197. |
| [UserDefaultsPreferences.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift:48) | Case-sensitive keys at 48 and 59, generic dictionary at 3547, runtime fallback and persistence at 3625. |
| [ProviderCatalog.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift:1687) | Another production caller uses the legacy runtime fallback. |
| [AIProviderCatalogTests.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInkCore/Tests/VoiceInkCoreTests/AIProviderCatalogTests.swift:1479) | Named fallback assertions. |
| [UserDefaultsPreferencesTests.swift](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift:1578) | Caller-specific fallback assertions. |
| [Existing narrow service probe](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/scripts/run-writing-local-cli-service-probe.sh:40) | Eleven actual app sources and the pinned 26-package service dependency closure. |
| [Canonical dependency lock](/Users/atalphalnmomhappyhouse/.codex/worktrees/2ebd/VoiceInk/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:75) | `LLMkit` revision `adc2239e2a3c586fd442a8ec1d96dec8e9ae8917`. |

Pinned SDK source was unavailable in the current local checkout. Public web access rejected the pinned repository path and the unauthenticated API returned HTTP 403. The next remote proof owner must inspect its resolved checkout before choosing the stub envelope or claiming Foundation timeout and request-path behavior. No OpenAI-compatible endpoint assumptions are needed for this Ollama unit.

Model the Domain drove one immutable endpoint/model configuration. Laziness Protocol drove reuse of the existing generator and narrow source-verified probe. Prove It Works and Test Behavior, Not Implementation drove real HTTP capture with a successful response before the metadata mismatch counts as red. The parallel read-only setter investigation completed without writes. The parent owns implementation, authoritative execution, and commits.
