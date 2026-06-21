import Foundation

public struct VoiceInkOpenAICompatibleTranscriptionClient: Sendable {
    private let modelsClient: VoiceInkOpenAICompatibleClient

    public init(modelsClient: VoiceInkOpenAICompatibleClient = VoiceInkOpenAICompatibleClient()) {
        self.modelsClient = modelsClient
    }

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0,
        allowPlainTextFallback: Bool = true
    ) async throws -> String {
        return try await transcribeAudioData(
            url: VoiceInkProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: baseURL),
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature,
            errorDomain: errorDomain,
            timeout: timeout,
            maxRetries: maxRetries,
            allowPlainTextFallback: allowPlainTextFallback
        )
    }

    public func transcribeAudioData(
        url: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0,
        allowPlainTextFallback: Bool = true
    ) async throws -> String {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            url: url,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        let (data, response) = try await VoiceInkRetriedRequest.data(
            for: preparedRequest.requestWithHTTPBody(),
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )

        return VoiceInkOpenAICompatibleTranscriptionCodec.transcriptionText(
            from: data,
            allowPlainTextFallback: allowPlainTextFallback
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await modelsClient.verifyAPIKey(baseURL: baseURL, apiKey: apiKey)
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await modelsClient.verifyAPIKeyDetailed(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )
    }
}
