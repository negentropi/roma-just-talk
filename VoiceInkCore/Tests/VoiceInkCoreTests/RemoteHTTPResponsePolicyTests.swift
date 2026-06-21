import Foundation
@testable import VoiceInkCore

final class RemoteHTTPResponsePolicyTests: XCTestCase {
    func testValidateSuccessAcceptsHTTP2xxResponses() throws {
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
            response: response(statusCode: 204),
            data: Data(),
            errorDomain: "ProviderAPI"
        )
    }

    func testValidateSuccessRejectsNonHTTPResponses() throws {
        let response = URLResponse(
            url: try XCTUnwrap(URL(string: "https://api.example.test")),
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        do {
            try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
                response: response,
                data: Data(),
                errorDomain: "ProviderAPI"
            )
            XCTFail("Expected non-HTTP response to throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        } catch {
            XCTFail("Expected URLError.badServerResponse, got \(error)")
        }
    }

    func testValidateSuccessThrowsProviderNSErrorForNon2xxBody() throws {
        do {
            try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
                response: response(statusCode: 429),
                data: Data("rate limited".utf8),
                errorDomain: "ProviderAPI"
            )
            XCTFail("Expected non-2xx response to throw")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "ProviderAPI")
            XCTAssertEqual(nsError.code, 429)
            XCTAssertEqual(nsError.userInfo[NSLocalizedDescriptionKey] as? String, "rate limited")
        }
    }

    func testAPIErrorUsesEmptyMessageForNonUTF8Body() {
        let error = VoiceInkRemoteHTTPResponsePolicy.apiError(
            statusCode: 500,
            data: Data([0xFF]),
            errorDomain: "ProviderAPI"
        )

        XCTAssertEqual(error.domain, "ProviderAPI")
        XCTAssertEqual(error.code, 500)
        XCTAssertEqual(error.userInfo[NSLocalizedDescriptionKey] as? String, "")
    }

    func testRetryableStatusCodeMatchesSharedRemoteRetryPolicy() throws {
        XCTAssertEqual(
            VoiceInkRemoteHTTPResponsePolicy.retryableStatusCode(in: response(statusCode: 429)),
            429
        )
        XCTAssertEqual(
            VoiceInkRemoteHTTPResponsePolicy.retryableStatusCode(in: response(statusCode: 504)),
            504
        )
        XCTAssertNil(VoiceInkRemoteHTTPResponsePolicy.retryableStatusCode(in: response(statusCode: 400)))
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
