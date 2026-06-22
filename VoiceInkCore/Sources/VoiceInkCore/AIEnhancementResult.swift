import Foundation

public struct VoiceInkAIEnhancementResult: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let modelName: String?
    public let promptName: String?
    public let requestSystemMessage: String?
    public let requestUserMessage: String?

    public init(
        text: String,
        duration: TimeInterval,
        modelName: String?,
        promptName: String?,
        requestSystemMessage: String?,
        requestUserMessage: String?
    ) {
        self.text = text
        self.duration = duration
        self.modelName = modelName
        self.promptName = promptName
        self.requestSystemMessage = requestSystemMessage
        self.requestUserMessage = requestUserMessage
    }

    public static func completed(
        text: String,
        startedAt startDate: Date,
        endedAt endDate: Date,
        modelName: String?,
        promptName: String?,
        requestSystemMessage: String?,
        requestUserMessage: String?
    ) -> VoiceInkAIEnhancementResult {
        VoiceInkAIEnhancementResult(
            text: text,
            duration: endDate.timeIntervalSince(startDate),
            modelName: modelName,
            promptName: promptName,
            requestSystemMessage: requestSystemMessage,
            requestUserMessage: requestUserMessage
        )
    }
}
