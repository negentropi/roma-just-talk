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

    static func transcriptionText(from data: Data, allowPlainTextFallback: Bool) -> String {
        if let text = try? textIfPresent(from: data) {
            return text
        }
        guard allowPlainTextFallback else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
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

        let data = try await VoiceInkRetriedRequest.validatedData(
            for: preparedRequest.requestWithHTTPBody(),
            timeout: timeout,
            maxRetries: maxRetries,
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
