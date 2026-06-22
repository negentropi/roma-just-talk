import Foundation

public enum VoiceInkLastTranscriptionTextPreference: Equatable, Sendable {
    case original
    case preferred
}

public struct VoiceInkLastTranscriptionNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let kind: VoiceInkAppNotificationKind

    public init(title: String, kind: VoiceInkAppNotificationKind) {
        self.title = title
        self.kind = kind
    }
}

public enum VoiceInkLastTranscriptionRetryPreflightFailure: Equatable, Sendable {
    case missingAudio
    case noTranscriptionModelSelected
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
    public static let noTranscriptionNotification = VoiceInkLastTranscriptionNotificationPresentation(
        title: VoiceInkTranscriptPresentation.noTranscriptionAvailableTitle,
        kind: .error
    )

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

    public static func copyCompletionNotification(
        didCopy: Bool
    ) -> VoiceInkLastTranscriptionNotificationPresentation {
        VoiceInkLastTranscriptionNotificationPresentation(
            title: didCopy
                ? VoiceInkTranscriptPresentation.lastTranscriptionCopiedTitle
                : VoiceInkTranscriptPresentation.failedToCopyTranscriptionTitle,
            kind: didCopy ? .success : .error
        )
    }

    public static func retryPreflightFailureNotification(
        _ failure: VoiceInkLastTranscriptionRetryPreflightFailure
    ) -> VoiceInkLastTranscriptionNotificationPresentation {
        switch failure {
        case .missingAudio:
            return VoiceInkLastTranscriptionNotificationPresentation(
                title: VoiceInkTranscriptPresentation.cannotRetryTitle(
                    errorDescription: VoiceInkErrorDescription.text(for: VoiceInkEngineError.audioFileNotFound)
                ),
                kind: .error
            )
        case .noTranscriptionModelSelected:
            return VoiceInkLastTranscriptionNotificationPresentation(
                title: VoiceInkErrorDescription.text(for: VoiceInkEngineError.noTranscriptionModelSelected),
                kind: .error
            )
        }
    }

    public static let retrySuccessNotification = VoiceInkLastTranscriptionNotificationPresentation(
        title: VoiceInkTranscriptPresentation.copiedToClipboardTitle,
        kind: .success
    )

    public static func retryFailureNotification(
        errorDescription: String
    ) -> VoiceInkLastTranscriptionNotificationPresentation {
        VoiceInkLastTranscriptionNotificationPresentation(
            title: VoiceInkTranscriptPresentation.retryFailedTitle(errorDescription: errorDescription),
            kind: .error
        )
    }

    public static func retryFailureNotification(
        for error: Error
    ) -> VoiceInkLastTranscriptionNotificationPresentation {
        retryFailureNotification(errorDescription: VoiceInkErrorDescription.text(for: error))
    }
}
