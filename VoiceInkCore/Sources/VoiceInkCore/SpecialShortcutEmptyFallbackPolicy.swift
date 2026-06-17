import Foundation

public enum VoiceInkSpecialShortcutEmptyFallbackPolicy {
    public static let emptyTapThreshold: TimeInterval = 0.32
    public static let fallbackLifetime: TimeInterval = 30

    public static func shouldScheduleFallback(
        pressDuration: TimeInterval,
        threshold: TimeInterval = emptyTapThreshold
    ) -> Bool {
        pressDuration < threshold
    }

    public static func shouldConsumeFallback(
        createdAt: Date,
        now: Date = Date(),
        transcriptionStatus: VoiceInkTranscriptionStatus?,
        rawText: String,
        enhancedText: String?,
        lifetime: TimeInterval = fallbackLifetime
    ) -> Bool {
        guard now.timeIntervalSince(createdAt) <= lifetime else { return false }
        guard transcriptionStatus == .completed else { return false }
        guard rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard enhancedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return false }
        return true
    }
}
