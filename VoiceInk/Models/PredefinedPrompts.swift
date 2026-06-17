import Foundation
import VoiceInkCore

enum PredefinedPrompts {
    static let defaultPromptId = VoiceInkPredefinedPrompts.defaultPromptId
    static let assistantPromptId = VoiceInkPredefinedPrompts.assistantPromptId
    
    static var all: [CustomPrompt] {
        createDefaultPrompts()
    }
    
    static func createDefaultPrompts() -> [CustomPrompt] {
        VoiceInkPredefinedPrompts.all.map(CustomPrompt.init(predefinedPrompt:))
    }
}

private extension CustomPrompt {
    init(predefinedPrompt: VoiceInkPredefinedPrompt) {
        self.init(
            id: predefinedPrompt.id,
            title: predefinedPrompt.title,
            promptText: predefinedPrompt.promptText,
            icon: predefinedPrompt.icon,
            description: predefinedPrompt.description,
            isPredefined: true,
            useSystemInstructions: predefinedPrompt.useSystemInstructions
        )
    }
}
