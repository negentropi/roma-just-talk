import Foundation

public enum VoiceInkLastTranscriptionTextPreference: Equatable, Sendable {
    case original
    case preferred
}

public struct VoiceInkLastTranscriptionCandidate<ID: Equatable & Sendable>: Equatable, Sendable {
    public let id: ID
    public let rawText: String
    public let enhancedText: String?
    public let status: VoiceInkTranscriptionStatus?

    public init(
        id: ID,
        rawText: String,
        enhancedText: String?,
        status: VoiceInkTranscriptionStatus?
    ) {
        self.id = id
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.status = status
    }
}

public enum VoiceInkLastTranscriptionPolicy {
    public static let fetchLimit = 20

    public static func firstPasteableCandidate<ID: Equatable & Sendable>(
        in candidates: [VoiceInkLastTranscriptionCandidate<ID>],
        excluding excludedID: ID? = nil
    ) -> VoiceInkLastTranscriptionCandidate<ID>? {
        candidates.first { candidate in
            candidate.id != excludedID && VoiceInkTranscriptPresentation.isPasteable(
                rawText: candidate.rawText,
                statusRawValue: candidate.status?.rawValue
            )
        }
    }

    public static func pasteText<ID: Equatable & Sendable>(
        for candidate: VoiceInkLastTranscriptionCandidate<ID>,
        preference: VoiceInkLastTranscriptionTextPreference
    ) -> String {
        switch preference {
        case .original:
            return candidate.rawText
        case .preferred:
            return VoiceInkTranscriptPresentation.preferredText(
                rawText: candidate.rawText,
                enhancedText: candidate.enhancedText
            ) ?? candidate.rawText
        }
    }
}
