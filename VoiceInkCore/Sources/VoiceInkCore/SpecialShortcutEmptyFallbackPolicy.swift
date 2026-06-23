import Foundation

public struct VoiceInkShortcutPressContext: Equatable, Sendable {
    public var didPressOtherKeyDuringPress: Bool
    public var didReleaseOtherKeyDuringPress: Bool
    public var hasReliableKeyEvidence: Bool

    public init(
        didPressOtherKeyDuringPress: Bool = false,
        didReleaseOtherKeyDuringPress: Bool = false,
        hasReliableKeyEvidence: Bool = true
    ) {
        self.didPressOtherKeyDuringPress = didPressOtherKeyDuringPress
        self.didReleaseOtherKeyDuringPress = didReleaseOtherKeyDuringPress
        self.hasReliableKeyEvidence = hasReliableKeyEvidence
    }
}

public enum VoiceInkSpecialShortcutKeyEvidencePolicy {
    public static func shouldDiscardShortcut(for context: VoiceInkShortcutPressContext) -> Bool {
        context.didPressOtherKeyDuringPress ||
        context.didReleaseOtherKeyDuringPress ||
        !context.hasReliableKeyEvidence
    }
}

public enum VoiceInkRecordingShortcutTimingPolicy {
    public static let pressCooldown: TimeInterval = 0.08
    public static let hybridPushToTalkThreshold: TimeInterval = 0.5

    public static func isPressWithinCooldown(
        lastPressTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastPressTime else { return false }
        return now.timeIntervalSince(lastPressTime) < pressCooldown
    }

    public static func shouldStopHybridRecording(
        pressDuration: TimeInterval,
        recordingState: VoiceInkRecordingState
    ) -> Bool {
        pressDuration >= hybridPushToTalkThreshold && recordingState == .recording
    }

    public static func sleepNanoseconds(delaySeconds: TimeInterval) -> UInt64 {
        guard delaySeconds.isFinite else { return 0 }
        let safeDelay = max(delaySeconds, 0)
        let nanoseconds = (safeDelay * 1_000_000_000).rounded()
        guard nanoseconds.isFinite, nanoseconds < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(nanoseconds)
    }
}

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
