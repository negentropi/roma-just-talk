import Foundation

public struct VoiceInkAPIKeyVerificationResult: Equatable, Sendable {
    public let isValid: Bool
    public let errorMessage: String?

    public init(isValid: Bool, errorMessage: String?) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }
}

public struct VoiceInkOpenAICompatibleClient: Sendable {
    public init() {}

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        }

        let request = VoiceInkOpenAICompatibleModelsRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "No HTTP response received."
                )
            }

            if (200..<300).contains(http.statusCode) {
                return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            }

            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            )
        } catch {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    public func chatCompletion(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double? = VoiceInkPostProcessingRequest.defaultTemperature,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) async throws -> String {
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "LLMPostProcessing",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorText]
            )
        }

        return try VoiceInkOpenAICompatibleChatCodec.firstMessageContent(from: data)
    }
}
