import Foundation

public struct RomaIOSRecordingFeedbackPlan: Equatable, Sendable {
    public let playsHaptic: Bool
    public let playsSound: Bool

    public init(playsHaptic: Bool, playsSound: Bool) {
        self.playsHaptic = playsHaptic
        self.playsSound = playsSound
    }
}

public enum RomaIOSRecordingFeedbackPreference {
    public static let hapticFeedbackEnabledKey = "iOSHapticRecordingFeedbackEnabled"
    public static let defaultHapticFeedbackEnabled = true

    public static func isHapticFeedbackEnabled(
        from defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: hapticFeedbackEnabledKey) as? Bool
            ?? defaultHapticFeedbackEnabled
    }

    public static func saveHapticFeedbackEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: hapticFeedbackEnabledKey)
    }

    public static func plan(from defaults: UserDefaults = .standard) -> RomaIOSRecordingFeedbackPlan {
        RomaIOSRecordingFeedbackPlan(
            playsHaptic: isHapticFeedbackEnabled(from: defaults),
            playsSound: defaults.object(
                forKey: RomaRecordingFeedbackPreference.isSoundFeedbackEnabledKey
            ) as? Bool ?? RomaRecordingFeedbackPreference.defaultIsSoundFeedbackEnabled
        )
    }
}
