import Foundation

public enum VoiceInkPostProcessingFailurePresentation {
    public static let defaultNotificationReasonLimit = 80
    public static let enhancementUnavailableFallbackText = "AI Enhancement is not enabled or configured"

    public static func postProcessingFailureText(reason: String) -> String {
        "Post-processing failed: \(reason)"
    }

    public static func enhancementFailureText(reason: String) -> String {
        "Enhancement failed: \(reason)"
    }

    public static func enhancementUnavailableMessage(
        isEnabled: Bool,
        isConfigured: Bool
    ) -> String? {
        isEnabled && isConfigured ? nil : enhancementUnavailableFallbackText
    }

    public static func enhancementFailureNotificationTitle(
        reason: String,
        reasonLimit: Int = defaultNotificationReasonLimit
    ) -> String {
        "Enhancement failed: \(String(reason.prefix(max(0, reasonLimit))))"
    }
}
