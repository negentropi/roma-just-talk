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
