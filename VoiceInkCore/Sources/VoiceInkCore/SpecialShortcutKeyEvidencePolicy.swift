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
