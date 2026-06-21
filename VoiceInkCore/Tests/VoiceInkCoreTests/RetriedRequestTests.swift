import Foundation
@testable import VoiceInkCore

final class RetriedRequestTests: XCTestCase {
    func testValidatedDataReturnsBodyAfterHTTP2xx() async throws {
        RetriedRequestCapturingURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("ok".utf8))
        }

        URLProtocol.registerClass(RetriedRequestCapturingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RetriedRequestCapturingURLProtocol.self)
            RetriedRequestCapturingURLProtocol.requestHandler = nil
        }

        let data = try await VoiceInkRetriedRequest.validatedData(
            for: URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.test/status"))),
            timeout: nil,
            maxRetries: 0,
            errorDomain: "ProviderAPI"
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    func testValidatedDataThrowsProviderNSErrorForNon2xx() async throws {
        RetriedRequestCapturingURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("rate limited".utf8))
        }

        URLProtocol.registerClass(RetriedRequestCapturingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RetriedRequestCapturingURLProtocol.self)
            RetriedRequestCapturingURLProtocol.requestHandler = nil
        }

        do {
            _ = try await VoiceInkRetriedRequest.validatedData(
                for: URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.test/status"))),
                timeout: nil,
                maxRetries: 0,
                errorDomain: "ProviderAPI"
            )
            XCTFail("Expected validatedData to reject non-2xx response")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "ProviderAPI")
            XCTAssertEqual(nsError.code, 429)
            XCTAssertEqual(nsError.userInfo[NSLocalizedDescriptionKey] as? String, "rate limited")
        }
    }

}

private final class RetriedRequestCapturingURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
