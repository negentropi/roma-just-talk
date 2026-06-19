import Foundation

public enum VoiceInkAppendTrailingSpacePreference {
    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.appendTrailingSpace) as? Bool
            ?? VoiceInkPreferenceDefault.appendTrailingSpace
    }

    public static func saveIsEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
    }
}

public enum VoiceInkTranscriptionPasteOutputPolicy {
    public static let trialExpiredPrefix = "Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy"

    public static func finalPastedText(
        _ text: String,
        appendTrailingSpace: Bool,
        isTrialExpired: Bool
    ) -> String {
        let textWithLicensePrefix = isTrialExpired
            ? "\(trialExpiredPrefix)\n\n\(text)"
            : text

        return textWithLicensePrefix + (appendTrailingSpace ? " " : "")
    }
}
