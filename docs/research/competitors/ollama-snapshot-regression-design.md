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

Start two owned loopback HTTP listeners on ephemeral ports A and B. Use origin-only base URLs. Record every method, path, request body, and local endpoint. Return public synthetic output `RJT ollama identity receipt.` through the real SDK response decoder. Serve the base URL, `/api/tags`, and `/api/generate` using the pinned SDK contract below. Unexpected paths and missing requests fail the run. A bounded listener timeout is a setup failure, not evidence of the reported mismatch.

Install volatile defaults selecting Local CLI before constructing `AIService`, as in the existing probe. Switch the real instance to `.ollama` after initialization. The source proves that this provider has no credential storage name, so credential resolution does not evaluate its saved-key loader. Do not enumerate `connectedProviders`, which does query saved keys. Switching to Ollama starts asynchronous connection and model refresh work. Serve an empty model list so refresh cannot write a replacement model. Keep these requests visible in the receipt. Do not omit or race away the refresh effect.

Run each initial-state case in a fresh probe identity so no case inherits another case's preferences. Create a fresh AI service so its generic dictionary comes from that case's defaults. Keep ordinary enhancement and screen/clipboard context disabled. Capture the snapshot at endpoint A, then change volatile endpoint/model preferences to endpoint B and `later-model` before executing it. Call the real `selectModel("later-model")` menu path too, so the live generic dictionary describes that intentional new selection. Record its deliberate persistence separately. Leave the held snapshot unchanged.

The two failing cases and one control share these assertions:

1. The real request arrives at A exactly once and never at B. Its model is the initial runtime model in the table above.
2. Its prompt and system fields equal the `VoiceInkWritingActionRequest` values byte for byte after JSON decoding. It contains the expected `think` and temperature policy from the real service.
3. The result text is exactly `RJT ollama identity receipt.` and its model metadata equals the literal expected runtime model.
4. A new snapshot sends a subsequent request to B with `later-model` and matching metadata. The previous snapshot continues to identify A and its original model.
5. Capture, request execution, and retry handling do not modify the unique bundle's persistent preference domain. Compare before and after each capture and request, excluding the explicitly recorded provider/model selection writes.

Expected baseline failure is precise. Both missing-key and divergent-key cases reach A and return the synthetic text, but their result model metadata differs from the literal expected wire model. The coherent stored-model control passes on both baseline and candidate. If baseline never sends the request or fails to decode the response, fix the fixture or environment before claiming regression proof.

Add a separate retry control only when the extraction changes retry wiring. Have A hold a first request beyond the captured timeout, edit preferences during that wait, then permit the retry. Both captured bodies must retain the same endpoint, model, prompt, and timeout policy. Server-side delay must exercise the real timeout classification. HTTP 408 cannot substitute for that delay, as the pinned mapping below confirms.

Retain exact source SHAs, unchanged driver hash, app source hashes, dependency pin receipt, source hashes after build, signature identity, exact case IDs, captured requests, result metadata, preference comparisons, and process exit statuses. Reject skipped cases and baseline compilation failures. Synthetic HTTP responses establish routing, identity, and isolation. They do not establish Ollama model quality, real server compatibility, microphone behavior, or editor delivery.

## Source owners and remaining check

| Source | Evidence |
| --- | --- |
| [AIEnhancementService.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Services/AIEnhancement/AIEnhancementService.swift#L149) | Snapshot at 149, ignored model at 235, result metadata at 421. |
| [AIService.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Services/AIEnhancement/AIService.swift#L47) | Generic current model at 47, initialization at 78, provider refresh at 95, model selection at 120, runtime setter at 283. |
| [OllamaService.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Services/OllamaService.swift#L8) | Persisting observers at 8 and 14, defaults at 24, refresh at 54, actual model sent at 88. |
| [APIKeyManagementView.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Views/AI%20Models/APIKeyManagementView.swift#L154) | Dedicated Ollama picker calls the runtime setter. |
| [MenuBarView.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Views/MenuBarView.swift#L117) | Menu model selection calls the generic model-selection plan. |
| [AIProviderCatalog.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift#L1922) | Credential loader at 1958, named defaults at 1969, no-key Ollama at 2043, default model at 2127, unavailable-model preservation at 2197. |
| [UserDefaultsPreferences.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift#L48) | Case-sensitive keys at 48 and 59, generic dictionary at 3547, runtime fallback and persistence at 3625. |
| [ProviderCatalog.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift#L1687) | Another production caller uses the legacy runtime fallback. |
| [AIProviderCatalogTests.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInkCore/Tests/VoiceInkCoreTests/AIProviderCatalogTests.swift#L1479) | Named fallback assertions. |
| [UserDefaultsPreferencesTests.swift](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift#L1578) | Caller-specific fallback assertions. |
| [Existing narrow service probe](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/scripts/run-writing-local-cli-service-probe.sh#L40) | Eleven actual app sources and the pinned 26-package service dependency closure. |
| [Canonical dependency lock](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved#L75) | `LLMkit` revision `adc2239e2a3c586fd442a8ec1d96dec8e9ae8917`. |

## Pinned SDK request and timeout contract

Authenticated `gh api` reads resolved the exact `LLMkit` revision `adc2239e2a3c586fd442a8ec1d96dec8e9ae8917`. The initial unauthenticated retrieval failure no longer blocks source inspection. The commit tree maps the inspected files to these immutable blobs:

| File | Git blob |
| --- | --- |
| `Sources/LLMkit/LLM/OllamaClient.swift` | `341c5d0d38edd79733a2da47f412e3ab540c82fb` |
| `Sources/LLMkit/HTTPClient.swift` | `81db783f7ab47c2b2174a4f2367c1e0f5ac1509d` |
| `Sources/LLMkit/HTTPHelpers.swift` | `7b2a095d066260e194a6b6c1026807e601aaae10` |
| `Sources/LLMkit/LLMKitError.swift` | `5db3d14e020e3bc3daba752d289aeae530f7b56e` |

The SDK constructs these requests. A root path here assumes the fixture's origin-only base URL.

| Operation | Request construction | Timeout and valid fixture response |
| --- | --- | --- |
| Connection check | `URLRequest(url: baseURL)` with no method override, so GET to `/`. Uses `URLSession.shared`. | Default request timeout is five seconds. Any HTTP 2xx succeeds. The body is unused. Errors and non-2xx return `false`. |
| Model refresh | GET to `baseURL.appendingPathComponent("api/tags")`. Uses `URLSession.shared`. | Default request timeout is ten seconds. Return HTTP 200 with `{"models":[]}`. |
| Generation | POST to `baseURL.appendingPathComponent("api/generate")`, with `Content-Type: application/json`. Uses `performRequest`. | RJT supplies the captured enhancement timeout. Return HTTP 200 with `{"response":"RJT ollama identity receipt."}`. |

Connection checks do not call `/api/tags`. The model-list response requires a `models` array. An empty array avoids all model-detail fields and prevents RJT's refresh policy from selecting a replacement. A nonempty model entry requires `name`, `modified_at`, `size`, `digest`, and `details`. Its required detail fields are `format`, `family`, `parameter_size`, and `quantization_level`. Only `families` is optional. Generation requires one string field, `response`. The decoder does not require model, completion, or timing fields. See the pinned [Ollama client and response models](https://github.com/Beingpax/LLMkit/blob/adc2239e2a3c586fd442a8ec1d96dec8e9ae8917/Sources/LLMkit/LLM/OllamaClient.swift#L20).

The current RJT caller produces this exact JSON field set:

| Field | Value |
| --- | --- |
| `model` | Captured runtime model string. |
| `prompt` | Writing request's user message. |
| `system` | Writing request's system message. |
| `temperature` | Number `0.3`, at the top level. |
| `stream` | Boolean `false`. |
| `think` | Boolean `false`. |

The SDK includes `think` only when its optional argument is non-nil. RJT explicitly passes `false`. The SDK uses `JSONSerialization`, so assertions compare decoded fields and message bytes rather than object-key order. It does not add an authorization header or call the OpenAI-compatible chat endpoint. Preserve the current top-level temperature field in this identity unit. The synthetic response does not prove that a real Ollama version honors the setting. See [generation request construction](https://github.com/Beingpax/LLMkit/blob/adc2239e2a3c586fd442a8ec1d96dec8e9ae8917/Sources/LLMkit/LLM/OllamaClient.swift#L62) and the actual [RJT caller](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Services/OllamaService.swift#L86).

Generation sets `URLRequest.timeoutInterval` to the supplied timeout. Each SDK attempt creates a fresh ephemeral session. Both its request and resource timeout intervals use that same value. The configuration ignores local cache data and has no URL cache. This differs from the two discovery operations, which use the shared session. These are source settings, not measured timeout precision. See [request execution](https://github.com/Beingpax/LLMkit/blob/adc2239e2a3c586fd442a8ec1d96dec8e9ae8917/Sources/LLMkit/HTTPClient.swift#L16) and [session configuration](https://github.com/Beingpax/LLMkit/blob/adc2239e2a3c586fd442a8ec1d96dec8e9ae8917/Sources/LLMkit/HTTPClient.swift#L106).

The SDK can issue three attempts by default, with one-second and two-second delays before retries. Retryable HTTP statuses are exactly `429`, `500`, `502`, `503`, and `504`. Other thrown errors also retry, except an existing `LLMKitError` is rethrown immediately. An `NSError` with `NSURLErrorDomain` and `NSURLErrorTimedOut` becomes `LLMKitError.timeout` immediately, without SDK retry. A clean HTTP 200 generation fixture therefore needs exactly one generation request per call. Discovery requests are separate. See the pinned [retry and timeout branches](https://github.com/Beingpax/LLMkit/blob/adc2239e2a3c586fd442a8ec1d96dec8e9ae8917/Sources/LLMkit/HTTPClient.swift#L25).

`validateHTTPResponse` accepts only HTTP 2xx. A non-HTTP response becomes `.networkError`. Other statuses become `.httpError` with the status and UTF-8 body. HTTP 408 is neither SDK-retryable nor a timeout error. RJT converts that HTTP failure to its Ollama invalid-response error, then a generic enhancement error. By contrast, a real SDK timeout becomes `VoiceInkAIEnhancementError.timeout` and uses the existing enhancement retry-on-timeout policy. `decodeJSON` uses `JSONDecoder().decode` and wraps decoding failures as `.decodingError`. See [HTTP and JSON validation](https://github.com/Beingpax/LLMkit/blob/adc2239e2a3c586fd442a8ec1d96dec8e9ae8917/Sources/LLMkit/HTTPHelpers.swift#L4), [RJT's SDK error adapter](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInk/Services/OllamaService.swift#L103), and [enhancement error and retry policy](https://github.com/negentropi/roma-just-talk/blob/d6397ed975ba62d03289d681e53e3bb103eff5a0/VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift#L135).

There is no explicit cancellation branch or cancellation handler in `performRequest`. Backoff sleep throws outside its request catch block. This source does not establish whether canceled server work stops. The next executable proof must observe the actual request and error behavior. No runtime, real Ollama server, Foundation timing, or cancellation claim is added by these source reads.

Model the Domain drove one immutable endpoint/model configuration. Laziness Protocol drove reuse of the existing generator and narrow source-verified probe. Prove It Works and Test Behavior, Not Implementation drove real HTTP capture with a successful response before the metadata mismatch counts as red. The parallel read-only setter investigation completed without writes. The parent owns implementation, authoritative execution, and commits.
