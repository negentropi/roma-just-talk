import Foundation
import VoiceInkCore

final class ProviderAPIKeyVerifierPublicAPITests: XCTestCase {
    func testProviderAPIKeyVerifierPublicRoutesRejectMissingKeysWithoutNetwork() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()
        let missingAPIKeyResult = VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: "API key is missing or empty."
        )

        XCTAssertEqual(
            VoiceInkAPIKeyVerificationResult(legacyResult: (true, nil)),
            VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        )
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationResult(legacyResult: (false, "invalid key")),
            VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "invalid key")
        )

        for provider in VoiceInkProviderKind.userAPIKeyProviders {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)
            XCTAssertEqual(result, missingAPIKeyResult)
        }

        let missingStoredProviderKeyIsValid = await verifier.verifyStoredAPIKey(nil, for: .groq, environment: [:])
        XCTAssertFalse(missingStoredProviderKeyIsValid)
        let missingStoredProviderKeyResult = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_GROQ_API_KEY",
            for: VoiceInkProviderKind.groq,
            environment: [:]
        )
        XCTAssertEqual(missingStoredProviderKeyResult, missingAPIKeyResult)
        let unsupportedProviderResult = await verifier.verifyAPIKeyDetailed("key", for: .localWhisper)
        XCTAssertEqual(
            unsupportedProviderResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )

        for provider in VoiceInkTranscriptionModelProvider.allCases where provider != .local {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)
            XCTAssertEqual(result, missingAPIKeyResult)
        }
        let missingStoredTranscriptionProviderKeyResult = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_CARTESIA_API_KEY",
            for: VoiceInkTranscriptionModelProvider.cartesia,
            environment: [:]
        )
        XCTAssertEqual(missingStoredTranscriptionProviderKeyResult, missingAPIKeyResult)
        let unsupportedTranscriptionProviderResult = await verifier.verifyAPIKeyDetailed(
            "key",
            for: VoiceInkTranscriptionModelProvider.local
        )
        XCTAssertEqual(
            unsupportedTranscriptionProviderResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )

        for provider in VoiceInkMacOSTranscriptionModelProvider.allCases where provider.coreTranscriptionModelProvider != nil {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)
            XCTAssertEqual(result, missingAPIKeyResult)
        }
        let missingStoredMacOSProviderKeyResult = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_GROQ_API_KEY",
            for: VoiceInkMacOSTranscriptionModelProvider.groq,
            environment: [:]
        )
        XCTAssertEqual(missingStoredMacOSProviderKeyResult, missingAPIKeyResult)
        let unsupportedMacOSProviderResult = await verifier.verifyStoredAPIKeyDetailed(
            "key",
            for: VoiceInkMacOSTranscriptionModelProvider.whisper
        )
        XCTAssertEqual(
            unsupportedMacOSProviderResult,
            VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "Unsupported provider")
        )
    }

    func testCartesiaRequestClientAndProviderVerifierExposePublicAPI() async {
        let request = VoiceInkCartesiaRequestBuilder.makeVoicesRequest(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: "cartesia-key",
            timeout: 10
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.cartesia.ai/voices?limit=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "cartesia-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cartesia-Version"), "2026-03-01")
        XCTAssertEqual(request.timeoutInterval, 10)

        let client = VoiceInkCartesiaClient()
        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: "API key is missing or empty."
        )
        let detailedBlankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertEqual(detailedBlankAPIKeyResult, blankAPIKeyResult)
        let verifierBlankAPIKeyResult = await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(
            " \n\t ",
            for: VoiceInkTranscriptionModelProvider.cartesia
        )
        XCTAssertEqual(verifierBlankAPIKeyResult, blankAPIKeyResult)
    }
}
