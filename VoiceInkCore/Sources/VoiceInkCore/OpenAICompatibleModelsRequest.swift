import Foundation

public enum VoiceInkOpenAICompatibleModelsRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.openAICompatibleModelsURL(from: baseURL))
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}
