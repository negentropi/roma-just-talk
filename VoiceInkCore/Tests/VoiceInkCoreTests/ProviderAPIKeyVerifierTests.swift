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
}
