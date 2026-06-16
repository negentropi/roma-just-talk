import Foundation

public struct VoiceInkPreparedMistralTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkMistralTranscriptionCodec {
    public static func multipartContentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public static func requestBody(
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String
    ) -> Data {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addField(name: "model", value: model)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        return form.data
    }

    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkMistralTranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkMistralRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedMistralTranscriptionRequest {
        let body = VoiceInkMistralTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary
        )

        var request = URLRequest(url: VoiceInkProviderEndpoint.mistralAudioTranscriptionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(
            VoiceInkMistralTranscriptionCodec.multipartContentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedMistralTranscriptionRequest(request: request, body: body)
    }

    public static func makeModelsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.mistralModelsURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private struct VoiceInkMistralTranscriptionResponse: Decodable {
    let text: String
}
