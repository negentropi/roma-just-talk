public enum VoiceInkAIRequestPrompts {
    public static let postProcessingSystemPrompt = "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."

    public static func taggedTranscript(_ text: String) -> String {
        "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
    }

    public static func postProcessingUserPrompt(prompt: String, transcript: String) -> String {
        "Prompt: \(prompt)\n\nTranscript:\n\(transcript)"
    }
}

public struct VoiceInkAIEnhancementRequestPayload: Equatable, Sendable {
    public let userMessage: String

    public init?(transcript: String) {
        guard !transcript.isEmpty else {
            return nil
        }

        self.userMessage = VoiceInkAIRequestPrompts.taggedTranscript(transcript)
    }

    public static func enhancedText(from providerOutput: String) -> String {
        VoiceInkAIEnhancementOutputFilter.filter(providerOutput)
    }
}

public enum VoiceInkAIEnhancementRequestPreparation: Equatable, Sendable {
    case skipEmptyTranscript
    case execute(VoiceInkAIEnhancementRequestPayload)

    public static func preparing(
        transcript: String,
        isConfigured: Bool
    ) throws -> VoiceInkAIEnhancementRequestPreparation {
        guard isConfigured else {
            throw VoiceInkAIEnhancementError.notConfigured
        }

        guard let requestPayload = VoiceInkAIEnhancementRequestPayload(transcript: transcript) else {
            return .skipEmptyTranscript
        }

        return .execute(requestPayload)
    }
}
