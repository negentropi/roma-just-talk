import Foundation

public enum RomaIOSKeyboardAutoSendPreference {
    public static let userDefaultsKey = "iOSKeyboardAutoSendReturn"
    public static let defaultIsEnabled = false

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }
}

public struct RomaIOSKeyboardDeliveryPlan: Equatable, Sendable {
    public let text: String
    public let shouldInsertReturn: Bool

    public init(text: String, shouldInsertReturn: Bool) {
        self.text = text
        self.shouldInsertReturn = shouldInsertReturn
    }
}

public enum RomaIOSKeyboardDeliveryPolicy {
    public static let returnText = "\n"

    public static func plan(
        text: String,
        shouldLowercase: Bool,
        shouldInsertReturn: Bool,
        beforeCursor: String?
    ) -> RomaIOSKeyboardDeliveryPlan {
        let pastePlan = RomaTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            text,
            shouldLowercase: shouldLowercase
        )
        return RomaIOSKeyboardDeliveryPlan(
            text: pastePlan.text(beforeCursor: beforeCursor),
            shouldInsertReturn: shouldInsertReturn
        )
    }
}
