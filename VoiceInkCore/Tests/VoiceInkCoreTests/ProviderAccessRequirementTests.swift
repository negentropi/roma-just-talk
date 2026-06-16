#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class ProviderAccessRequirementTests: XCTestCase {
    func testUserAPIKeyProvidersExposeDerivedCredentialMetadata() {
        XCTAssertEqual(
            VoiceInkProviderKind.userAPIKeyProviders,
            [.groq, .openAI, .deepgram, .cerebras, .gemini]
        )

        let expected: [VoiceInkProviderKind: (account: String, verificationKey: String, transport: VoiceInkAPIKeyVerificationTransport)] = [
            .groq: (VoiceInkProviderAPIKeyAccount.groq, "groqKeyVerified", .openAICompatibleModels),
            .openAI: (VoiceInkProviderAPIKeyAccount.openAI, "openAIKeyVerified", .openAICompatibleModels),
            .deepgram: (VoiceInkProviderAPIKeyAccount.deepgram, "deepgramKeyVerified", .deepgramProjects),
            .cerebras: (VoiceInkProviderAPIKeyAccount.cerebras, "cerebrasKeyVerified", .openAICompatibleModels),
            .gemini: (VoiceInkProviderAPIKeyAccount.gemini, "geminiKeyVerified", .openAICompatibleModels)
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
        }
    }

    func testNonUserKeyProvidersKeepTheirAccessPolicy() {
        guard case .localWhisperModel = VoiceInkProviderKind.localWhisper.accessRequirement else {
            return XCTFail("Local Whisper should use local model availability")
        }
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyVerificationTransport)

        guard case .bundledService = VoiceInkProviderKind.voiceInk.accessRequirement else {
            return XCTFail("VoiceInk should use bundled service access")
        }
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationTransport)
    }

    func testRuntimeAPIKeyFollowsProviderAccessPolicy() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKey(userAPIKey: "groq-key"), "groq-key")
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKey(userAPIKey: ""), "local")
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.runtimeAPIKey(userAPIKey: "ignored"), "")
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
        let readyProviders: Set<VoiceInkProviderKind> = [.groq, .deepgram, .localWhisper, .voiceInk]

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { readyProviders.contains($0) },
            [.groq, .deepgram, .localWhisper, .voiceInk]
        )

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { readyProviders.contains($0) },
            [.groq, .voiceInk]
        )
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
#endif
