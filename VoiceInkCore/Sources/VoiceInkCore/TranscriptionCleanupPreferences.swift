import Foundation

public enum PunctuationCleanupMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case keep = "keep"
    case removeAll = "removeAll"
    case removeTrailingPeriod = "removeTrailingPeriod"

    public static let userDefaultsKey = "PunctuationCleanupMode"
    public static let legacyRemovePunctuationKey = "RemovePunctuation"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keep:
            return "Keep"
        case .removeAll:
            return "Remove all"
        case .removeTrailingPeriod:
            return "Remove trailing period"
        }
    }

    public static func current(in defaults: UserDefaults = .standard) -> PunctuationCleanupMode {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let mode = PunctuationCleanupMode(rawValue: rawValue) {
            return mode
        }

        return defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep
    }

    public static func setCurrent(_ mode: PunctuationCleanupMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
        defaults.set(mode == .removeAll, forKey: legacyRemovePunctuationKey)
    }

    public static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           PunctuationCleanupMode(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep, in: defaults)
    }
}

public struct VoiceInkTranscriptionCleanupConfiguration: Equatable, Sendable {
    public static let disabled = VoiceInkTranscriptionCleanupConfiguration()

    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkTranscriptionCleanupConfiguration {
        let shouldRemoveFillerWords = defaults.object(forKey: VoiceInkUserDefaultsKey.removeFillerWords) as? Bool
            ?? VoiceInkPreferenceDefault.removeFillerWords

        return VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: PunctuationCleanupMode.current(in: defaults),
            shouldFormatParagraphs: defaults.object(forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled) as? Bool
                ?? VoiceInkPreferenceDefault.isTextFormattingEnabled,
            shouldLowercase: defaults.object(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription) as? Bool
                ?? VoiceInkPreferenceDefault.lowercaseTranscription,
            shouldRemoveFillerWords: shouldRemoveFillerWords,
            fillerWords: VoiceInkFillerWordPreference.words(from: defaults)
        )
    }

    public let punctuationMode: PunctuationCleanupMode
    public let shouldFormatParagraphs: Bool
    public let shouldLowercase: Bool
    public let shouldRemoveFillerWords: Bool
    public let fillerWords: [String]

    public var activeFillerWords: [String] {
        shouldRemoveFillerWords ? fillerWords : []
    }

    public func filterRawOutput(
        _ text: String,
        whitespacePolicy: VoiceInkTranscriptionOutputWhitespacePolicy = .collapseRuns
    ) -> String {
        VoiceInkTranscriptionOutputFilter.filter(
            text,
            fillerWords: activeFillerWords,
            whitespacePolicy: whitespacePolicy
        )
    }

    public func applyTextPreferences(_ text: String) -> String {
        VoiceInkTranscriptionCleanupPreferences.apply(
            text,
            punctuationMode: punctuationMode,
            shouldLowercase: shouldLowercase
        )
    }

    public init(
        punctuationMode: PunctuationCleanupMode = .keep,
        shouldFormatParagraphs: Bool = false,
        shouldLowercase: Bool = false,
        shouldRemoveFillerWords: Bool = false,
        fillerWords: [String] = VoiceInkFillerWords.defaultWords
    ) {
        self.punctuationMode = punctuationMode
        self.shouldFormatParagraphs = shouldFormatParagraphs
        self.shouldLowercase = shouldLowercase
        self.shouldRemoveFillerWords = shouldRemoveFillerWords
        self.fillerWords = fillerWords
    }
}

public enum VoiceInkTranscriptionCleanupPreferences {
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'’‘ʼ＇")

    public static func apply(
        _ text: String,
        punctuationMode: PunctuationCleanupMode,
        shouldLowercase: Bool
    ) -> String {
        guard punctuationMode != .keep || shouldLowercase else {
            return text
        }

        var cleanedText = text
        switch punctuationMode {
        case .keep:
            break
        case .removeAll:
            cleanedText = removePunctuation(from: cleanedText)
        case .removeTrailingPeriod:
            cleanedText = removeTrailingPeriod(from: cleanedText)
        }

        if shouldLowercase {
            cleanedText = cleanedText.lowercased()
        }

        return cleanedText
    }

    public static func removeTrailingPeriod(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let trailingWhitespace = text.reversed().prefix { $0.isWhitespace }
        let trimmedEndIndex = text.index(text.endIndex, offsetBy: -trailingWhitespace.count)
        guard trimmedEndIndex > text.startIndex else { return text }

        let lastCharIndex = text.index(before: trimmedEndIndex)
        guard text[lastCharIndex] == "." else { return text }

        if lastCharIndex > text.startIndex {
            let previousCharIndex = text.index(before: lastCharIndex)
            guard text[previousCharIndex] != "." else { return text }
        }

        var result = text
        result.remove(at: lastCharIndex)
        return result
    }

    public static func removePunctuation(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let punctuationSeparators = CharacterSet.punctuationCharacters.subtracting(apostropheLikeCharacters)
        let cleanedScalars = text.unicodeScalars.map { scalar -> String in
            if apostropheLikeCharacters.contains(scalar) {
                return ""
            }

            if punctuationSeparators.contains(scalar) {
                return " "
            }

            return String(scalar)
        }

        return VoiceInkTranscriptTextNormalizer.normalizeInlineWhitespaceAndTrim(cleanedScalars.joined())
    }
}
