import Foundation

public struct VoiceInkPreparedXAITranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkXAITranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkXAITranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkXAIRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        format: Bool = false,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedXAITranscriptionRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        if let language, !language.isEmpty, language != "auto" {
            form.addField(name: "language", value: language)
            if format {
                form.addField(name: "format", value: "true")
            }
        }
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.xaiSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedXAITranscriptionRequest(request: request, body: form.data)
    }

    public static func makeAPIKeyRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.xaiAPIKeyURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private struct VoiceInkXAITranscriptionResponse: Decodable {
    let text: String
}
