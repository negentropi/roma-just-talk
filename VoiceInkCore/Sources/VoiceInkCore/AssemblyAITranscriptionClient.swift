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
        let (data, response) = try await VoiceInkRetriedRequest.upload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(response: response, data: data, errorDomain: errorDomain)
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
        let (data, response) = try await VoiceInkRetriedRequest.data(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(response: response, data: data, errorDomain: errorDomain)
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
