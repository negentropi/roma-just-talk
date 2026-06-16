import Foundation

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
        temperature: Double?
    ) throws -> Data {
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
