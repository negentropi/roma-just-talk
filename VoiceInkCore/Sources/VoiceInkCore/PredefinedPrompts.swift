import Foundation

public struct VoiceInkPredefinedPrompt: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let promptText: String
    public let icon: String
    public let description: String
    public let useSystemInstructions: Bool

    public init(
        id: UUID,
        title: String,
        promptText: String,
        icon: String,
        description: String,
        useSystemInstructions: Bool
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.icon = icon
        self.description = description
        self.useSystemInstructions = useSystemInstructions
    }
}

public enum VoiceInkPredefinedPrompts {
    public static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let assistantPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    public static var all: [VoiceInkPredefinedPrompt] {
        [
            VoiceInkPredefinedPrompt(
                id: defaultPromptId,
                title: "Default",
                promptText: VoiceInkPromptTemplates.macTemplate(named: "System Default")?.promptText ?? "",
                icon: "checkmark.seal.fill",
                description: "Default mode to improved clarity and accuracy of the transcription",
                useSystemInstructions: true
            ),
            VoiceInkPredefinedPrompt(
                id: assistantPromptId,
                title: "Assistant",
                promptText: VoiceInkAIPrompts.assistantMode,
                icon: "bubble.left.and.bubble.right.fill",
                description: "AI assistant that provides direct answers to queries",
                useSystemInstructions: false
            )
        ]
    }
}
