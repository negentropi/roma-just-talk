import Foundation

public struct VoiceInkPostProcessingPromptTemplate: Identifiable, Codable, Sendable {
    public let id = UUID()
    public var type: VoiceInkPostProcessingTemplateType
    public var customPrompt: String

    private enum CodingKeys: String, CodingKey {
        case type
        case customPrompt
    }

    public init(type: VoiceInkPostProcessingTemplateType, customPrompt: String = "") {
        self.type = type
        self.customPrompt = customPrompt
    }

    public var effectivePrompt: String {
        switch type {
        case .custom:
            return customPrompt
        default:
            return type.prompt
        }
    }

    public var description: String {
        switch type {
        case .custom:
            return customPrompt.isEmpty ? "Custom prompt (empty)" : "Custom: \(customPrompt.prefix(50))..."
        default:
            return type.displayName
        }
    }
}
