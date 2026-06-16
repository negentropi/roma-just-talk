import Foundation

public enum VoiceInkGeminiTranscriptionCodec {
    public static let defaultPrompt = "Please transcribe this audio file. Provide only the transcribed text."

    public static func requestBody(
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = defaultPrompt
    ) throws -> Data {
        try JSONEncoder().encode(
            VoiceInkGeminiTranscriptionRequest(
                contents: [
                    VoiceInkGeminiContent(parts: [
                        VoiceInkGeminiPart(text: prompt, inlineData: nil),
                        VoiceInkGeminiPart(
                            text: nil,
                            inlineData: VoiceInkGeminiInlineData(
                                mimeType: mimeType,
                                data: audioData.base64EncodedString()
                            )
                        )
                    ])
                ]
            )
        )
    }

    public static func transcript(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(VoiceInkGeminiTranscriptionResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public enum VoiceInkGeminiRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = VoiceInkGeminiTranscriptionCodec.defaultPrompt,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.geminiGenerateContentURL(from: baseURL, model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try VoiceInkGeminiTranscriptionCodec.requestBody(
            audioData: audioData,
            mimeType: mimeType,
            prompt: prompt
        )
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeModelsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.geminiModelsURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private struct VoiceInkGeminiTranscriptionRequest: Encodable {
    let contents: [VoiceInkGeminiContent]
}

private struct VoiceInkGeminiContent: Encodable {
    let parts: [VoiceInkGeminiPart]
}

private struct VoiceInkGeminiPart: Encodable {
    let text: String?
    let inlineData: VoiceInkGeminiInlineData?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let inlineData {
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }
}

private struct VoiceInkGeminiInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct VoiceInkGeminiTranscriptionResponse: Decodable {
    let candidates: [VoiceInkGeminiCandidate]
}

private struct VoiceInkGeminiCandidate: Decodable {
    let content: VoiceInkGeminiResponseContent
}

private struct VoiceInkGeminiResponseContent: Decodable {
    let parts: [VoiceInkGeminiResponsePart]
}

private struct VoiceInkGeminiResponsePart: Decodable {
    let text: String
}
