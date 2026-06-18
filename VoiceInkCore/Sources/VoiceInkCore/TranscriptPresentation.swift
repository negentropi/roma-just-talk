import Foundation

public extension VoiceInkTranscriptionStatus {
    var needsTranscription: Bool {
        self == .pending || self == .failed
    }
}

public struct VoiceInkTranscriptStatusPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case processing
        case failed
    }

    public enum Tone: Equatable, Sendable {
        case processing
        case failure
    }

    public let kind: Kind
    public let title: String
    public let badgeText: String

    public var isProcessing: Bool {
        kind == .processing
    }

    public var isFailure: Bool {
        kind == .failed
    }

    public var tone: Tone {
        switch kind {
        case .processing:
            return .processing
        case .failed:
            return .failure
        }
    }

    public var panelSystemImageName: String {
        switch kind {
        case .processing:
            return "clock.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    public var shouldShowInlineProgress: Bool {
        kind == .processing
    }

    public var shouldShowBadge: Bool {
        kind == .failed
    }

    public init(kind: Kind, title: String, badgeText: String) {
        self.kind = kind
        self.title = title
        self.badgeText = badgeText
    }
}

public enum VoiceInkTranscriptPresentation {
    public static let pendingDisplayText = "New transcription"
    public static let failedDisplayText = "Transcription failed - tap to retry"
    public static let canceledDisplayText = "Transcription canceled"
    public static let emptyCompletedDisplayText = "No audible content detected."
    public static let emptyPreferredText = "No content available."
    public static let canceledTranscriptionText = "The transcription was canceled."

    public static func preferredText(rawText: String, enhancedText: String?) -> String? {
        if let enhancedText, !enhancedText.isEmpty {
            return enhancedText
        }
        if !rawText.isEmpty {
            return rawText
        }
        return nil
    }

    public static func preferredTextOrEmptyContent(rawText: String, enhancedText: String?) -> String {
        preferredText(rawText: rawText, enhancedText: enhancedText) ?? emptyPreferredText
    }

    public static func failedTranscriptText(reason: String) -> String {
        "Transcription Failed: \(reason)"
    }

    public static func matchesSearch(rawText: String, enhancedText: String?, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        return rawText.localizedStandardContains(query) ||
            (enhancedText?.localizedStandardContains(query) ?? false)
    }

    public static func displayText(
        status: VoiceInkTranscriptionStatus,
        rawText: String,
        enhancedText: String?
    ) -> String {
        displayText(
            status: status,
            rawText: rawText,
            enhancedText: enhancedText,
            pendingText: pendingDisplayText,
            failedText: failedDisplayText,
            canceledText: canceledDisplayText,
            emptyCompletedText: emptyCompletedDisplayText
        )
    }

    public static func displayText(
        status: VoiceInkTranscriptionStatus,
        rawText: String,
        enhancedText: String?,
        pendingText: String,
        failedText: String,
        canceledText: String,
        emptyCompletedText: String
    ) -> String {
        switch status {
        case .pending:
            return pendingText
        case .failed:
            return failedText
        case .canceled:
            return canceledText
        case .completed:
            return preferredText(rawText: rawText, enhancedText: enhancedText) ?? emptyCompletedText
        }
    }

    public static func statusTitle(for status: VoiceInkTranscriptionStatus) -> String? {
        statusPresentation(for: status)?.title
    }

    public static func statusBadgeText(for status: VoiceInkTranscriptionStatus) -> String? {
        statusPresentation(for: status)?.badgeText
    }

    public static func statusPresentation(
        for status: VoiceInkTranscriptionStatus
    ) -> VoiceInkTranscriptStatusPresentation? {
        switch status {
        case .pending:
            return VoiceInkTranscriptStatusPresentation(
                kind: .processing,
                title: "Transcription Pending",
                badgeText: "Processing"
            )
        case .failed:
            return VoiceInkTranscriptStatusPresentation(
                kind: .failed,
                title: "Transcription Failed",
                badgeText: "Failed"
            )
        case .completed, .canceled:
            return nil
        }
    }

    public static func shouldShowStatusPanel(for status: VoiceInkTranscriptionStatus) -> Bool {
        statusPresentation(for: status) != nil
    }

    public static func shouldShowCompletedContent(for status: VoiceInkTranscriptionStatus) -> Bool {
        status == .completed
    }

    public static func isPasteable(
        rawText: String,
        statusRawValue: String?
    ) -> Bool {
        isPasteable(
            rawText: rawText,
            statusRawValue: statusRawValue,
            canceledText: canceledTranscriptionText
        )
    }

    public static func isPasteable(
        rawText: String,
        statusRawValue: String?,
        canceledText: String
    ) -> Bool {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty &&
            trimmedText != canceledText &&
            (statusRawValue == nil || statusRawValue == VoiceInkTranscriptionStatus.completed.rawValue)
    }
}
