import Foundation
@testable import VoiceInkCore

final class RemoteTransportTests: XCTestCase {
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

    func testPollReturnsFinishedResultWithoutSleeping() async throws {
        var operationCount = 0
        var sleepCount = 0

        let result = try await VoiceInkRemotePollingPolicy.poll(
            maxWaitSeconds: 10,
            sleep: { _ in sleepCount += 1 }
        ) {
            operationCount += 1
            return .finished("done")
        }

        XCTAssertEqual(result, "done")
        XCTAssertEqual(operationCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    func testPollSleepsAndRetriesUntilFinished() async throws {
        var operationCount = 0
        var sleptIntervals: [UInt64] = []

        let result = try await VoiceInkRemotePollingPolicy.poll(
            maxWaitSeconds: 10,
            sleep: { interval in sleptIntervals.append(interval) }
        ) {
            operationCount += 1
            return operationCount == 1 ? .keepPolling : .finished("done")
        }

        XCTAssertEqual(result, "done")
        XCTAssertEqual(operationCount, 2)
        XCTAssertEqual(sleptIntervals, [VoiceInkRemotePollingPolicy.defaultIntervalNanoseconds])
    }

    func testPollTimesOutAfterPendingDecision() async throws {
        var operationCount = 0
        var now = Date(timeIntervalSince1970: 0)

        do {
            let _: String = try await VoiceInkRemotePollingPolicy.poll(
                maxWaitSeconds: 1,
                now: { now },
                sleep: { _ in
                    now = Date(timeIntervalSince1970: now.timeIntervalSince1970 + 2)
                }
            ) {
                operationCount += 1
                return .keepPolling
            }
            XCTFail("Expected polling timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Expected URLError.timedOut, got \(error)")
        }

        XCTAssertEqual(operationCount, 2)
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
