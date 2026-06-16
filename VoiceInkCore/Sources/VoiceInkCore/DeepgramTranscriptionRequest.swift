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
        language: String? = nil
    ) throws -> URLRequest {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "false")
        ]

        if let language, !language.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: language))
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
        return request
    }

    public static func makeProjectsRequest(baseURL: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.deepgramProjectsURL(from: baseURL))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
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
