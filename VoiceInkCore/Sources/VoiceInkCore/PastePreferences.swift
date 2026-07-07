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

public enum VoiceInkPasteDiagnostics {
    public static let failedToPrepareClipboardMessage = "Failed to prepare clipboard for paste"
    public static let skippedClipboardRestoreCommandNotPostedMessage = "Skipping clipboard restore because paste command was not posted"
    public static let appleScriptPasteScriptUnavailableMessage = "AppleScript paste script is unavailable"
    public static let accessibilityPermissionRequiredForSimulatedPasteMessage = "Accessibility permission is required to paste with simulated key events"
    public static let failedToCreateCommandVPasteEventsMessage = "Failed to create Cmd+V keyboard events"

    public static func appleScriptPasteFailedMessage(errorDescription: String) -> String {
        "AppleScript paste failed: \(errorDescription)"
    }
}

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

public enum VoiceInkContextualCapitalizationFormatter {
    public static func needsCursorContext(_ text: String) -> Bool {
        guard let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return false
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return false }

        return shouldUppercaseFirstCasedCharacter(in: firstWord) ||
            shouldLowercaseFirstCasedCharacter(in: firstWord)
    }

    public static func format(_ text: String, beforeCursor: String?) -> String {
        guard let beforeCursor,
              let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return text
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return text }

        switch boundary(beforeCursor) {
        case .sentenceStart:
            guard shouldUppercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).uppercased())
        case .midSentence:
            guard shouldLowercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).lowercased())
        }
    }

    private enum Boundary {
        case sentenceStart
        case midSentence
    }

    private static let sentenceTerminators = Set<Character>([".", "!", "?", "。", "！", "？"])
    private static let wordInternalCharacters = Set<Character>(["'", "’", "‘", "ʼ", "＇", "-"])

    private static func boundary(_ beforeCursor: String) -> Boundary {
        var index = beforeCursor.endIndex
        var sawTrailingNewline = false

        while index > beforeCursor.startIndex {
            let previousIndex = beforeCursor.index(before: index)
            let character = beforeCursor[previousIndex]

            if isWhitespace(character) {
                if containsNewline(character) {
                    sawTrailingNewline = true
                }
                index = previousIndex
                continue
            }

            if sawTrailingNewline || sentenceTerminators.contains(character) {
                return .sentenceStart
            }

            return .midSentence
        }

        return .sentenceStart
    }

    private static func firstCasedCharacterRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            if isCasedLetter(text[index]) {
                return index..<nextIndex
            }
            index = nextIndex
        }
        return nil
    }

    private static func word(in text: String, startingAt startIndex: String.Index) -> String {
        var index = startIndex
        var result = ""

        while index < text.endIndex {
            let character = text[index]
            guard isWordCharacter(character) else { break }
            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func shouldUppercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard let first = letters.first,
              isLowercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func shouldLowercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard letters.count > 1,
              let first = letters.first,
              isUppercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func casedLetters(in word: String) -> [Character] {
        word.filter { isCasedLetter($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        isCasedLetter(character) ||
            wordInternalCharacters.contains(character) ||
            character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isCasedLetter(_ character: Character) -> Bool {
        let value = String(character)
        return value.lowercased() != value.uppercased()
    }

    private static func isLowercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.lowercased() && value != value.uppercased()
    }

    private static func isUppercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.uppercased() && value != value.lowercased()
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func containsNewline(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    private static func replacing(_ text: String, range: Range<String.Index>, with replacement: String) -> String {
        var result = text
        result.replaceSubrange(range, with: replacement)
        return result
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
