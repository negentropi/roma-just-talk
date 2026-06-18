import Foundation
@testable import VoiceInkCore

final class ProviderAccessRequirementTests: XCTestCase {
    func testUserAPIKeyProvidersExposeDerivedCredentialMetadata() {
        XCTAssertEqual(
            VoiceInkProviderKind.userAPIKeyProviders,
            [.groq, .openAI, .deepgram, .cerebras, .gemini, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai]
        )

        let expected: [VoiceInkProviderKind: (account: String, verificationKey: String, transport: VoiceInkAPIKeyVerificationTransport)] = [
            .groq: (VoiceInkProviderAPIKeyAccount.groq, "groqKeyVerified", .openAICompatibleModels),
            .openAI: (VoiceInkProviderAPIKeyAccount.openAI, "openAIKeyVerified", .openAICompatibleModels),
            .deepgram: (VoiceInkProviderAPIKeyAccount.deepgram, "deepgramKeyVerified", .deepgramProjects),
            .cerebras: (VoiceInkProviderAPIKeyAccount.cerebras, "cerebrasKeyVerified", .openAICompatibleModels),
            .gemini: (VoiceInkProviderAPIKeyAccount.gemini, "geminiKeyVerified", .geminiModels),
            .mistral: (VoiceInkProviderAPIKeyAccount.mistral, "mistralKeyVerified", .mistralModels),
            .elevenLabs: (VoiceInkProviderAPIKeyAccount.elevenLabs, "elevenLabsKeyVerified", .elevenLabsUser),
            .soniox: (VoiceInkProviderAPIKeyAccount.soniox, "sonioxKeyVerified", .sonioxFiles),
            .speechmatics: (VoiceInkProviderAPIKeyAccount.speechmatics, "speechmaticsKeyVerified", .speechmaticsJobs),
            .assemblyAI: (VoiceInkProviderAPIKeyAccount.assemblyAI, "assemblyAIKeyVerified", .assemblyAITranscripts),
            .xai: (VoiceInkProviderAPIKeyAccount.xAI, "xaiKeyVerified", .xaiAPIKey)
        ]

        for (provider, policy) in expected {
            guard case let .userAPIKey(account, verificationStateKey, verificationTransport) = provider.accessRequirement else {
                XCTFail("\(provider) should require a user API key")
                continue
            }

            XCTAssertTrue(provider.requiresUserAPIKey)
            XCTAssertEqual(account, policy.account)
            XCTAssertEqual(verificationStateKey, policy.verificationKey)
            XCTAssertEqual(verificationTransport, policy.transport)
            XCTAssertEqual(provider.apiKeyAccount, policy.account)
            XCTAssertEqual(provider.apiKeyVerificationStateKey, policy.verificationKey)
            XCTAssertEqual(provider.apiKeyVerificationTransport, policy.transport)
            XCTAssertTrue(provider.canVerifyAPIKey)
        }
    }

    func testProviderEnvironmentFallbacksPreserveMacOSPolicy() {
        XCTAssertEqual(
            VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "ElevenLabs"),
            "ELEVENLABS_API_KEY"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "elevenlabs"),
            "ELEVENLABS_API_KEY"
        )
        XCTAssertNil(VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "Groq"))
    }

    func testNonUserKeyProvidersKeepTheirAccessPolicy() {
        guard case .localWhisperModel = VoiceInkProviderKind.localWhisper.accessRequirement else {
            return XCTFail("Local Whisper should use local model availability")
        }
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyVerificationTransport)
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.canVerifyAPIKey)

        guard case .bundledService = VoiceInkProviderKind.voiceInk.accessRequirement else {
            return XCTFail("VoiceInk should use bundled service access")
        }
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationTransport)
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.canVerifyAPIKey)
    }

    func testRuntimeAPIKeyFollowsProviderAccessPolicy() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKey(userAPIKey: "groq-key"), "groq-key")
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKey(userAPIKey: ""), "local")
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.runtimeAPIKey(userAPIKey: "ignored"), "")
    }

    func testProviderCredentialRejectsBlankKeysWithoutNormalizingUsableKeys() {
        XCTAssertNil(VoiceInkProviderCredential.nonBlank(nil))
        XCTAssertNil(VoiceInkProviderCredential.nonBlank(""))
        XCTAssertNil(VoiceInkProviderCredential.nonBlank(" \n\t "))
        XCTAssertEqual(VoiceInkProviderCredential.nonBlank(" key-with-space "), " key-with-space ")
    }

    func testRuntimeAPIKeyIfAvailableFollowsProviderAccessPolicyAndBlankRules() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: "groq-key"), "groq-key")
        XCTAssertNil(VoiceInkProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: " \n "))
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKeyIfAvailable(userAPIKey: ""), "local")
        XCTAssertNil(VoiceInkProviderKind.voiceInk.runtimeAPIKeyIfAvailable(userAPIKey: "ignored"))
    }

    func testTranscriptionServiceKindGroupsProvidersByRequiredAdapter() {
        XCTAssertEqual(VoiceInkProviderKind.groq.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.openAI.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.deepgram.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.cerebras.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.gemini.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.xai.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.transcriptionServiceKind, .localWhisper)
    }

    func testTranscriptionEmptyTextPolicyPreservesMacOSAndLocalPolicy() {
        XCTAssertEqual(VoiceInkProviderKind.groq.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertEqual(VoiceInkProviderKind.deepgram.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertEqual(VoiceInkProviderKind.gemini.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertTrue(VoiceInkProviderKind.groq.transcriptionEmptyTextPolicy.accepts(" \n\t "))
        XCTAssertFalse(VoiceInkProviderKind.groq.transcriptionEmptyTextPolicy.accepts(""))

        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertFalse(VoiceInkProviderKind.soniox.transcriptionEmptyTextPolicy.accepts(" \n\t "))

        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionEmptyTextPolicy, .allow)
        XCTAssertTrue(VoiceInkProviderKind.mistral.transcriptionEmptyTextPolicy.accepts(""))
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.transcriptionEmptyTextPolicy, .allow)
        XCTAssertTrue(VoiceInkProviderKind.localWhisper.transcriptionEmptyTextPolicy.accepts(""))
    }

    func testRemoteTranscriptionProvidersUseSharedTransportAndEndpoints() {
        XCTAssertEqual(VoiceInkProviderKind.gemini.transcriptionTransport, .geminiGenerateContent)
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.transcriptionAPIBaseURL.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta"
        )
        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionTransport, .mistral)
        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionAPIBaseURL.absoluteString, "https://api.mistral.ai")
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.transcriptionTransport, .elevenLabs)
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.transcriptionAPIBaseURL.absoluteString, "https://api.elevenlabs.io")
        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionTransport, .soniox)
        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionAPIBaseURL.absoluteString, "https://api.soniox.com/v1")
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionTransport, .speechmatics)
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionAPIBaseURL.absoluteString, "https://asr.api.speechmatics.com/v2")
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionTransport, .assemblyAI)
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionAPIBaseURL.absoluteString, "https://api.assemblyai.com")
        XCTAssertEqual(VoiceInkProviderKind.xai.transcriptionTransport, .xai)
        XCTAssertEqual(VoiceInkProviderKind.xai.transcriptionAPIBaseURL.absoluteString, "https://api.x.ai")
    }

    func testGeminiUsesNativeTranscriptionEndpointButOpenAICompatiblePostProcessingEndpoint() {
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.postProcessingChatCompletionsURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai/v1/chat/completions"
        )
    }

    func testProviderReadinessFollowsProviderAccessPolicy() {
        XCTAssertTrue(VoiceInkProviderKind.groq.isReady(
            userAPIKey: "groq-key",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: false
        ))
        XCTAssertFalse(VoiceInkProviderKind.groq.isReady(
            userAPIKey: "",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.groq.isReady(
            userAPIKey: " \n ",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.groq.isReady(
            userAPIKey: "groq-key",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))

        XCTAssertTrue(VoiceInkProviderKind.localWhisper.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.isReady(
            userAPIKey: "",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: false
        ))

        XCTAssertTrue(VoiceInkProviderKind.voiceInk.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: false
        ))
    }

    func testAvailableProvidersFiltersByModelUseAndReadiness() {
        let readyProviders: Set<VoiceInkProviderKind> = [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper, .voiceInk]

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { readyProviders.contains($0) },
            [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper]
        )

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { readyProviders.contains($0) },
            [.groq]
        )
    }

    func testBundledVoiceInkProviderIsNotSelectableUntilAnAdapterExists() {
        XCTAssertTrue(VoiceInkProviderKind.voiceInk.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: false
        ))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.supportsModelUse(.transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.supportsModelUse(.postProcessing))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .postProcessing))
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { $0 == .voiceInk },
            []
        )
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { $0 == .voiceInk },
            []
        )
    }

    func testProviderSelectabilityKeepsReadinessAndModelSupportSeparate() {
        XCTAssertTrue(VoiceInkProviderKind.groq.isSelectable(for: .transcription))
        XCTAssertTrue(VoiceInkProviderKind.groq.isSelectable(for: .postProcessing))
        XCTAssertTrue(VoiceInkProviderKind.localWhisper.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.isSelectable(for: .postProcessing))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .postProcessing))
    }

    func testAvailableProvidersReturnsEmptyWhenNoProviderIsReady() {
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { _ in false },
            []
        )
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { _ in false },
            []
        )
    }
}
