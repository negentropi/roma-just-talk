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
        errorDomain: String = "OpenAICompatibleTranscriptionAPI"
    ) async throws -> String {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        let (data, response) = try await URLSession.shared.data(
            for: preparedRequest.requestWithHTTPBody()
        )
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: errorDomain,
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorText]
            )
        }

        if let text = try? VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(from: data) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await modelsClient.verifyAPIKey(baseURL: baseURL, apiKey: apiKey)
    }
}
