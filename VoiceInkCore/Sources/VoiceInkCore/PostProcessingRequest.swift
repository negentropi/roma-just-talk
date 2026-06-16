import Foundation

public struct VoiceInkPostProcessingRequest: Equatable, Sendable {
    public static let defaultTemperature = 0.2

    public let messages: [VoiceInkOpenAICompatibleChatMessage]
    public let temperature: Double

    public init?(
        prompt: String,
        transcript: String,
        temperature: Double = Self.defaultTemperature
    ) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.messages = [
            VoiceInkOpenAICompatibleChatMessage(
                role: "system",
                content: VoiceInkAIRequestPrompts.postProcessingSystemPrompt
            ),
            VoiceInkOpenAICompatibleChatMessage(
                role: "user",
                content: VoiceInkAIRequestPrompts.postProcessingUserPrompt(
                    prompt: prompt,
                    transcript: transcript
                )
            )
        ]
        self.temperature = temperature
    }

    public static func finalizedTranscript(
        from responseText: String,
        fallbackTranscript: String
    ) -> String {
        let filteredText = VoiceInkAIEnhancementOutputFilter.filter(responseText)
        return filteredText.isEmpty ? fallbackTranscript : filteredText
    }
}
