import Foundation

public enum VoiceInkDictationMode: Equatable, Sendable {
    case voice
    case voiceAndLips
    case lips

    public var usesMicrophone: Bool { self != .lips }
    public var usesCamera: Bool { self != .voice }
}

public enum VoiceInkLipDictationPreference {
    public static let enabledKey = "LipDictationEnabled"
    public static let lipOnlyKey = "LipDictationLipOnly"

    public static var registeredDefaults: [String: Any] {
        [enabledKey: false, lipOnlyKey: false]
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }

    public static func isLipOnly(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: lipOnlyKey) as? Bool ?? false
    }

    public static func mode(in defaults: UserDefaults = .standard) -> VoiceInkDictationMode {
        guard isEnabled(from: defaults) else { return .voice }
        return isLipOnly(from: defaults) ? .lips : .voiceAndLips
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: enabledKey)
    }

    public static func saveLipOnly(_ lipOnly: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(lipOnly, forKey: lipOnlyKey)
    }
}
