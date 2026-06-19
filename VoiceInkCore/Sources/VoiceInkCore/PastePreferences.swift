import Foundation

public enum VoiceInkPasteMethod: String, CaseIterable, Identifiable, Sendable {
    case standard = "default"
    case appleScript = "appleScript"

    public static let userDefaultsKey = "pasteMethod"
    public static let legacyAppleScriptPasteKey = "useAppleScriptPaste"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard:
            return "Default"
        case .appleScript:
            return "AppleScript"
        }
    }

    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkPasteMethod {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let method = VoiceInkPasteMethod(rawValue: rawValue) {
            return method
        }

        return defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard
    }

    public static func setCurrent(_ method: VoiceInkPasteMethod, in defaults: UserDefaults = .standard) {
        defaults.set(method.rawValue, forKey: userDefaultsKey)
        defaults.set(method == .appleScript, forKey: legacyAppleScriptPasteKey)
    }

    public static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           VoiceInkPasteMethod(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard, in: defaults)
    }
}

public enum VoiceInkPastePreference {
    public static let restoreClipboardAfterPasteKey = "restoreClipboardAfterPaste"
    public static let clipboardRestoreDelayKey = "clipboardRestoreDelay"
    public static let defaultRestoreClipboardAfterPaste = true
    public static let defaultClipboardRestoreDelay: TimeInterval = 2.0
    public static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    public static var registeredDefaults: [String: Any] {
        [
            restoreClipboardAfterPasteKey: defaultRestoreClipboardAfterPaste,
            clipboardRestoreDelayKey: defaultClipboardRestoreDelay,
            VoiceInkPasteMethod.legacyAppleScriptPasteKey: false
        ]
    }

    public static func shouldRestoreClipboardAfterPaste(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: restoreClipboardAfterPasteKey)
    }

    public static func clipboardRestoreDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        defaults.double(forKey: clipboardRestoreDelayKey)
    }

    public static func boundedClipboardRestoreDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        max(clipboardRestoreDelay(from: defaults), minimumClipboardRestoreDelay)
    }

    public static func saveShouldRestoreClipboardAfterPaste(
        _ value: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: restoreClipboardAfterPasteKey)
    }

    public static func saveClipboardRestoreDelay(
        _ value: TimeInterval,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: clipboardRestoreDelayKey)
    }
}
