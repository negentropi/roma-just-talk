import Foundation

public struct VoiceInkAssemblyAITranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = VoiceInkTranscriptionModelProvider.assemblyAI.requiredAPIErrorDomain
    ) async throws -> String {
        let uploadURL = try await uploadAudio(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        let transcriptID = try await createTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            audioURL: uploadURL,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try await pollTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptID,
            maxWaitSeconds: maxWaitSeconds,
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
            request: VoiceInkAssemblyAIRequestBuilder.makeTranscriptsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func uploadAudio(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = VoiceInkAssemblyAIRequestBuilder.makeUploadAudioRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try VoiceInkAssemblyAITranscriptionCodec.uploadedAudioURL(from: data)
    }

    private func createTranscript(
        baseURL: URL,
        apiKey: String,
        audioURL: String,
        model: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = try VoiceInkAssemblyAIRequestBuilder.makeCreateTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioURL: audioURL,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try VoiceInkAssemblyAITranscriptionCodec.createdTranscriptID(from: data)
    }

    private func pollTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        try await VoiceInkRemotePollingPolicy.pollValidatedData(
            request: {
                VoiceInkAssemblyAIRequestBuilder.makeTranscriptStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            let transcript = try VoiceInkAssemblyAITranscriptionCodec.transcriptStatus(from: data)
            switch transcript.status.lowercased() {
            case "completed":
                return .finished(transcript.text ?? "")
            case "error":
                throw NSError(
                    domain: errorDomain,
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: transcript.error ?? "AssemblyAI transcription failed."]
                )
            default:
                return .keepPolling
            }
        }
    }

}

public struct VoiceInkPreparedAssemblyAIUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public struct VoiceInkAssemblyAITranscriptStatus: Equatable, Sendable {
    public let status: String
    public let text: String?
    public let error: String?

    public init(status: String, text: String?, error: String?) {
        self.status = status
        self.text = text
        self.error = error
    }
}

public enum VoiceInkAssemblyAITranscriptionCodec {
    public static func uploadedAudioURL(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkAssemblyAIUploadResponse.self, from: data).uploadURL
    }

    public static func createdTranscriptID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkAssemblyAITranscriptCreateResponse.self, from: data).id
    }

    public static func transcriptStatus(from data: Data) throws -> VoiceInkAssemblyAITranscriptStatus {
        let decoded = try JSONDecoder().decode(VoiceInkAssemblyAITranscriptStatusResponse.self, from: data)
        return VoiceInkAssemblyAITranscriptStatus(
            status: decoded.status,
            text: decoded.text,
            error: decoded.error
        )
    }
}

public enum VoiceInkAssemblyAIRequestBuilder {
    public static func makeUploadAudioRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedAssemblyAIUploadRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAIUploadURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedAssemblyAIUploadRequest(request: request, body: audioData)
    }

    public static func makeCreateTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        audioURL: String,
        model: String,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        let speechModels = speechModels(for: model)
        let primarySpeechModel = speechModels.first ?? model
        var payload: [String: Any] = [
            "audio_url": audioURL,
            "speech_models": speechModels,
            "punctuate": true,
            "format_text": true
        ]

        if let language, !language.isEmpty, language != "auto" {
            payload["language_code"] = language
        } else {
            payload["language_detection"] = true
        }

        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyterms = normalizedKeyterms(customVocabulary, model: primarySpeechModel)
        if supportsPrompt(speechModels), !trimmedPrompt.isEmpty {
            payload["prompt"] = appendedKeyterms(keyterms, to: trimmedPrompt)
        } else if !keyterms.isEmpty {
            payload["keyterms_prompt"] = keyterms
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAITranscriptsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAITranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAITranscriptsURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    static func speechModels(for model: String) -> [String] {
        switch model {
        case "universal-3-pro":
            return ["universal-3-pro", "universal-2"]
        case "universal-2":
            return ["universal-2"]
        case "universal-streaming", "universal-streaming-english", "universal-streaming-multilingual", "whisper-rt":
            return ["universal-2"]
        default:
            return [model]
        }
    }

    static func supportsPrompt(_ speechModels: [String]) -> Bool {
        speechModels.contains("universal-3-pro")
    }

    static func normalizedKeyterms(_ terms: [String], model: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let limit = model == "universal-2" ? 200 : 1_000
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split(separator: " ").count
            guard !trimmed.isEmpty, trimmed.count <= 50, wordCount <= 6 else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }

    static func appendedKeyterms(_ keyterms: [String], to prompt: String) -> String {
        guard !keyterms.isEmpty else { return prompt }
        return "\(prompt)\n\nBoost these terms when they appear in the audio: \(keyterms.joined(separator: ", "))."
    }
}

private struct VoiceInkAssemblyAIUploadResponse: Decodable {
    let uploadURL: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
    }
}

private struct VoiceInkAssemblyAITranscriptCreateResponse: Decodable {
    let id: String
}

private struct VoiceInkAssemblyAITranscriptStatusResponse: Decodable {
    let status: String
    let text: String?
    let error: String?
}
