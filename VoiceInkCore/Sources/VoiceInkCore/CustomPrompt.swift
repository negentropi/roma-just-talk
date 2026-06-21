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

public struct VoiceInkCustomPromptStoreState: Equatable, Sendable {
    public let prompts: [VoiceInkCustomPrompt]
    public let selectedPromptId: UUID?

    public init(prompts: [VoiceInkCustomPrompt], selectedPromptId: UUID?) {
        self.prompts = prompts
        self.selectedPromptId = selectedPromptId
    }
}

public struct VoiceInkAIEnhancementPromptSettingsState: Equatable, Sendable {
    public let isEnhancementEnabled: Bool
    public let selectedPromptId: UUID?

    public init(isEnhancementEnabled: Bool, selectedPromptId: UUID?) {
        self.isEnhancementEnabled = isEnhancementEnabled
        self.selectedPromptId = selectedPromptId
    }
}

public struct VoiceInkCustomPromptDraft: Equatable, Sendable {
    public let title: String
    public let promptText: String
    public let icon: String
    public let description: String
    public let triggerWords: [String]
    public let useSystemInstructions: Bool

    public init(
        title: String,
        promptText: String,
        icon: String,
        description: String,
        triggerWords: [String],
        useSystemInstructions: Bool
    ) {
        self.title = title
        self.promptText = promptText
        self.icon = icon
        self.description = description
        self.triggerWords = triggerWords
        self.useSystemInstructions = useSystemInstructions
    }
}

public enum VoiceInkCustomPromptPolicy {
    public static func startupStoreState(
        loadedPrompts: [VoiceInkCustomPrompt],
        selectedPromptId: UUID?,
        isEnhancementEnabled: Bool
    ) -> VoiceInkCustomPromptStoreState {
        let repairedSelectedPromptId = repairedSelectedPromptId(
            selectedPromptId,
            isEnhancementEnabled: isEnhancementEnabled,
            prompts: loadedPrompts
        )
        return VoiceInkCustomPromptStoreState(
            prompts: repairedPredefinedPrompts(in: loadedPrompts),
            selectedPromptId: repairedSelectedPromptId
        )
    }

    public static func isSaveableCustomPromptDraft(_ draft: VoiceInkCustomPromptDraft) -> Bool {
        !draft.title.isEmpty && !draft.promptText.isEmpty
    }

    public static func customPrompt(from draft: VoiceInkCustomPromptDraft) -> VoiceInkCustomPrompt {
        VoiceInkCustomPrompt(
            title: draft.title,
            promptText: draft.promptText,
            icon: draft.icon,
            description: customPromptDescription(draft.description),
            isPredefined: false,
            triggerWords: draft.triggerWords,
            useSystemInstructions: draft.useSystemInstructions
        )
    }

    public static func prompt(
        _ prompt: VoiceInkCustomPrompt,
        applying draft: VoiceInkCustomPromptDraft
    ) -> VoiceInkCustomPrompt {
        VoiceInkCustomPrompt(
            id: prompt.id,
            title: prompt.isPredefined ? prompt.title : draft.title,
            promptText: prompt.isPredefined ? prompt.promptText : draft.promptText,
            isActive: prompt.isActive,
            icon: prompt.isPredefined ? prompt.icon : draft.icon,
            description: prompt.isPredefined ? prompt.description : customPromptDescription(draft.description),
            isPredefined: prompt.isPredefined,
            triggerWords: draft.triggerWords,
            useSystemInstructions: prompt.isPredefined ? prompt.useSystemInstructions : draft.useSystemInstructions
        )
    }

    public static func addingPrompt(
        _ prompt: VoiceInkCustomPrompt,
        to prompts: [VoiceInkCustomPrompt],
        selectedPromptId: UUID?
    ) -> VoiceInkCustomPromptStoreState {
        let updatedPrompts = prompts + [prompt]
        let updatedSelectedPromptId = updatedPrompts.count == 1 ? prompt.id : selectedPromptId
        return VoiceInkCustomPromptStoreState(prompts: updatedPrompts, selectedPromptId: updatedSelectedPromptId)
    }

    public static func updatingPrompt(
        _ prompt: VoiceInkCustomPrompt,
        in prompts: [VoiceInkCustomPrompt],
        selectedPromptId: UUID?
    ) -> VoiceInkCustomPromptStoreState {
        var updatedPrompts = prompts
        if let index = updatedPrompts.firstIndex(where: { $0.id == prompt.id }) {
            updatedPrompts[index] = prompt
        }

        return VoiceInkCustomPromptStoreState(prompts: updatedPrompts, selectedPromptId: selectedPromptId)
    }

    public static func deletingPrompt(
        _ prompt: VoiceInkCustomPrompt,
        from prompts: [VoiceInkCustomPrompt],
        selectedPromptId: UUID?
    ) -> VoiceInkCustomPromptStoreState {
        let updatedPrompts = prompts.filter { $0.id != prompt.id }
        let updatedSelectedPromptId = selectedPromptId == prompt.id ? updatedPrompts.first?.id : selectedPromptId
        return VoiceInkCustomPromptStoreState(prompts: updatedPrompts, selectedPromptId: updatedSelectedPromptId)
    }

    public static func exportedCustomPrompts(from prompts: [VoiceInkCustomPrompt]) -> [VoiceInkCustomPrompt] {
        prompts.filter { !$0.isPredefined }
    }

    public static func promptsAfterImportingCustomPrompts(
        _ importedPrompts: [VoiceInkCustomPrompt],
        currentPrompts: [VoiceInkCustomPrompt]
    ) -> [VoiceInkCustomPrompt] {
        currentPrompts.filter { $0.isPredefined } + importedPrompts
    }

    public static func selectedPromptIdAfterEnablingEnhancement(
        _ selectedPromptId: UUID?,
        prompts: [VoiceInkCustomPrompt]
    ) -> UUID? {
        selectedPromptId ?? prompts.first?.id
    }

    public static func settingsStateAfterEnhancementEnabledChange(
        _ state: VoiceInkAIEnhancementPromptSettingsState,
        prompts: [VoiceInkCustomPrompt]
    ) -> VoiceInkAIEnhancementPromptSettingsState {
        guard state.isEnhancementEnabled else {
            return state
        }

        return VoiceInkAIEnhancementPromptSettingsState(
            isEnhancementEnabled: true,
            selectedPromptId: selectedPromptIdAfterEnablingEnhancement(
                state.selectedPromptId,
                prompts: prompts
            )
        )
    }

    public static func repairedSelectedPromptId(
        _ selectedPromptId: UUID?,
        isEnhancementEnabled: Bool,
        prompts: [VoiceInkCustomPrompt]
    ) -> UUID? {
        guard isEnhancementEnabled else {
            return selectedPromptId
        }

        guard let selectedPromptId,
              prompts.contains(where: { $0.id == selectedPromptId }) else {
            return prompts.first?.id
        }

        return selectedPromptId
    }

    public static func basePromptText(
        activePrompt: VoiceInkCustomPrompt?,
        prompts: [VoiceInkCustomPrompt],
        assistantPromptId: UUID = VoiceInkPredefinedPrompts.assistantPromptId,
        defaultPromptId: UUID = VoiceInkPredefinedPrompts.defaultPromptId
    ) -> String {
        if let activePrompt {
            if activePrompt.id == assistantPromptId {
                return activePrompt.promptText
            }

            return activePrompt.finalPromptText
        }

        let defaultPrompt = prompts.first { $0.id == defaultPromptId } ?? prompts.first
        return defaultPrompt?.finalPromptText ?? ""
    }

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

    private static func customPromptDescription(_ description: String) -> String? {
        description.isEmpty ? nil : description
    }
}
