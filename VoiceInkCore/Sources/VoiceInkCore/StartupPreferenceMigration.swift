import Foundation

public enum VoiceInkStartupPreferenceMigrationPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

public enum VoiceInkStartupPreferenceMigration {
    public static func migrateLegacyPreferences(
        for platform: VoiceInkStartupPreferenceMigrationPlatform,
        in defaults: UserDefaults = .standard
    ) {
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded(in: defaults)

        switch platform {
        case .iOS:
            break
        case .macOS:
            VoiceInkPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)
        }
    }
}
