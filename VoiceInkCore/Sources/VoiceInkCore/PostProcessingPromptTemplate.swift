import Foundation

public enum VoiceInkPostProcessingTemplateType: String, CaseIterable, Codable, Sendable {
    case custom = "Custom"
    case summary = "Summary"
    case keyPoints = "Key Points"
    case rewrite = "Rewrite"
    case transcriptCleanup = "Clean Transcript"

    public var displayName: String {
        rawValue
    }

    public var prompt: String {
        switch self {
        case .custom:
            return ""
        case .summary:
            return "Please provide a concise summary of the following transcription, capturing the main points and key information in a clear and organized manner:"
        case .keyPoints:
            return "Please extract the key points from the following transcription and present them as a bulleted list, highlighting the most important information:"
        case .rewrite:
            return "Please rewrite the following transcription to improve clarity, grammar, and flow while preserving the original meaning and intent:"
        case .transcriptCleanup:
            return "Please clean up the following transcription by correcting any errors, removing filler words, and improving readability while maintaining the speaker's original meaning and tone:"
        }
    }
}

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
