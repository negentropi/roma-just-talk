import Foundation

public struct VoiceInkPreparedElevenLabsTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkElevenLabsTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkElevenLabsTranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkElevenLabsRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedElevenLabsTranscriptionRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        form.addField(name: "model_id", value: model)
        form.addField(name: "temperature", value: "0.0")
        form.addField(name: "tag_audio_events", value: "false")
        if let language, !language.isEmpty {
            form.addField(name: "language_code", value: language)
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.elevenLabsSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedElevenLabsTranscriptionRequest(request: request, body: form.data)
    }

    public static func makeUserRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.elevenLabsUserURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkElevenLabsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        errorDomain: String = VoiceInkTranscriptionModelProvider.elevenLabs.requiredAPIErrorDomain,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try VoiceInkElevenLabsTranscriptionCodec.transcript(from: data)
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
            request: VoiceInkElevenLabsRequestBuilder.makeUserRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkElevenLabsTranscriptionResponse: Decodable {
    let text: String
}
