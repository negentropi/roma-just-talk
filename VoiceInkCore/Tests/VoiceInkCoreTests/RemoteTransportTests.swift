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

    func testAPIKeyVerificationPolicyRejectsBlankKeys() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.blankAPIKeyResultIfNeeded(" \n\t "),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
        XCTAssertNil(VoiceInkAPIKeyVerificationPolicy.blankAPIKeyResultIfNeeded("key"))
    }

    func testAPIKeyVerificationPolicyRejectsMissingHTTPResponse() throws {
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

    func testAPIKeyVerificationPolicyAcceptsHTTP2xxResponses() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.verificationResult(
                data: Data("ok".utf8),
                response: response(statusCode: 204)
            ),
            VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        )
    }

    func testAPIKeyVerificationPolicyReturnsHTTPBodyOrStatusForFailures() {
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

    func testAPIKeyVerificationPolicyFailureResultUsesLocalizedDescription() {
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationPolicy.failureResult(StubVerificationError()),
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "network offline"
            )
        )
    }

    func testNoTranscriptionReturnedUsesSharedRunErrorDescription() {
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.noTranscriptionReturned.errorDescription,
            VoiceInkTranscriptionRunError.noTranscriptionReturned.errorDescription
        )
    }

    func testCloudTranscriptionAudioFileLoadsBytesAndFileName() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.RemoteTransportTests.\(UUID().uuidString).wav")
        try Data("WAVDATA".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioFile = try VoiceInkCloudTranscriptionAudioFile.load(from: audioURL)

        XCTAssertEqual(audioFile.data, Data("WAVDATA".utf8))
        XCTAssertEqual(audioFile.fileName, audioURL.lastPathComponent)
    }

    func testCloudTranscriptionAudioFileMapsMissingFile() {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.RemoteTransportTests.missing.\(UUID().uuidString).wav")

        do {
            _ = try VoiceInkCloudTranscriptionAudioFile.load(from: audioURL)
            XCTFail("Expected audio file not found")
        } catch VoiceInkCloudTranscriptionError.audioFileNotFound {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    func testMultipartFormDataBuildsContentTypeAndCRLFBody() throws {
        var form = VoiceInkMultipartFormData(boundary: "Boundary-test")
        form.addField(name: "model", value: "whisper-large-v3")
        form.addFile(name: "file", fileName: "sample.wav", mimeType: "audio/wav", fileData: Data("WAVDATA".utf8))

        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=Boundary-test")
        XCTAssertEqual(
            try XCTUnwrap(String(data: form.data, encoding: .utf8)),
            [
                "--Boundary-test",
                #"Content-Disposition: form-data; name="model""#,
                "",
                "whisper-large-v3",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="file"; filename="sample.wav""#,
                "Content-Type: audio/wav",
                "",
                "WAVDATA",
                "--Boundary-test--",
                ""
            ].joined(separator: "\r\n")
        )
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

    func testRemoteTranscriptionServiceFileOptionsUseProviderBatchDefaults() throws {
        let groq = VoiceInkRemoteTranscriptionService(provider: .groq)
            .fileTranscriptionOptions(prompt: "spell Roma correctly")
        XCTAssertEqual(groq.prompt, "spell Roma correctly")
        XCTAssertEqual(groq.openAICompatibleResponseFormat, "json")
        XCTAssertEqual(groq.openAICompatibleTemperature, "0")
        XCTAssertEqual(groq.openAICompatibleTimeout, 60)
        XCTAssertEqual(groq.openAICompatibleMaxRetries, 2)

        let deepgram = VoiceInkRemoteTranscriptionService(provider: .deepgram)
            .fileTranscriptionOptions(prompt: "ignored")
        XCTAssertNil(deepgram.prompt)
        XCTAssertEqual(deepgram.deepgramParagraphs, true)
        XCTAssertNil(deepgram.deepgramDiarize)
        XCTAssertEqual(deepgram.deepgramTimeout, 30)

        let soniox = VoiceInkRemoteTranscriptionService(provider: .soniox)
            .fileTranscriptionOptions(
                prompt: "ignored",
                customVocabulary: [" Roma ", "Felix", "roma", ""]
            )
        XCTAssertEqual(soniox.customVocabulary, ["Roma", "Felix"])

        let directTransport = VoiceInkRemoteTranscriptionService(
            transport: .openAICompatible,
            apiBaseURL: try XCTUnwrap(URL(string: "https://custom.example.test"))
        )
            .fileTranscriptionOptions(
                prompt: "custom prompt",
                customVocabulary: ["Roma"]
            )
        XCTAssertEqual(directTransport.prompt, "custom prompt")
        XCTAssertEqual(directTransport.customVocabulary, ["Roma"])
        XCTAssertNil(directTransport.openAICompatibleResponseFormat)
        XCTAssertNil(directTransport.openAICompatibleTimeout)
    }

    func testMacOSCloudTranscriptionPolicyBuildsSharedTransportRequest() async throws {
        let requestCapture = MacOSCloudTranscriptionRequestCapture()

        let text = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
            modelProvider: .soniox,
            apiKey: "soniox-key",
            modelName: "stt-async-v4",
            audioData: Data([4, 5, 6]),
            fileName: "clip.wav",
            language: "en",
            prompt: "ignored",
            customVocabulary: [" Roma ", "Felix", "roma", ""]
        ) { request in
            await requestCapture.store(request)
            return "remote transcript"
        }

        let capturedRequest = await requestCapture.value
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(text, "remote transcript")
        XCTAssertEqual(request.provider, .soniox)
        XCTAssertEqual(request.apiKey, "soniox-key")
        XCTAssertEqual(request.modelName, "stt-async-v4")
        XCTAssertEqual(request.audioData, Data([4, 5, 6]))
        XCTAssertEqual(request.fileName, "clip.wav")
        XCTAssertEqual(request.language, "en")
        XCTAssertNil(request.options.prompt)
        XCTAssertEqual(request.options.customVocabulary, ["Roma", "Felix"])
    }

    func testMacOSCloudTranscriptionPolicyRejectsBlankAPIKeyBeforeTransport() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .soniox,
                apiKey: " \n\t ",
                modelName: "stt-async-v4",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                XCTFail("Blank API keys should not call transport")
                return "unexpected"
            }
            XCTFail("Expected missing API key error")
        } catch VoiceInkCloudTranscriptionError.missingAPIKey {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMacOSCloudTranscriptionPolicyRejectsUnsupportedBatchProvider() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .cartesia,
                apiKey: "cartesia-key",
                modelName: "ink-whisper",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                XCTFail("Unsupported provider should not call transport")
                return "unexpected"
            }
            XCTFail("Expected unsupported provider error")
        } catch VoiceInkCloudTranscriptionError.unsupportedProvider {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMacOSCloudTranscriptionPolicyMapsProviderHTTPNSError() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .assemblyAI,
                apiKey: "assembly-key",
                modelName: "universal-3-pro",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                throw NSError(
                    domain: try XCTUnwrap(VoiceInkMacOSTranscriptionModelProvider.assemblyAI.apiErrorDomain),
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "server failed"]
                )
            }
            XCTFail("Expected API request failure")
        } catch VoiceInkCloudTranscriptionError.apiRequestFailed(let statusCode, let message) {
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "server failed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMacOSCloudTranscriptionPolicyMapsUnknownErrorsToNetworkError() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .soniox,
                apiKey: "soniox-key",
                modelName: "stt-async-v4",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                throw NSError(
                    domain: "Transport",
                    code: -42,
                    userInfo: [NSLocalizedDescriptionKey: "socket closed"]
                )
            }
            XCTFail("Expected network error")
        } catch VoiceInkCloudTranscriptionError.networkError(let error) {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "Transport")
            XCTAssertEqual(nsError.code, -42)
            XCTAssertEqual(nsError.localizedDescription, "socket closed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoteTranscriptionServiceUsesSharedProviderErrorDomainsForProviderTransports() throws {
        let providers: [(VoiceInkProviderKind, VoiceInkTranscriptionModelProvider)] = [
            (.mistral, .mistral),
            (.assemblyAI, .assemblyAI),
            (.xai, .xai)
        ]

        for (provider, modelProvider) in providers {
            XCTAssertEqual(
                VoiceInkRemoteTranscriptionService(provider: provider)
                    .providerAPIErrorDomain(defaultingTo: modelProvider),
                try XCTUnwrap(provider.transcriptionModelProvider?.apiErrorDomain)
            )
        }

        let directMistral = VoiceInkRemoteTranscriptionService(
            transport: .mistral,
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.mistral.ai"))
        )
        XCTAssertEqual(
            directMistral.providerAPIErrorDomain(defaultingTo: .mistral),
            VoiceInkTranscriptionModelProvider.mistral.apiErrorDomain
        )
    }

    func testOpenAICompatibleTranscriptionCodecCanDisablePlainTextFallback() throws {
        let plainTextData = Data("plain transcription".utf8)

        XCTAssertEqual(
            VoiceInkOpenAICompatibleTranscriptionCodec.transcriptionText(
                from: plainTextData,
                allowPlainTextFallback: true
            ),
            "plain transcription"
        )
        XCTAssertEqual(
            VoiceInkOpenAICompatibleTranscriptionCodec.transcriptionText(
                from: plainTextData,
                allowPlainTextFallback: false
            ),
            ""
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

private actor MacOSCloudTranscriptionRequestCapture {
    private var storedValue: VoiceInkMacOSCloudTranscriptionRequest?

    var value: VoiceInkMacOSCloudTranscriptionRequest? {
        storedValue
    }

    func store(_ request: VoiceInkMacOSCloudTranscriptionRequest) {
        storedValue = request
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

private struct StubNetworkError: LocalizedError {
    var errorDescription: String? {
        "network offline"
    }
}

private struct StubVerificationError: LocalizedError {
    var errorDescription: String? {
        "network offline"
    }
}
