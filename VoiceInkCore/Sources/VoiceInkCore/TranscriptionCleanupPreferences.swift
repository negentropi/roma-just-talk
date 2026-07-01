import Foundation

public enum VoiceInkTranscriptionOutputWhitespacePolicy: Sendable {
    case collapseRuns
    case preserveParagraphs
}

public enum VoiceInkTranscriptTextNormalizer {
    public static func collapseWhitespaceRunsAndTrim(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizeParagraphSpacing(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
    }

    public static func normalizeInlineWhitespaceAndTrim(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum VoiceInkTranscriptionOutputFilter {
    public static let defaultFillerWords = VoiceInkFillerWords.defaultWords

    private static let hallucinationPatterns = [
        #"\[.*?\]"#,
        #"\(.*?\)"#,
        #"\{.*?\}"#
    ]

    public static func filter(
        _ text: String,
        fillerWords: [String] = [],
        whitespacePolicy: VoiceInkTranscriptionOutputWhitespacePolicy = .collapseRuns
    ) -> String {
        var filteredText = removeTagBlocks(from: text)
        filteredText = removeBracketedHallucinations(from: filteredText)
        filteredText = removeFillerWords(fillerWords, from: filteredText)

        switch whitespacePolicy {
        case .collapseRuns:
            return VoiceInkTranscriptTextNormalizer.collapseWhitespaceRunsAndTrim(filteredText)
        case .preserveParagraphs:
            return VoiceInkTranscriptTextNormalizer.normalizeInlineWhitespaceAndTrim(filteredText)
        }
    }

    private static func removeTagBlocks(from text: String) -> String {
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        guard let regex = try? NSRegularExpression(pattern: tagBlockPattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func removeBracketedHallucinations(from text: String) -> String {
        var filteredText = text
        for pattern in hallucinationPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        return filteredText
    }

    private static func removeFillerWords(_ fillerWords: [String], from text: String) -> String {
        var filteredText = text
        for fillerWord in fillerWords {
            let normalizedFiller = fillerWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedFiller.isEmpty else { continue }

            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: normalizedFiller))\\b[,.]?"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        return filteredText
    }
}

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

    public static func selection(
        fromStoredRawValue storedRawValue: String?,
        in defaults: UserDefaults = .standard
    ) -> PunctuationCleanupMode {
        if let storedRawValue, let mode = PunctuationCleanupMode(rawValue: storedRawValue) {
            return mode
        }

        return current(in: defaults)
    }

    public static func setCurrent(_ mode: PunctuationCleanupMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
        defaults.set(mode == .removeAll, forKey: legacyRemovePunctuationKey)
    }

    public static func clearCurrent(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
        defaults.set(false, forKey: legacyRemovePunctuationKey)
    }

    public static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           PunctuationCleanupMode(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep, in: defaults)
    }
}

public enum VoiceInkTranscriptionCleanupPreferenceStorage {
    public static func isTextFormattingEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled) as? Bool
            ?? VoiceInkPreferenceDefault.isTextFormattingEnabled
    }

    public static func saveTextFormattingEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
    }

    public static func shouldLowercase(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription) as? Bool
            ?? VoiceInkPreferenceDefault.lowercaseTranscription
    }

    public static func saveLowercaseTranscription(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
    }

    public static func shouldRemoveFillerWords(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.removeFillerWords) as? Bool
            ?? VoiceInkPreferenceDefault.removeFillerWords
    }

    public static func saveRemoveFillerWords(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
    }

    public static func clearTextPreferences(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.removeFillerWords)
    }
}

public struct VoiceInkTranscriptionCleanupSettings: Equatable, Sendable {
    public let punctuationMode: PunctuationCleanupMode
    public let isTextFormattingEnabled: Bool
    public let lowercaseTranscription: Bool
    public let removeFillerWords: Bool

    public var removesAllPunctuation: Bool {
        punctuationMode == .removeAll
    }

    public init(
        punctuationMode: PunctuationCleanupMode = .keep,
        isTextFormattingEnabled: Bool = VoiceInkPreferenceDefault.isTextFormattingEnabled,
        lowercaseTranscription: Bool = VoiceInkPreferenceDefault.lowercaseTranscription,
        removeFillerWords: Bool = VoiceInkPreferenceDefault.removeFillerWords
    ) {
        self.punctuationMode = punctuationMode
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.lowercaseTranscription = lowercaseTranscription
        self.removeFillerWords = removeFillerWords
    }

    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkTranscriptionCleanupSettings {
        VoiceInkTranscriptionCleanupSettings(
            punctuationMode: PunctuationCleanupMode.current(in: defaults),
            isTextFormattingEnabled: VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults),
            lowercaseTranscription: VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults),
            removeFillerWords: VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults)
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        PunctuationCleanupMode.setCurrent(punctuationMode, in: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(isTextFormattingEnabled, to: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(lowercaseTranscription, to: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(removeFillerWords, to: defaults)
    }

    public func runtimeConfiguration(
        fillerWords: [String] = VoiceInkFillerWords.defaultWords
    ) -> VoiceInkTranscriptionCleanupConfiguration {
        VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: punctuationMode,
            shouldFormatParagraphs: isTextFormattingEnabled,
            shouldLowercase: lowercaseTranscription,
            shouldRemoveFillerWords: removeFillerWords,
            fillerWords: fillerWords
        )
    }

    public var backupPreferences: VoiceInkTranscriptionCleanupBackupPreferences {
        VoiceInkTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationCleanupMode: punctuationMode,
            removePunctuation: removesAllPunctuation,
            lowercaseTranscription: lowercaseTranscription
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkTranscriptionCleanupBackupPreferences
    ) -> VoiceInkTranscriptionCleanupBackupImportPlan {
        VoiceInkTranscriptionCleanupBackupImportPlan(
            isTextFormattingEnabled: preferences.isTextFormattingEnabled,
            punctuationCleanupMode: preferences.punctuationCleanupMode
                ?? preferences.removePunctuation.map { $0 ? .removeAll : .keep },
            lowercaseTranscription: preferences.lowercaseTranscription
        )
    }
}

public struct VoiceInkTranscriptionCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isTextFormattingEnabled: Bool?
    public let punctuationCleanupMode: PunctuationCleanupMode?
    public let removePunctuation: Bool?
    public let lowercaseTranscription: Bool?

    public init(
        isTextFormattingEnabled: Bool?,
        punctuationCleanupMode: PunctuationCleanupMode?,
        removePunctuation: Bool?,
        lowercaseTranscription: Bool?
    ) {
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.removePunctuation = removePunctuation
        self.lowercaseTranscription = lowercaseTranscription
    }
}

public struct VoiceInkTranscriptionCleanupBackupImportPlan: Equatable, Sendable {
    public let isTextFormattingEnabled: Bool?
    public let punctuationCleanupMode: PunctuationCleanupMode?
    public let lowercaseTranscription: Bool?

    public init(
        isTextFormattingEnabled: Bool?,
        punctuationCleanupMode: PunctuationCleanupMode?,
        lowercaseTranscription: Bool?
    ) {
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
    }
}

public struct VoiceInkTranscriptionCleanupPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let paragraphBreaksToggleTitle: String
    public let paragraphBreaksHelpText: String?
    public let punctuationPickerTitle: String
    public let punctuationHelpText: String?
    public let lowercaseToggleTitle: String
    public let lowercaseHelpText: String?
    public let removeFillerWordsToggleTitle: String
    public let removeFillerWordsHelpText: String?
    public let addFillerWordPlaceholder: String

    public static let iOS = VoiceInkTranscriptionCleanupPresentation(
        sectionTitle: "Transcription Cleanup",
        paragraphBreaksToggleTitle: "Paragraph Breaks",
        paragraphBreaksHelpText: nil,
        punctuationPickerTitle: "Punctuation",
        punctuationHelpText: nil,
        lowercaseToggleTitle: "Lowercase Transcription",
        lowercaseHelpText: nil,
        removeFillerWordsToggleTitle: "Remove Filler Words",
        removeFillerWordsHelpText: nil,
        addFillerWordPlaceholder: "Add filler word"
    )

    public static let macOS = VoiceInkTranscriptionCleanupPresentation(
        sectionTitle: "Transcript Formatting",
        paragraphBreaksToggleTitle: "Paragraph breaks",
        paragraphBreaksHelpText: "Apply intelligent text formatting to break large block of text into paragraphs.",
        punctuationPickerTitle: "Punctuation",
        punctuationHelpText: "Keep preserves punctuation as transcribed. Remove all strips punctuation marks from the transcribed text. Remove trailing period only removes a final period from the transcribed text.",
        lowercaseToggleTitle: "Lowercase output",
        lowercaseHelpText: "Convert transcription output to lowercase.",
        removeFillerWordsToggleTitle: "Remove filler words",
        removeFillerWordsHelpText: "Automatically remove filler words like 'uh', 'um', 'hmm' from transcriptions.",
        addFillerWordPlaceholder: "Add filler word"
    )
}

public struct VoiceInkCleanupRetentionOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Int

    public var id: Int { value }
}

public struct VoiceInkMacOSCleanupSettingsPresentation: Equatable, Sendable {
    public let transcriptToggleTitle: String
    public let transcriptHelpText: String
    public let transcriptRetentionPickerTitle: String
    public let transcriptRetentionOptions: [VoiceInkCleanupRetentionOption]
    public let manualCleanupButtonTitle: String
    public let transcriptCleanupAlertTitle: String
    public let transcriptCleanupCompleteMessage: String
    public let audioToggleTitle: String
    public let audioHelpText: String
    public let audioRetentionPickerTitle: String
    public let audioRetentionOptions: [VoiceInkCleanupRetentionOption]
    public let audioCleanupAnalyzingButtonTitle: String
    public let audioCleanupAlertTitle: String
    public let cancelButtonTitle: String
    public let deleteFilesButtonTitlePrefix: String
    public let deleteFilesButtonTitleSuffix: String
    public let cleanupCompleteAlertTitle: String
    public let okButtonTitle: String
    public let disclosureSystemImageName: String

    public static let macOS = VoiceInkMacOSCleanupSettingsPresentation(
        transcriptToggleTitle: "Auto-delete Transcripts",
        transcriptHelpText: "Automatically delete transcript history based on the retention period you set.",
        transcriptRetentionPickerTitle: "Delete After",
        transcriptRetentionOptions: [
            VoiceInkCleanupRetentionOption(title: "Immediately", value: 0),
            VoiceInkCleanupRetentionOption(title: "1 hour", value: 60),
            VoiceInkCleanupRetentionOption(title: "1 day", value: 24 * 60),
            VoiceInkCleanupRetentionOption(title: "3 days", value: 3 * 24 * 60),
            VoiceInkCleanupRetentionOption(title: "7 days", value: 7 * 24 * 60)
        ],
        manualCleanupButtonTitle: "Run Cleanup Now",
        transcriptCleanupAlertTitle: "Transcript Cleanup",
        transcriptCleanupCompleteMessage: "Cleanup complete.",
        audioToggleTitle: "Auto-delete Audio Files",
        audioHelpText: "Automatically delete audio recordings while keeping text transcripts intact.",
        audioRetentionPickerTitle: "Keep Audio For",
        audioRetentionOptions: [
            VoiceInkCleanupRetentionOption(title: "1 day", value: 1),
            VoiceInkCleanupRetentionOption(title: "3 days", value: 3),
            VoiceInkCleanupRetentionOption(title: "7 days", value: 7),
            VoiceInkCleanupRetentionOption(title: "14 days", value: 14),
            VoiceInkCleanupRetentionOption(title: "30 days", value: 30)
        ],
        audioCleanupAnalyzingButtonTitle: "Analyzing...",
        audioCleanupAlertTitle: "Audio Cleanup",
        cancelButtonTitle: "Cancel",
        deleteFilesButtonTitlePrefix: "Delete",
        deleteFilesButtonTitleSuffix: "Files",
        cleanupCompleteAlertTitle: "Cleanup Complete",
        okButtonTitle: "OK",
        disclosureSystemImageName: "chevron.right"
    )

    public func audioCleanupButtonTitle(isAnalyzing: Bool) -> String {
        isAnalyzing ? audioCleanupAnalyzingButtonTitle : manualCleanupButtonTitle
    }

    public func deleteFilesButtonTitle(fileCount: Int) -> String {
        "\(deleteFilesButtonTitlePrefix) \(fileCount) \(deleteFilesButtonTitleSuffix)"
    }

    public func audioCleanupConfirmationMessage(fileCount: Int, totalSizeText: String) -> String {
        "This will delete \(fileCount) audio files (\(totalSizeText))."
    }

    public func audioCleanupFileSizeText(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    public func noAudioFilesMessage(retentionDays: Int) -> String {
        "No audio files found older than \(retentionDays) day\(retentionDays > 1 ? "s" : "")."
    }

    public func audioCleanupResultMessage(deletedCount: Int, errorCount: Int) -> String {
        if errorCount > 0 {
            return "Deleted \(deletedCount) files. Failed: \(errorCount)."
        }

        return "Deleted \(deletedCount) audio files."
    }
}

fileprivate enum VoiceInkCleanupAutomaticAudioAction: Equatable, Sendable {
    case none
    case start
    case stop
}

public struct VoiceInkMacOSCleanupSettingsTogglePlan: Equatable, Sendable {
    public let isExpanded: Bool
    private let audioAction: VoiceInkCleanupAutomaticAudioAction

    public init(isExpanded: Bool) {
        self.init(isExpanded: isExpanded, audioAction: .none)
    }

    fileprivate init(
        isExpanded: Bool,
        audioAction: VoiceInkCleanupAutomaticAudioAction
    ) {
        self.isExpanded = isExpanded
        self.audioAction = audioAction
    }

    public func applyAutomaticAudioRuntimeState(
        start: () -> Void,
        stop: () -> Void
    ) {
        switch audioAction {
        case .none:
            break
        case .start:
            start()
        case .stop:
            stop()
        }
    }
}

public enum VoiceInkMacOSCleanupSettingsPolicy {
    public static func shouldShowAudioCleanupSection(
        isTranscriptionCleanupEnabled: Bool
    ) -> Bool {
        !isTranscriptionCleanupEnabled
    }

    public static func transcriptCleanupChangePlan(
        isEnabled: Bool,
        isAudioCleanupEnabled: Bool
    ) -> VoiceInkMacOSCleanupSettingsTogglePlan {
        VoiceInkMacOSCleanupSettingsTogglePlan(
            isExpanded: isEnabled,
            audioAction: audioActionAfterTranscriptCleanupChange(
                isTranscriptionCleanupEnabled: isEnabled,
                isAudioCleanupEnabled: isAudioCleanupEnabled
            )
        )
    }

    public static func audioCleanupChangePlan(
        isEnabled: Bool
    ) -> VoiceInkMacOSCleanupSettingsTogglePlan {
        VoiceInkMacOSCleanupSettingsTogglePlan(isExpanded: isEnabled)
    }

    private static func audioActionAfterTranscriptCleanupChange(
        isTranscriptionCleanupEnabled: Bool,
        isAudioCleanupEnabled: Bool
    ) -> VoiceInkCleanupAutomaticAudioAction {
        if isTranscriptionCleanupEnabled {
            return .stop
        }

        return isAudioCleanupEnabled ? .start : .none
    }
}

public struct VoiceInkTranscriptionCleanupConfiguration: Equatable, Sendable {
    public static let disabled = VoiceInkTranscriptionCleanupConfiguration()

    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkTranscriptionCleanupConfiguration {
        VoiceInkTranscriptionCleanupSettings.current(in: defaults).runtimeConfiguration(
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

    public func prepareFilteredText(
        _ filteredText: String,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> VoiceInkPreparedTranscriptionText {
        let textForWordReplacement: String
        if normalizeParagraphSpacingBeforeFormatting {
            let normalizedText = VoiceInkTranscriptTextNormalizer.normalizeParagraphSpacing(filteredText)
            textForWordReplacement = shouldFormatParagraphs
                ? VoiceInkTranscriptParagraphFormatter.format(normalizedText)
                : normalizedText
        } else {
            textForWordReplacement = prepareFilteredTextForWordReplacement(filteredText)
        }

        let wordReplacedText = wordReplacement(textForWordReplacement)
        return VoiceInkPreparedTranscriptionText(
            textForWordReplacement: textForWordReplacement,
            wordReplacedText: wordReplacedText,
            cleanedText: applyTextPreferences(wordReplacedText)
        )
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

    public func prepareFilteredTextForWordReplacement(_ filteredText: String) -> String {
        let trimmedText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)
        return shouldFormatParagraphs
            ? VoiceInkTranscriptParagraphFormatter.format(trimmedText)
            : trimmedText
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

public struct VoiceInkPreparedTranscriptionText: Equatable, Sendable {
    public let textForWordReplacement: String
    public let wordReplacedText: String
    public let cleanedText: String

    public init(
        textForWordReplacement: String,
        wordReplacedText: String,
        cleanedText: String
    ) {
        self.textForWordReplacement = textForWordReplacement
        self.wordReplacedText = wordReplacedText
        self.cleanedText = cleanedText
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
