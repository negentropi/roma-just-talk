import Foundation

public struct VoiceInkDeepgramTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        smartFormat: Bool = true,
        punctuate: Bool = true,
        paragraphs: Bool? = nil,
        diarize: Bool? = false,
        customVocabulary: [String] = [],
        errorDomain: String = VoiceInkTranscriptionModelProvider.deepgram.requiredAPIErrorDomain,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        let request = try VoiceInkDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            language: language,
            smartFormat: smartFormat,
            punctuate: punctuate,
            paragraphs: paragraphs,
            diarize: diarize,
            customVocabulary: customVocabulary,
            timeout: timeout
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )

        return try VoiceInkDeepgramTranscriptionCodec.transcript(from: data)
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
            request: VoiceInkDeepgramRequestBuilder.makeProjectsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}
