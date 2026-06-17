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

public enum VoiceInkDictionaryPolicy {
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

    public static func wordReplacementInsertPlan(
        original: String,
        replacement: String,
        existingOriginalTexts: [String]
    ) -> VoiceInkWordReplacementInsertPlan {
        let originalTokens = tokens(from: original)
        guard !originalTokens.isEmpty, !replacement.isEmpty else {
            return VoiceInkWordReplacementInsertPlan(
                originalText: original,
                replacementText: replacement,
                errorMessage: nil
            )
        }

        let existingTokens = Set(existingOriginalTexts.flatMap { tokens(from: $0).map { $0.lowercased() } })

        for token in originalTokens where existingTokens.contains(token.lowercased()) {
            return VoiceInkWordReplacementInsertPlan(
                originalText: original,
                replacementText: replacement,
                errorMessage: "'\(token)' already exists in word replacements"
            )
        }

        return VoiceInkWordReplacementInsertPlan(
            originalText: original,
            replacementText: replacement,
            errorMessage: nil
        )
    }

    public static func tokens(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
