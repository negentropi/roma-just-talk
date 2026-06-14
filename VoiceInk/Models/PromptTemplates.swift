import Foundation
import VoiceInkCore

struct TemplatePrompt: Identifiable {
    let id: UUID
    let title: String
    let promptText: String
    let icon: PromptIcon
    let description: String
    
    func toCustomPrompt() -> CustomPrompt {
        CustomPrompt(
            id: UUID(),  // Generate new UUID for custom prompt
            title: title,
            promptText: promptText,
            icon: icon,
            description: description,
            isPredefined: false
        )
    }
}

enum PromptTemplates {
    static var all: [TemplatePrompt] {
        createTemplatePrompts()
    }

    
    static func createTemplatePrompts() -> [TemplatePrompt] {
        VoiceInkPromptTemplates.macTemplates.map { template in
            TemplatePrompt(
                id: UUID(),
                title: template.title,
                promptText: template.promptText,
                icon: template.icon,
                description: template.description
            )
        }
    }
}
