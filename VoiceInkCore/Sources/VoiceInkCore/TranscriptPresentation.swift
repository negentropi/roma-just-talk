import Foundation

public extension VoiceInkTranscriptionStatus {
    var needsTranscription: Bool {
        self == .pending || self == .failed
    }
}

public enum VoiceInkTranscriptPresentation {
    public static func preferredText(rawText: String, enhancedText: String?) -> String? {
        if let enhancedText, !enhancedText.isEmpty {
            return enhancedText
        }
        if !rawText.isEmpty {
            return rawText
        }
        return nil
    }

    public static func matchesSearch(rawText: String, enhancedText: String?, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        return rawText.localizedCaseInsensitiveContains(query) ||
            (enhancedText?.localizedCaseInsensitiveContains(query) ?? false)
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
        switch status {
        case .pending:
            return "Transcription Pending"
        case .failed:
            return "Transcription Failed"
        case .completed, .canceled:
            return nil
        }
    }

    public static func statusBadgeText(for status: VoiceInkTranscriptionStatus) -> String? {
        switch status {
        case .pending:
            return "Processing"
        case .failed:
            return "Failed"
        case .completed, .canceled:
            return nil
        }
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
