import Foundation

public struct VoiceInkSpeechmaticsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = VoiceInkTranscriptionModelProvider.speechmatics.requiredAPIErrorDomain
    ) async throws -> String {
        let jobID = try await submitJob(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try await pollJobStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkSpeechmaticsRequestBuilder.makeJobsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func submitJob(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String?,
        operatingPoint: String,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = try VoiceInkSpeechmaticsRequestBuilder.makeSubmitJobRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try VoiceInkSpeechmaticsTranscriptionCodec.submittedJobID(from: data)
    }

    private func pollJobStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        try await VoiceInkRemotePollingPolicy.pollValidatedData(
            request: {
                VoiceInkSpeechmaticsRequestBuilder.makeJobStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            if let status = try? VoiceInkSpeechmaticsTranscriptionCodec.jobStatus(from: data).lowercased() {
                switch status {
                case "done":
                    return .finished(())
                case "rejected":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was rejected."]
                    )
                case "deleted":
                    throw NSError(
                        domain: errorDomain,
                        code: 410,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was deleted."]
                    )
                default:
                    break
                }
            }

            return .keepPolling
        }
    }

    private func fetchTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = VoiceInkSpeechmaticsRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return VoiceInkSpeechmaticsTranscriptionCodec.transcript(from: data)
    }
}

public struct VoiceInkPreparedSpeechmaticsUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkSpeechmaticsTranscriptionCodec {
    public static func submittedJobID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSpeechmaticsSubmitJobResponse.self, from: data).id
    }

    public static func jobStatus(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSpeechmaticsJobStatusResponse.self, from: data).job.status
    }

    public static func transcript(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    public static func speechmaticsLanguage(from language: String?) -> String {
        guard let language, !language.isEmpty, language != "auto" else { return "auto" }
        switch language {
        case "zh":
            return "cmn"
        default:
            return language
        }
    }
}

public enum VoiceInkSpeechmaticsRequestBuilder {
    public static func makeSubmitJobRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) throws -> VoiceInkPreparedSpeechmaticsUploadRequest {
        let config = VoiceInkSpeechmaticsSubmitJobConfig.make(
            language: VoiceInkSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: language),
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary
        )
        let configData = try JSONSerialization.data(withJSONObject: config)
        guard let configString = String(data: configData, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addField(name: "config", value: configString)
        form.addFile(name: "data_file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsJobsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedSpeechmaticsUploadRequest(request: request, body: form.data)
    }

    public static func makeJobStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsJobURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsTranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeJobsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsJobsURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private enum VoiceInkSpeechmaticsSubmitJobConfig {
    static func make(
        language: String,
        operatingPoint: String,
        customVocabulary: [String]
    ) -> [String: Any] {
        var transcriptionConfig: [String: Any] = [
            "language": language,
            "operating_point": operatingPoint
        ]
        if !customVocabulary.isEmpty {
            transcriptionConfig["additional_vocab"] = customVocabulary.map { ["content": $0] }
        }
        return [
            "type": "transcription",
            "transcription_config": transcriptionConfig
        ]
    }
}

private struct VoiceInkSpeechmaticsSubmitJobResponse: Decodable {
    let id: String
}

private struct VoiceInkSpeechmaticsJobStatusResponse: Decodable {
    let job: Job

    struct Job: Decodable {
        let status: String
    }
}
