import Foundation

public struct VoiceInkMacOSAppendTrailingSpaceSettingsPresentation: Equatable, Sendable {
    public let toggleTitle: String
    public let helpText: String

    public static let macOS = VoiceInkMacOSAppendTrailingSpaceSettingsPresentation(
        toggleTitle: "Add Space After Paste",
        helpText: "Add a trailing space after pasted transcription output."
    )
}

public enum VoiceInkAppendTrailingSpacePreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.appendTrailingSpace
    public static let defaultIsEnabled = VoiceInkPreferenceDefault.appendTrailingSpace
    public static let macOSSettingsPresentation = VoiceInkMacOSAppendTrailingSpaceSettingsPresentation.macOS

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultIsEnabled
        ]
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkTranscriptionPasteOutputPolicy {
    public static let trialExpiredPrefix = "Your trial has expired. Upgrade to VoiceInk Pro at \(VoiceInkLicenseLinks.purchaseDisplayURLString)"

    public struct CursorPasteTextPlan: Equatable, Sendable {
        public let text: String
        public let shouldReadCursorContext: Bool

        public init(text: String, shouldReadCursorContext: Bool) {
            self.text = text
            self.shouldReadCursorContext = shouldReadCursorContext
        }

        public func text(beforeCursor: String?) -> String {
            guard shouldReadCursorContext else { return text }
            return VoiceInkContextualCapitalizationFormatter.format(
                text,
                beforeCursor: beforeCursor
            )
        }
    }

    public static func cursorPasteTextPlan(
        _ text: String,
        shouldLowercase: Bool
    ) -> CursorPasteTextPlan {
        CursorPasteTextPlan(
            text: text,
            shouldReadCursorContext: !shouldLowercase
                && VoiceInkContextualCapitalizationFormatter.needsCursorContext(text)
        )
    }

    public static func cursorPasteTextPlan(
        _ text: String,
        from defaults: UserDefaults = .standard
    ) -> CursorPasteTextPlan {
        cursorPasteTextPlan(
            text,
            shouldLowercase: VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults)
        )
    }

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

public enum VoiceInkCursorTextContextPolicy {
    public static let defaultMaximumLength = 240
    public static let parentTraversalLimit = 4
    public static let textInputRoleNames: Set<String> = [
        "AXComboBox",
        "AXTextArea",
        "AXTextField"
    ]

    public static func shouldAttemptRead(maximumLength: Int = defaultMaximumLength) -> Bool {
        maximumLength > 0
    }

    public static func prefixLength(
        cursorLocation: Int,
        maximumLength: Int = defaultMaximumLength
    ) -> Int? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              cursorLocation >= 0 else {
            return nil
        }

        return min(maximumLength, cursorLocation)
    }

    public static func isTextInputRole(_ role: String?) -> Bool {
        guard let role else { return false }
        return textInputRoleNames.contains(role)
    }

    public static func valueSuffix(
        from text: String,
        role: String?,
        maximumLength: Int = defaultMaximumLength
    ) -> String? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              isTextInputRole(role) else {
            return nil
        }

        guard text.count > maximumLength else {
            return text
        }

        return String(text.suffix(maximumLength))
    }
}
