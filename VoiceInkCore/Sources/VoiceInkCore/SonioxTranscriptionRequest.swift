import Foundation

public struct VoiceInkSonioxTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        errorDomain: String = VoiceInkTranscriptionModelProvider.soniox.requiredAPIErrorDomain
    ) async throws -> String {
        let fileID = try await uploadFile(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout,
            errorDomain: errorDomain
        )
        let transcriptionID = try await createTranscription(
            baseURL: baseURL,
            apiKey: apiKey,
            fileID: fileID,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout,
            errorDomain: errorDomain
        )
        try await pollTranscriptionStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptionID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptionID,
            timeout: timeout,
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
            request: VoiceInkSonioxRequestBuilder.makeFilesRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func uploadFile(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = VoiceInkSonioxRequestBuilder.makeUploadFileRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return try VoiceInkSonioxTranscriptionCodec.uploadedFileID(from: data)
    }

    private func createTranscription(
        baseURL: URL,
        apiKey: String,
        fileID: String,
        model: String,
        language: String?,
        customVocabulary: [String],
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let request = try VoiceInkSonioxRequestBuilder.makeCreateTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            fileID: fileID,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return try VoiceInkSonioxTranscriptionCodec.createdTranscriptionID(from: data)
    }

    private func pollTranscriptionStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        try await VoiceInkRemotePollingPolicy.pollValidatedData(
            request: {
                VoiceInkSonioxRequestBuilder.makeTranscriptionStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            if let status = try? VoiceInkSonioxTranscriptionCodec.status(from: data).lowercased() {
                switch status {
                case "completed":
                    return .finished(())
                case "failed":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Soniox transcription job failed."]
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
        errorDomain: String
    ) async throws -> String {
        let request = VoiceInkSonioxRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return VoiceInkSonioxTranscriptionCodec.transcript(from: data)
    }
}

public struct VoiceInkPreparedSonioxUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkSonioxTranscriptionCodec {
    public static func uploadedFileID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSonioxIDResponse.self, from: data).id
    }

    public static func createdTranscriptionID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSonioxIDResponse.self, from: data).id
    }

    public static func status(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSonioxStatusResponse.self, from: data).status
    }

    public static func transcript(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(VoiceInkSonioxTranscriptResponse.self, from: data) {
            return decoded.text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum VoiceInkSonioxRequestBuilder {
    public static func makeUploadFileRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedSonioxUploadRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxFilesURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedSonioxUploadRequest(request: request, body: form.data)
    }

    public static func makeCreateTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        fileID: String,
        model: String,
        language: String? = nil,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var payload: [String: Any] = [
            "file_id": fileID,
            "model": model,
            "enable_speaker_diarization": false
        ]

        if !customVocabulary.isEmpty {
            payload["context"] = ["terms": customVocabulary]
        }

        if let language, !language.isEmpty {
            payload["language_hints"] = [language]
            payload["language_hints_strict"] = true
            payload["enable_language_identification"] = true
        } else {
            payload["enable_language_identification"] = true
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxTranscriptionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptionStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxTranscriptionURL(from: baseURL, id: id))
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
        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxTranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeFilesRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxFilesURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private struct VoiceInkSonioxIDResponse: Decodable {
    let id: String
}

private struct VoiceInkSonioxStatusResponse: Decodable {
    let status: String
}

private struct VoiceInkSonioxTranscriptResponse: Decodable {
    let text: String
}
