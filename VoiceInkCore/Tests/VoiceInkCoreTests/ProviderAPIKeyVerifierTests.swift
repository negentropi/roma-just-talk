import Foundation
@testable import VoiceInkCore

final class ProviderAPIKeyVerifierTests: XCTestCase {
    func testVerifierRejectsBlankKeysForEveryUserAPIKeyProviderWithoutNetwork() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()

        for provider in VoiceInkProviderKind.userAPIKeyProviders {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)

            XCTAssertEqual(
                result,
                VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "API key is missing or empty."
                ),
                "\(provider.displayName) should route through its verification transport"
            )
        }
    }

    func testStoredKeyVerifierRejectsMissingStoredOrEnvironmentKeyWithoutNetwork() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()

        let result = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_GROQ_API_KEY",
            for: .groq,
            environment: [:]
        )

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
        let isValid = await verifier.verifyStoredAPIKey(nil, for: .groq, environment: [:])
        XCTAssertFalse(isValid)
    }

    func testVerifierRejectsProvidersWithoutVerificationTransport() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()

        let localResult = await verifier.verifyAPIKeyDetailed("key", for: .localWhisper)
        XCTAssertEqual(
            localResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )

        let bundledResult = await verifier.verifyAPIKeyDetailed("key", for: .voiceInk)
        XCTAssertEqual(
            bundledResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "VoiceInk does not support API key verification."
            )
        )
    }

    func testStoredKeyVerifierRejectsProvidersWithoutVerificationTransport() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()

        let result = await verifier.verifyStoredAPIKeyDetailed("key", for: .localWhisper)

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )
    }

    func testVerifierRoutesTranscriptionModelProvidersWithoutNetworkForBlankKeys() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()

        for provider in VoiceInkTranscriptionModelProvider.allCases where provider != .local {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)

            XCTAssertEqual(
                result,
                VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "API key is missing or empty."
                ),
                "\(provider.rawValue) should route through shared model-provider verification"
            )
        }
    }

    func testVerifierRejectsLocalTranscriptionModelProviderWithoutVerificationTransport() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()

        let result = await verifier.verifyAPIKeyDetailed("key", for: VoiceInkTranscriptionModelProvider.local)

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )
    }
}
