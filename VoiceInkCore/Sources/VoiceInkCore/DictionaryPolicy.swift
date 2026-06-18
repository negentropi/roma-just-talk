import Foundation

public struct VoiceInkVocabularyInsertPlan: Equatable, Sendable {
    public let wordsToInsert: [String]
    public let errorMessage: String?

    public var shouldInsert: Bool {
        !wordsToInsert.isEmpty
    }
}

public struct VoiceInkWordReplacementInsertPlan: Equatable, Sendable {
    public let originalText: String
    public let replacementText: String
    public let errorMessage: String?

    public var shouldInsert: Bool {
        errorMessage == nil && !VoiceInkDictionaryPolicy.tokens(from: originalText).isEmpty && !replacementText.isEmpty
    }
}

public struct VoiceInkWordReplacementBackupImportPlan: Equatable, Sendable {
    public let rulesToInsert: [VoiceInkWordReplacementRule]
    public let skippedInvalidReplacementCount: Int

    public init(
        rulesToInsert: [VoiceInkWordReplacementRule],
        skippedInvalidReplacementCount: Int
    ) {
        self.rulesToInsert = rulesToInsert
        self.skippedInvalidReplacementCount = skippedInvalidReplacementCount
    }
}

public struct VoiceInkVocabularyWordBackup: Codable, Equatable, Sendable {
    public let word: String

    public init(word: String) {
        self.word = word
    }
}

public struct VoiceInkDictionaryAlertPresentation: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String

    public init(
        id: String,
        title: String,
        message: String,
        primaryButtonTitle: String = "OK"
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
    }

    public static func duplicateFillerWord(message: String) -> VoiceInkDictionaryAlertPresentation {
        VoiceInkDictionaryAlertPresentation(
            id: "duplicateFillerWord-\(message)",
            title: "Duplicate Word",
            message: message
        )
    }

    public static func vocabulary(message: String) -> VoiceInkDictionaryAlertPresentation {
        VoiceInkDictionaryAlertPresentation(
            id: "vocabulary-\(message)",
            title: "Vocabulary",
            message: message
        )
    }

    public static func wordReplacement(message: String) -> VoiceInkDictionaryAlertPresentation {
        VoiceInkDictionaryAlertPresentation(
            id: "wordReplacement-\(message)",
            title: "Word Replacement",
            message: message
        )
    }

    public static func failedToAddVocabularyWord(
        _ word: String,
        localizedDescription: String
    ) -> String {
        "Failed to add '\(word)': \(localizedDescription)"
    }

    public static func failedToAddWordReplacement(localizedDescription: String) -> String {
        "Failed to add replacement: \(localizedDescription)"
    }

    public static func failedToSaveWordReplacementChanges(localizedDescription: String) -> String {
        "Failed to save changes: \(localizedDescription)"
    }

    public static func failedToRemoveVocabularyWord(localizedDescription: String) -> String {
        "Failed to remove word: \(localizedDescription)"
    }

    public static func failedToRemoveWordReplacement(localizedDescription: String) -> String {
        "Failed to remove replacement: \(localizedDescription)"
    }
}

public enum VoiceInkDictionaryPolicy {
    public static func hasVocabularyDraft(_ input: String) -> Bool {
        !tokens(from: input).isEmpty
    }

    public static func vocabularyInsertPlan(
        input: String,
        existingWords: [String]
    ) -> VoiceInkVocabularyInsertPlan {
        let words = tokens(from: input)
        guard !words.isEmpty else {
            return VoiceInkVocabularyInsertPlan(wordsToInsert: [], errorMessage: nil)
        }

        let existingKeys = Set(existingWords.map { $0.lowercased() })

        if words.count == 1, let word = words.first, existingKeys.contains(word.lowercased()) {
            return VoiceInkVocabularyInsertPlan(
                wordsToInsert: [],
                errorMessage: "'\(word)' is already in the vocabulary"
            )
        }

        let wordsToInsert = vocabularyWordsToInsert(words, existingWords: existingWords)

        return VoiceInkVocabularyInsertPlan(wordsToInsert: wordsToInsert, errorMessage: nil)
    }

    public static func vocabularyWordsToInsert(
        _ words: [String],
        existingWords: [String]
    ) -> [String] {
        var insertedKeys = Set(existingWords.map { $0.lowercased() })
        var wordsToInsert = [String]()

        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !insertedKeys.contains(key) else { continue }

            wordsToInsert.append(trimmed)
            insertedKeys.insert(key)
        }

        return wordsToInsert
    }

    public static func vocabularyBackupRecords(from words: [String]) -> [VoiceInkVocabularyWordBackup] {
        words.map { VoiceInkVocabularyWordBackup(word: $0) }
    }

    public static func vocabularyWordsToInsert(
        from backupRecords: [VoiceInkVocabularyWordBackup],
        existingWords: [String]
    ) -> [String] {
        vocabularyWordsToInsert(
            backupRecords.map(\.word),
            existingWords: existingWords
        )
    }

    public static func wordReplacementBackupImportPlan(
        from backupReplacements: [String: String],
        existingOriginalTexts: [String]
    ) -> VoiceInkWordReplacementBackupImportPlan {
        var existingOriginalTexts = existingOriginalTexts
        var rulesToInsert = [VoiceInkWordReplacementRule]()
        var skippedInvalidReplacementCount = 0

        for (original, replacement) in backupReplacements {
            let plan = wordReplacementInsertPlan(
                original: original,
                replacement: replacement,
                existingOriginalTexts: existingOriginalTexts
            )

            if plan.errorMessage != nil {
                continue
            }

            guard plan.shouldInsert else {
                skippedInvalidReplacementCount += 1
                continue
            }

            rulesToInsert.append(
                VoiceInkWordReplacementRule(
                    originalText: plan.originalText,
                    replacementText: plan.replacementText
                )
            )
            existingOriginalTexts.append(plan.originalText)
        }

        return VoiceInkWordReplacementBackupImportPlan(
            rulesToInsert: rulesToInsert,
            skippedInvalidReplacementCount: skippedInvalidReplacementCount
        )
    }

    public static func wordReplacementInsertPlan(
        original: String,
        replacement: String,
        existingOriginalTexts: [String]
    ) -> VoiceInkWordReplacementInsertPlan {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTokens = tokens(from: trimmedOriginal)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalTokens.isEmpty, !trimmedReplacement.isEmpty else {
            return VoiceInkWordReplacementInsertPlan(
                originalText: trimmedOriginal,
                replacementText: trimmedReplacement,
                errorMessage: nil
            )
        }

        let existingTokens = Set(existingOriginalTexts.flatMap { tokens(from: $0).map { $0.lowercased() } })

        for token in originalTokens where existingTokens.contains(token.lowercased()) {
            return VoiceInkWordReplacementInsertPlan(
                originalText: trimmedOriginal,
                replacementText: trimmedReplacement,
                errorMessage: "'\(token)' already exists in word replacements"
            )
        }

        return VoiceInkWordReplacementInsertPlan(
            originalText: trimmedOriginal,
            replacementText: trimmedReplacement,
            errorMessage: nil
        )
    }

    public static func canSaveWordReplacementDraft(
        original: String,
        replacement: String
    ) -> Bool {
        wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: []
        ).shouldInsert
    }

    public static func tokens(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
