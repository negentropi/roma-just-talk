import Foundation

public enum VoiceInkDeepgramTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(DeepgramTranscriptionResponse.self, from: data)
        return decoded.results.channels.first?.alternatives.first?.transcript ?? ""
    }
}

public enum VoiceInkDeepgramRequestBuilder {
    public static func makeTranscriptionRequest(
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
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: smartFormat ? "true" : "false"),
            URLQueryItem(name: "punctuate", value: punctuate ? "true" : "false")
        ]

        if let paragraphs {
            queryItems.append(URLQueryItem(name: "paragraphs", value: paragraphs ? "true" : "false"))
        }

        if let diarize {
            queryItems.append(URLQueryItem(name: "diarize", value: diarize ? "true" : "false"))
        }

        if let language, !language.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }

        for term in customVocabulary where !term.isEmpty {
            queryItems.append(URLQueryItem(name: "keyterm", value: term))
        }

        var components = URLComponents(
            url: VoiceInkProviderEndpoint.deepgramListenURL(from: baseURL),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems

        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeProjectsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.deepgramProjectsURL(from: baseURL))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

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

        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
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

private struct DeepgramTranscriptionResponse: Decodable {
    let results: DeepgramResults
}

private struct DeepgramResults: Decodable {
    let channels: [DeepgramChannel]
}

private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}

private struct DeepgramAlternative: Decodable {
    let transcript: String
}
