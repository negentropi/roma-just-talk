import Foundation
@testable import VoiceInkCore

final class APIKeyVerificationPolicyTests: XCTestCase {
    func testBlankAPIKeyResultPreservesSharedFailureCopy() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.blankAPIKeyResultIfNeeded(" \n\t "),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
        XCTAssertNil(VoiceInkAPIKeyVerificationPolicy.blankAPIKeyResultIfNeeded("key"))
    }

    func testVerificationResultRejectsMissingHTTPResponse() throws {
        let response = URLResponse(
            url: try XCTUnwrap(URL(string: "https://api.example.test")),
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.verificationResult(data: Data(), response: response),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "No HTTP response received."
            )
        )
    }

    func testVerificationResultAcceptsHTTP2xxResponses() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.verificationResult(
                data: Data("ok".utf8),
                response: response(statusCode: 204)
            ),
            VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        )
    }

    func testVerificationResultReturnsHTTPBodyForFailure() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.verificationResult(
                data: Data("invalid key".utf8),
                response: response(statusCode: 401)
            ),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "invalid key"
            )
        )
    }

    func testVerificationResultFallsBackToHTTPStatusForNonUTF8FailureBody() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.verificationResult(
                data: Data([0xFF]),
                response: response(statusCode: 500)
            ),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "HTTP 500"
            )
        )
    }

    func testFailureResultUsesLocalizedDescription() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.failureResult(StubVerificationError()),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "network offline"
            )
        )
    }

    private func response(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private struct StubVerificationError: LocalizedError {
    var errorDescription: String? {
        "network offline"
    }
}
