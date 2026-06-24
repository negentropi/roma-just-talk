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

    public static func selection(
        fromStoredRawValue storedRawValue: String?,
        in defaults: UserDefaults = .standard
    ) -> VoiceInkPasteMethod {
        if let storedRawValue, let method = VoiceInkPasteMethod(rawValue: storedRawValue) {
            return method
        }

        return current(in: defaults)
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

public struct VoiceInkPasteDelayOption: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: TimeInterval

    public var id: TimeInterval { value }

    public init(label: String, value: TimeInterval) {
        self.label = label
        self.value = value
    }
}

public struct VoiceInkMacOSPasteSettingsPresentation: Equatable, Sendable {
    public let keepClipboardContentLabel: String
    public let keepClipboardContentInfoMessage: String
    public let restoreDelayLabel: String
    public let restoreDelayOptions: [VoiceInkPasteDelayOption]
    public let pasteMethodLabel: String
    public let pasteMethodHelpMessage: String

    public init(
        keepClipboardContentLabel: String,
        keepClipboardContentInfoMessage: String,
        restoreDelayLabel: String,
        restoreDelayOptions: [VoiceInkPasteDelayOption],
        pasteMethodLabel: String,
        pasteMethodHelpMessage: String
    ) {
        self.keepClipboardContentLabel = keepClipboardContentLabel
        self.keepClipboardContentInfoMessage = keepClipboardContentInfoMessage
        self.restoreDelayLabel = restoreDelayLabel
        self.restoreDelayOptions = restoreDelayOptions
        self.pasteMethodLabel = pasteMethodLabel
        self.pasteMethodHelpMessage = pasteMethodHelpMessage
    }
}

public struct VoiceInkPasteBackupPreferences: Codable, Equatable, Sendable {
    public let shouldRestoreClipboardAfterPaste: Bool?
    public let clipboardRestoreDelay: Double?

    public init(
        shouldRestoreClipboardAfterPaste: Bool?,
        clipboardRestoreDelay: Double?
    ) {
        self.shouldRestoreClipboardAfterPaste = shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }
}

public struct VoiceInkPasteBackupImportPlan: Equatable, Sendable {
    public let shouldRestoreClipboardAfterPaste: Bool?
    public let clipboardRestoreDelay: Double?

    public init(
        shouldRestoreClipboardAfterPaste: Bool?,
        clipboardRestoreDelay: Double?
    ) {
        self.shouldRestoreClipboardAfterPaste = shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
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

    public static let macOSSettingsPresentation = VoiceInkMacOSPasteSettingsPresentation(
        keepClipboardContentLabel: "Keep Clipboard Content",
        keepClipboardContentInfoMessage: "VoiceInk temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard.",
        restoreDelayLabel: "Restore Delay",
        restoreDelayOptions: [
            VoiceInkPasteDelayOption(label: "250ms", value: 0.25),
            VoiceInkPasteDelayOption(label: "500ms", value: 0.5),
            VoiceInkPasteDelayOption(label: "1s", value: 1.0),
            VoiceInkPasteDelayOption(label: "2s", value: 2.0),
            VoiceInkPasteDelayOption(label: "3s", value: 3.0),
            VoiceInkPasteDelayOption(label: "4s", value: 4.0),
            VoiceInkPasteDelayOption(label: "5s", value: 5.0)
        ],
        pasteMethodLabel: "Paste Method",
        pasteMethodHelpMessage: "Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly."
    )

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

    public static func backupPreferences(
        shouldRestoreClipboardAfterPaste: Bool,
        clipboardRestoreDelay: Double
    ) -> VoiceInkPasteBackupPreferences {
        VoiceInkPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkPasteBackupPreferences
    ) -> VoiceInkPasteBackupImportPlan {
        VoiceInkPasteBackupImportPlan(
            shouldRestoreClipboardAfterPaste: preferences.shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: preferences.clipboardRestoreDelay
        )
    }
}
