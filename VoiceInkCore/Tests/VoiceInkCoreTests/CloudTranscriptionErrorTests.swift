import Foundation
@testable import VoiceInkCore

final class CloudTranscriptionErrorTests: XCTestCase {
    func testErrorDescriptionsPreserveMacOSCloudTranscriptionCopy() {
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.unsupportedProvider.errorDescription,
            "The model provider is not supported by this service."
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.missingAPIKey.errorDescription,
            "API key for this service is missing. Please configure it in the settings."
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.audioFileNotFound.errorDescription,
            "The audio file to transcribe could not be found."
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.apiRequestFailed(statusCode: 429, message: "rate limited").errorDescription,
            "The API request failed with status code 429: rate limited"
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.networkError(StubNetworkError()).errorDescription,
            "A network error occurred: network offline"
        )
    }

    func testNoTranscriptionReturnedUsesSharedRunErrorDescription() {
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.noTranscriptionReturned.errorDescription,
            VoiceInkTranscriptionRunError.noTranscriptionReturned.errorDescription
        )
    }

    func testAPIRequestFailureMapsMatchingHTTPNSError() {
        let error = NSError(
            domain: "GroqAPI",
            code: 429,
            userInfo: [NSLocalizedDescriptionKey: "rate limited"]
        )

        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: error,
                matchingErrorDomain: "GroqAPI"
            )?.errorDescription,
            "The API request failed with status code 429: rate limited"
        )
    }

    func testAPIRequestFailureFallsBackToLocalizedDescription() {
        let error = NSError(domain: "GroqAPI", code: 500)

        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: error,
                matchingErrorDomain: "GroqAPI"
            )?.errorDescription,
            "The API request failed with status code 500: \(error.localizedDescription)"
        )
    }

    func testAPIRequestFailureRejectsWrongDomainMissingDomainAndNonHTTPStatus() {
        XCTAssertNil(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: NSError(domain: "Other", code: 429),
                matchingErrorDomain: "GroqAPI"
            )
        )
        XCTAssertNil(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: NSError(domain: "GroqAPI", code: 429),
                matchingErrorDomain: nil
            )
        )
        XCTAssertNil(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: NSError(domain: "GroqAPI", code: 99),
                matchingErrorDomain: "GroqAPI"
            )
        )
    }

    func testLegacyCloudTranscriptionErrorAliasResolvesToSharedCoreError() {
        let error: CloudTranscriptionError = .missingAPIKey

        XCTAssertEqual(
            error.errorDescription,
            VoiceInkCloudTranscriptionError.missingAPIKey.errorDescription
        )
    }
}

private struct StubNetworkError: LocalizedError {
    var errorDescription: String? {
        "network offline"
    }
}
