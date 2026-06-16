import Foundation

public struct VoiceInkOpenAICompatibleTranscriptionResponse: Decodable, Equatable, Sendable {
    public let text: String?
    public let language: String?
    public let duration: Double?

    public init(text: String?, language: String? = nil, duration: Double? = nil) {
        self.text = text
        self.language = language
        self.duration = duration
    }
}

public enum VoiceInkOpenAICompatibleTranscriptionCodec {
    public static func multipartContentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public static func requestBody(
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> Data {
        let crlf = "\r\n"
        var body = Data()

        append("--\(boundary)\(crlf)", to: &body)
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(crlf)", to: &body)
        append("Content-Type: audio/wav\(crlf)\(crlf)", to: &body)
        body.append(audioData)
        append(crlf, to: &body)

        appendField("model", model, boundary: boundary, crlf: crlf, to: &body)
        if let responseFormat, !responseFormat.isEmpty {
            appendField("response_format", responseFormat, boundary: boundary, crlf: crlf, to: &body)
        }
        if let temperature, !temperature.isEmpty {
            appendField("temperature", temperature, boundary: boundary, crlf: crlf, to: &body)
        }
        if let language, !language.isEmpty {
            appendField("language", language, boundary: boundary, crlf: crlf, to: &body)
        }
        if let prompt, !prompt.isEmpty {
            appendField("prompt", prompt, boundary: boundary, crlf: crlf, to: &body)
        }

        append("--\(boundary)--\(crlf)", to: &body)
        return body
    }

    public static func textIfPresent(from data: Data) throws -> String? {
        try JSONDecoder()
            .decode(VoiceInkOpenAICompatibleTranscriptionResponse.self, from: data)
            .text
    }

    private static func appendField(
        _ name: String,
        _ value: String,
        boundary: String,
        crlf: String,
        to body: inout Data
    ) {
        append("--\(boundary)\(crlf)", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)", to: &body)
        append(value, to: &body)
        append(crlf, to: &body)
    }

    private static func append(_ string: String, to body: inout Data) {
        body.append(Data(string.utf8))
    }
}
