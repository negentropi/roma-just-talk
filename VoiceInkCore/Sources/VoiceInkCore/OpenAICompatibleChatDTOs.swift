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

public struct VoiceInkOpenAICompatibleClient: Sendable {
    public init() {}

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
            request: VoiceInkOpenAICompatibleModelsRequestBuilder.make(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    public func chatCompletion(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double? = 0.2,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) async throws -> String {
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: "LLMPostProcessing"
        )

        return try VoiceInkOpenAICompatibleChatCodec.firstMessageContent(from: data)
    }
}

public struct VoiceInkOpenAICompatibleChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct VoiceInkOpenAICompatibleChatRequest: Codable, Equatable, Sendable {
    public let model: String
    public let messages: [VoiceInkOpenAICompatibleChatMessage]
    public let temperature: Double?

    public init(
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double?
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

public struct VoiceInkOpenAICompatibleChatChoice: Codable, Equatable, Sendable {
    public let message: VoiceInkOpenAICompatibleChatMessage

    public init(message: VoiceInkOpenAICompatibleChatMessage) {
        self.message = message
    }
}

public struct VoiceInkOpenAICompatibleChatResponse: Codable, Equatable, Sendable {
    public let choices: [VoiceInkOpenAICompatibleChatChoice]

    public init(choices: [VoiceInkOpenAICompatibleChatChoice]) {
        self.choices = choices
    }
}

public enum VoiceInkOpenAICompatibleChatCodec {
    public static func requestBody(
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double?,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) throws -> Data {
        if reasoningEffort != nil || extraBodyParameters?.isEmpty == false {
            var body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role, "content": $0.content] }
            ]
            if let temperature {
                body["temperature"] = temperature
            }
            if let reasoningEffort {
                body["reasoning_effort"] = reasoningEffort
            }
            extraBodyParameters?.forEach { key, value in
                body[key] = value
            }
            return try JSONSerialization.data(withJSONObject: body)
        }

        let request = VoiceInkOpenAICompatibleChatRequest(
            model: model,
            messages: messages,
            temperature: temperature
        )
        return try JSONEncoder().encode(request)
    }

    public static func firstMessageContent(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(VoiceInkOpenAICompatibleChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
}

public enum VoiceInkOpenAICompatibleChatRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double?,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try VoiceInkOpenAICompatibleChatCodec.requestBody(
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        return request
    }
}
