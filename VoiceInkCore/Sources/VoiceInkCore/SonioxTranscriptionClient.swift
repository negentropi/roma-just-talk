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
        let (data, response) = try await VoiceInkRetriedRequest.upload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(response: response, data: data, errorDomain: errorDomain)
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
        let (data, response) = try await VoiceInkRetriedRequest.data(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(response: response, data: data, errorDomain: errorDomain)
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
        let (data, response) = try await VoiceInkRetriedRequest.data(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(response: response, data: data, errorDomain: errorDomain)
        return VoiceInkSonioxTranscriptionCodec.transcript(from: data)
    }
}
