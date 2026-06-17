import Foundation

public struct VoiceInkCustomPrompt: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let promptText: String
    public var isActive: Bool
    public let icon: String
    public let description: String?
    public let isPredefined: Bool
    public let triggerWords: [String]
    public let useSystemInstructions: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        isActive: Bool = false,
        icon: String = "doc.text.fill",
        description: String? = nil,
        isPredefined: Bool = false,
        triggerWords: [String] = [],
        useSystemInstructions: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.isActive = isActive
        self.icon = icon
        self.description = description
        self.isPredefined = isPredefined
        self.triggerWords = triggerWords
        self.useSystemInstructions = useSystemInstructions
    }

    public init(
        predefinedPrompt: VoiceInkPredefinedPrompt,
        isActive: Bool = false,
        triggerWords: [String] = []
    ) {
        self.init(
            id: predefinedPrompt.id,
            title: predefinedPrompt.title,
            promptText: predefinedPrompt.promptText,
            isActive: isActive,
            icon: predefinedPrompt.icon,
            description: predefinedPrompt.description,
            isPredefined: true,
            triggerWords: triggerWords,
            useSystemInstructions: predefinedPrompt.useSystemInstructions
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptText, isActive, icon, description, isPredefined, triggerWords, useSystemInstructions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptText = try container.decode(String.self, forKey: .promptText)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        icon = try container.decode(String.self, forKey: .icon)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPredefined = try container.decode(Bool.self, forKey: .isPredefined)
        triggerWords = try container.decode([String].self, forKey: .triggerWords)
        useSystemInstructions = try container.decodeIfPresent(Bool.self, forKey: .useSystemInstructions) ?? true
    }

    public var finalPromptText: String {
        VoiceInkAIPrompts.finalPromptText(promptText, useSystemInstructions: useSystemInstructions)
    }
}

public enum VoiceInkCustomPromptPolicy {
    public static func repairedPredefinedPrompts(
        in prompts: [VoiceInkCustomPrompt],
        predefinedPrompts: [VoiceInkPredefinedPrompt] = VoiceInkPredefinedPrompts.all
    ) -> [VoiceInkCustomPrompt] {
        var repairedPrompts = prompts

        for predefinedPrompt in predefinedPrompts {
            let template = VoiceInkCustomPrompt(predefinedPrompt: predefinedPrompt)
            if let existingIndex = repairedPrompts.firstIndex(where: { $0.id == template.id }) {
                let existingPrompt = repairedPrompts[existingIndex]
                repairedPrompts[existingIndex] = VoiceInkCustomPrompt(
                    id: existingPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: existingPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: existingPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
            } else {
                repairedPrompts.append(template)
            }
        }

        return repairedPrompts
    }

    public static func triggerDetectablePrompts(from prompts: [VoiceInkCustomPrompt]) -> [VoiceInkCustomPrompt] {
        prompts.filter { prompt in
            prompt.triggerWords.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
}
