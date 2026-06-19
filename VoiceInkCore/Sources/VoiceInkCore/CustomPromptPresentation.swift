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
