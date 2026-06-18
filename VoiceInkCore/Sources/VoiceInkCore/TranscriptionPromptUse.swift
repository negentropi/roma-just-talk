import Foundation

public enum VoiceInkTranscriptionPromptUse: Equatable, Sendable {
    case recordedFileTranscription(VoiceInkProviderKind)
    case streamingTranscription(VoiceInkProviderKind)
    case directTranscription

    public func requestPrompt(_ prompt: String?) -> String? {
        guard acceptsPrompt else { return nil }
        return Self.nonBlankRequestPrompt(prompt)
    }

    public static func nonBlankRequestPrompt(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt
    }

    private var acceptsPrompt: Bool {
        switch self {
        case .recordedFileTranscription(let provider):
            return provider.transcriptionTransport == .openAICompatible
                || provider == .assemblyAI
                || provider == .localWhisper
        case .streamingTranscription(.assemblyAI),
             .directTranscription:
            return true
        case .streamingTranscription:
            return false
        }
    }
}
