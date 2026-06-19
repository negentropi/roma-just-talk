import Foundation

public enum VoiceInkAppIdentity {
    public static let bundleIdentifier = "com.prakashjoshipax.VoiceInk"
    public static let displayName = "roma just talk"
    public static let compactDisplayName = "roma-just-talk"
    public static let sidebarSubtitle = "speak before hotkey"

    public static var welcomeTitle: String {
        "Welcome to \(displayName)"
    }

    public static var startUsingTitle: String {
        "Start Using \(displayName)"
    }

    public static var onboardingWindowTitle: String {
        "\(compactDisplayName) Onboarding"
    }

    public static var storageFailureMessage: String {
        "\(compactDisplayName) cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
    }

    public static func macOSApplicationSupportDirectory(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }
}
