import Foundation

public struct VoiceInkCustomPromptTriggerSummary: Equatable, Sendable {
    public let iconSystemName: String
    public let text: String

    public init(iconSystemName: String, text: String) {
        self.iconSystemName = iconSystemName
        self.text = text
    }
}

public enum VoiceInkCustomPromptPresentation {
    public static let defaultIconSystemName = "doc.text.fill"
    public static let defaultPromptFallbackIconSystemName = "checkmark.seal.fill"
    public static let triggerSummaryIconSystemName = "mic.fill"
    public static let addPromptTitle = "Add New"
    public static let addPromptSystemImageName = "plus.circle.fill"
    public static let editActionTitle = "Edit"
    public static let editActionSystemImageName = "pencil"
    public static let deleteActionTitle = "Delete"
    public static let deleteActionSystemImageName = "trash"
    public static let cancelActionTitle = "Cancel"
    public static let deletePromptConfirmationTitle = "Delete Prompt?"
    public static let promptGridEmptyText = "No prompts available"
    public static let promptGridInfoSystemImageName = "info.circle"
    public static let promptGridHelpText = "Double-click to edit • Right-click for more options"
    public static let addPromptHelpText = "Add new prompt"
    public static let closeHelpText = "Close"
    public static let closeSystemImageName = "xmark"
    public static let saveChangesButtonTitle = "Save Changes"
    public static let addEditorTitle = "New Prompt"
    public static let editEditorTitle = "Edit Prompt"
    public static let predefinedEditorTitle = "Edit Trigger Words"
    public static let predefinedPromptRestrictionText = "You can only customize the trigger words for system prompts."
    public static let promptNamePlaceholder = "Prompt Name"
    public static let descriptionPlaceholder = "Brief description"
    public static let detailsSectionTitle = "Details"
    public static let promptInstructionsPlaceholder = "Enter your custom prompt instructions here..."
    public static let useSystemTemplateTitle = "Use System Template"
    public static let useSystemTemplateHelpText = "If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users)."
    public static let instructionsSectionTitle = "Instructions"
    public static let triggerWordsSectionTitle = "Trigger Words"
    public static let triggerWordsHelpText = "Add words that automatically activate this prompt. For example, 'summarize', 'email', 'translate'."
    public static let startWithTemplateTitle = "Start with Template"
    public static let startWithTemplateIconSystemName = "sparkles"
    public static let triggerWordPlaceholder = "Add trigger word"
    public static let addTriggerWordSystemImageName = "plus.circle.fill"
    public static let removeTriggerWordSystemImageName = "xmark"
    public static let noTriggerWordsText = "No trigger words added"

    public static let iconSystemNames: [String] = [
        "doc.text.fill",
        "textbox",
        "checkmark.seal.fill",
        "bubble.left.and.bubble.right.fill",
        "message.fill",
        "envelope.fill",
        "person.2.fill",
        "person.wave.2.fill",
        "briefcase.fill",
        "curlybraces",
        "terminal.fill",
        "gearshape.fill",
        "doc.text.image.fill",
        "note",
        "book.fill",
        "bookmark.fill",
        "pencil.circle.fill",
        "video.fill",
        "mic.fill",
        "music.note",
        "photo.fill",
        "paintbrush.fill",
        "clock.fill",
        "calendar",
        "list.bullet",
        "checkmark.circle.fill",
        "timer",
        "hourglass",
        "star.fill",
        "flag.fill",
        "tag.fill",
        "folder.fill",
        "paperclip",
        "tray.fill",
        "chart.bar.fill",
        "flame.fill",
        "target",
        "list.clipboard.fill",
        "brain.head.profile",
        "lightbulb.fill",
        "megaphone.fill",
        "heart.fill",
        "map.fill",
        "house.fill",
        "camera.fill",
        "figure.walk",
        "dumbbell.fill",
        "cart.fill",
        "creditcard.fill",
        "graduationcap.fill",
        "airplane",
        "leaf.fill",
        "hand.raised.fill",
        "hand.thumbsup.fill"
    ]

    public static func editorTitle(isEditingPredefinedPrompt: Bool, isAddingPrompt: Bool) -> String {
        if isEditingPredefinedPrompt {
            return predefinedEditorTitle
        }

        return isAddingPrompt ? addEditorTitle : editEditorTitle
    }

    public static func editingHeaderTitle(for promptTitle: String) -> String {
        "Editing: \(promptTitle)"
    }

    public static func deletePromptConfirmationMessage(promptTitle: String) -> String {
        "Are you sure you want to delete '\(promptTitle)' prompt? This action cannot be undone."
    }

    public static func triggerSummary(for triggerWords: [String]) -> VoiceInkCustomPromptTriggerSummary? {
        guard let firstTrigger = triggerWords.first else {
            return nil
        }

        let text = triggerWords.count == 1
            ? "\"\(firstTrigger)...\""
            : "\"\(firstTrigger)...\" +\(triggerWords.count - 1)"

        return VoiceInkCustomPromptTriggerSummary(
            iconSystemName: triggerSummaryIconSystemName,
            text: text
        )
    }
}

public struct VoiceInkTemplatePrompt: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let promptText: String
    public let icon: String
    public let description: String

    public init(id: String, title: String, promptText: String, icon: String, description: String) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.icon = icon
        self.description = description
    }
}

public enum VoiceInkPromptTemplates {
    public static var macTemplates: [VoiceInkTemplatePrompt] {
        [
            VoiceInkTemplatePrompt(
                id: "system-default",
                title: "System Default",
                promptText: """
                    - Clean up the <TRANSCRIPT> text for clarity and natural flow while preserving meaning and the original tone.
                    - Use informal, plain language unless the <TRANSCRIPT> clearly uses a professional tone; in that case, match it.
                    - Fix obvious grammar, remove fillers and stutters, collapse repetitions, and keep names and numbers.
                    - Handle backtracking and self-corrections: When the speaker corrects themselves mid-sentence using phrases like "scratch that", "actually", "sorry not that", "I mean", "wait no", or similar corrections, remove the incorrect part and keep only the corrected version. Example: "The meeting is on Tuesday, sorry not that, actually Wednesday" → "The meeting is on Wednesday."
                    - Respect formatting commands: When the speaker explicitly says "new line" or "new paragraph", insert the appropriate line break or paragraph break at that point.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Apply smart formatting: Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20'), convert common abbreviations to proper format (e.g., 'vs' → 'vs.', 'etc' → 'etc.'), and format dates, times, and measurements consistently.
                    - Keep the original intent and nuance.
                    - Organize into short paragraphs of 2–4 sentences for readability.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the cleaned text.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "checkmark.seal.fill",
                description: "Default system prompt"
            ),
            VoiceInkTemplatePrompt(
                id: "chat",
                title: "Chat",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text as a chat message: informal, concise, and conversational.
                    - Keep emotive markers and emojis if present; don't invent new ones.
                    - Lightly fix grammar, remove fillers and repeated words, and improve flow without changing meaning.
                    - Keep the original tone; only be professional if the <TRANSCRIPT> already is.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Format like a modern chat message - short lines, natural breaks, emoji-friendly.
                    - Do not add greetings, sign-offs, or commentary.
                    - Output only the chat message.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "bubble.left.and.bubble.right.fill",
                description: "Casual chat-style formatting"
            ),
            VoiceInkTemplatePrompt(
                id: "email",
                title: "Email",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text as a complete email with proper formatting: include a greeting (Hi), body paragraphs (2-4 sentences each), and closing (Thanks).
                    - Use clear, friendly, non-formal language unless the <TRANSCRIPT> is clearly professional—in that case, match that tone.
                    - Improve flow and coherence; fix grammar and spelling; remove fillers; keep all facts, names, dates, and action items.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Do not invent new content, but structure it as a proper email format.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "envelope.fill",
                description: "Professional email formatting"
            ),
            VoiceInkTemplatePrompt(
                id: "rewrite",
                title: "Rewrite",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text with enhanced clarity, improved sentence structure, and rhythmic flow while preserving the original meaning and tone.
                    - Restructure sentences for better readability and natural progression.
                    - Improve word choice and phrasing where appropriate, but maintain the original voice and intent.
                    - Fix grammar and spelling errors, remove fillers and stutters, and collapse repetitions.
                    - Format any lists as proper bullet points or numbered lists.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Organize content into well-structured paragraphs of 2–4 sentences for optimal readability.
                    - Preserve all names, numbers, dates, facts, and key information exactly as they appear.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the rewritten text.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "pencil.circle.fill",
                description: "Rewrites with better clarity."
            )
        ]
    }

    public static func macTemplate(named title: String) -> VoiceInkTemplatePrompt? {
        macTemplates.first { $0.title == title }
    }
}

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
    public var title: String
    public var promptText: String
    public var icon: String
    public var description: String
    public var triggerWords: [String]
    public var useSystemInstructions: Bool

    public static let newPrompt = VoiceInkCustomPromptDraft(
        title: "",
        promptText: "",
        icon: VoiceInkCustomPromptPresentation.defaultIconSystemName,
        description: "",
        triggerWords: [],
        useSystemInstructions: true
    )

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

    public init(prompt: VoiceInkCustomPrompt) {
        self.init(
            title: prompt.title,
            promptText: prompt.promptText,
            icon: prompt.icon,
            description: prompt.description ?? "",
            triggerWords: prompt.triggerWords,
            useSystemInstructions: prompt.useSystemInstructions
        )
    }

    public var isSaveable: Bool {
        VoiceInkCustomPromptPolicy.isSaveableCustomPromptDraft(self)
    }

    public var customPrompt: VoiceInkCustomPrompt {
        VoiceInkCustomPromptPolicy.customPrompt(from: self)
    }

    public func applying(to prompt: VoiceInkCustomPrompt) -> VoiceInkCustomPrompt {
        VoiceInkCustomPromptPolicy.prompt(prompt, applying: self)
    }

    public func applyingTemplate(_ template: VoiceInkTemplatePrompt) -> Self {
        VoiceInkCustomPromptDraft(
            title: template.title,
            promptText: template.promptText,
            icon: template.icon,
            description: template.description,
            triggerWords: triggerWords,
            useSystemInstructions: useSystemInstructions
        )
    }
}

public enum VoiceInkCustomPromptEditorSavePlan: Equatable, Sendable {
    case add(VoiceInkCustomPrompt)
    case update(VoiceInkCustomPrompt)

    public func applyRuntimeState(
        addPrompt: (VoiceInkCustomPrompt) -> Void,
        updatePrompt: (VoiceInkCustomPrompt) -> Void
    ) {
        switch self {
        case .add(let prompt):
            addPrompt(prompt)
        case .update(let prompt):
            updatePrompt(prompt)
        }
    }
}

public struct VoiceInkCustomPromptEditorContext: Equatable, Sendable {
    private let prompt: VoiceInkCustomPrompt?

    public init(prompt: VoiceInkCustomPrompt? = nil) {
        self.prompt = prompt
    }

    public static let add = VoiceInkCustomPromptEditorContext()

    public static func edit(prompt: VoiceInkCustomPrompt) -> VoiceInkCustomPromptEditorContext {
        VoiceInkCustomPromptEditorContext(prompt: prompt)
    }

    public var initialDraft: VoiceInkCustomPromptDraft {
        prompt.map { VoiceInkCustomPromptDraft(prompt: $0) } ?? .newPrompt
    }

    public var isAddingPrompt: Bool {
        prompt == nil
    }

    public var isEditingPredefinedPrompt: Bool {
        prompt?.isPredefined == true
    }

    public var shouldShowPredefinedPromptForm: Bool {
        isEditingPredefinedPrompt
    }

    public var shouldShowTemplateSection: Bool {
        isAddingPrompt
    }

    public var editorTitle: String {
        VoiceInkCustomPromptPresentation.editorTitle(
            isEditingPredefinedPrompt: isEditingPredefinedPrompt,
            isAddingPrompt: isAddingPrompt
        )
    }

    public func isSaveButtonDisabled(for draft: VoiceInkCustomPromptDraft) -> Bool {
        isEditingPredefinedPrompt ? false : !draft.isSaveable
    }

    public func savePlan(for draft: VoiceInkCustomPromptDraft) -> VoiceInkCustomPromptEditorSavePlan {
        guard let prompt else {
            return .add(draft.customPrompt)
        }

        return .update(draft.applying(to: prompt))
    }
}

public struct VoiceInkCustomPromptBackupImportPlan: Equatable, Sendable {
    private let importedPrompts: [VoiceInkCustomPrompt]
    fileprivate let promptsAfterImport: [VoiceInkCustomPrompt]

    public init(
        importedPrompts: [VoiceInkCustomPrompt],
        currentPrompts: [VoiceInkCustomPrompt]
    ) {
        self.importedPrompts = importedPrompts
        self.promptsAfterImport = currentPrompts.filter { $0.isPredefined } + importedPrompts
    }

    public func applyRuntimeState(
        setPrompts: ([VoiceInkCustomPrompt]) -> Void,
        reportImportedPromptCount: (Int) -> Void
    ) {
        setPrompts(promptsAfterImport)
        reportImportedPromptCount(importedPrompts.count)
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
        customPromptBackupImportPlan(
            importedPrompts: importedPrompts,
            currentPrompts: currentPrompts
        ).promptsAfterImport
    }

    public static func customPromptBackupImportPlan(
        importedPrompts: [VoiceInkCustomPrompt],
        currentPrompts: [VoiceInkCustomPrompt]
    ) -> VoiceInkCustomPromptBackupImportPlan {
        VoiceInkCustomPromptBackupImportPlan(
            importedPrompts: importedPrompts,
            currentPrompts: currentPrompts
        )
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

    public static func settingsStateAfterAPIKeyValidityChange(
        _ state: VoiceInkAIEnhancementPromptSettingsState,
        isAPIKeyValid: Bool
    ) -> VoiceInkAIEnhancementPromptSettingsState? {
        guard !isAPIKeyValid else {
            return nil
        }

        return VoiceInkAIEnhancementPromptSettingsState(
            isEnhancementEnabled: false,
            selectedPromptId: state.selectedPromptId
        )
    }

    public static func settingsStateAfterPromptShortcutSelection(
        index: Int,
        current state: VoiceInkAIEnhancementPromptSettingsState,
        prompts: [VoiceInkCustomPrompt]
    ) -> VoiceInkAIEnhancementPromptSettingsState? {
        guard prompts.indices.contains(index) else {
            return nil
        }

        let selectedPromptId = prompts[index].id
        if state.isEnhancementEnabled && state.selectedPromptId == selectedPromptId {
            return state
        }

        return VoiceInkAIEnhancementPromptSettingsState(
            isEnhancementEnabled: true,
            selectedPromptId: selectedPromptId
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

    public static func activePrompt(
        selectedPromptId: UUID?,
        prompts: [VoiceInkCustomPrompt]
    ) -> VoiceInkCustomPrompt? {
        guard let selectedPromptId else {
            return nil
        }

        return prompts.first { $0.id == selectedPromptId }
    }

    public static func activePromptIcon(
        selectedPromptId: UUID?,
        prompts: [VoiceInkCustomPrompt],
        defaultPromptId: UUID = VoiceInkPredefinedPrompts.defaultPromptId,
        predefinedPrompts: [VoiceInkPredefinedPrompt] = VoiceInkPredefinedPrompts.all
    ) -> String {
        if let activePrompt = activePrompt(selectedPromptId: selectedPromptId, prompts: prompts) {
            return activePrompt.icon
        }

        return prompts.first { $0.id == defaultPromptId }?.icon
            ?? predefinedPrompts.first { $0.id == defaultPromptId }?.icon
            ?? VoiceInkCustomPromptPresentation.defaultPromptFallbackIconSystemName
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
