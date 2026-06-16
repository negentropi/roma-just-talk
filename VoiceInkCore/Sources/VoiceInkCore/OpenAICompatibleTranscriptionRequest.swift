import Foundation

public struct VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }

    public func requestWithHTTPBody() -> URLRequest {
        var copy = request
        copy.httpBody = body
        return copy
    }
}

public enum VoiceInkOpenAICompatibleTranscriptionRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
        make(
            url: VoiceInkProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: baseURL),
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }

    public static func make(
        url: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            VoiceInkOpenAICompatibleTranscriptionCodec.multipartContentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = VoiceInkOpenAICompatibleTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        return VoiceInkPreparedOpenAICompatibleTranscriptionRequest(request: request, body: body)
    }
}
