import Foundation

public enum VoiceInkOpenAICompatibleModelsRequestBuilder {
    public static func make(baseURL: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.openAICompatibleModelsURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}
