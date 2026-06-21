import Foundation

public struct VoiceInkGeminiTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = VoiceInkGeminiTranscriptionCodec.defaultPrompt,
        errorDomain: String = VoiceInkTranscriptionModelProvider.gemini.requiredAPIErrorDomain,
        timeout: TimeInterval? = 60
    ) async throws -> String {
        let request = try VoiceInkGeminiRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            mimeType: mimeType,
            prompt: prompt,
            timeout: timeout
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )

        return try VoiceInkGeminiTranscriptionCodec.transcript(from: data)
    }

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

        let request = VoiceInkGeminiRequestBuilder.makeModelsRequest(
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
}
