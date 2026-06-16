import Foundation
import VoiceInkCore

typealias PromptTemplateType = VoiceInkPostProcessingTemplateType

struct PromptTemplate: Identifiable, Codable {
    let id = UUID()
    let type: PromptTemplateType
    let customPrompt: String // Only used when type is .custom
    
    init(type: PromptTemplateType, customPrompt: String = "") {
        self.type = type
        self.customPrompt = customPrompt
    }
    
    /// Returns the effective prompt to use for post-processing
    var effectivePrompt: String {
        switch type {
        case .custom:
            return customPrompt
        default:
            return type.prompt
        }
    }
    
    /// Returns a display-friendly description of the template
    var description: String {
        switch type {
        case .custom:
            return customPrompt.isEmpty ? "Custom prompt (empty)" : "Custom: \(customPrompt.prefix(50))..."
        default:
            return type.displayName
        }
    }
}
