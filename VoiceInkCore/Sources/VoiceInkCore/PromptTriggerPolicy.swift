import Foundation

public struct VoiceInkPromptTrigger: Equatable, Sendable {
    public let promptId: UUID
    public let triggerWords: [String]

    public init(promptId: UUID, triggerWords: [String]) {
        self.promptId = promptId
        self.triggerWords = triggerWords
    }
}

public struct VoiceInkPromptTriggerMatch: Equatable, Sendable {
    public let promptId: UUID
    public let triggerWord: String
    public let processedText: String

    public init(promptId: UUID, triggerWord: String, processedText: String) {
        self.promptId = promptId
        self.triggerWord = triggerWord
        self.processedText = processedText
    }
}

public struct VoiceInkPromptDetectionResult: Equatable, Sendable {
    public let shouldEnableAI: Bool
    public let selectedPromptId: UUID?
    public let processedText: String
    public let detectedTriggerWord: String?
    public let originalEnhancementState: Bool
    public let originalPromptId: UUID?

    public init(
        shouldEnableAI: Bool,
        selectedPromptId: UUID?,
        processedText: String,
        detectedTriggerWord: String?,
        originalEnhancementState: Bool,
        originalPromptId: UUID?
    ) {
        self.shouldEnableAI = shouldEnableAI
        self.selectedPromptId = selectedPromptId
        self.processedText = processedText
        self.detectedTriggerWord = detectedTriggerWord
        self.originalEnhancementState = originalEnhancementState
        self.originalPromptId = originalPromptId
    }
}

public extension VoiceInkPromptDetectionResult {
    func applyingSettingsState(
        current state: VoiceInkAIEnhancementPromptSettingsState
    ) -> VoiceInkAIEnhancementPromptSettingsState? {
        guard shouldEnableAI else { return nil }

        return VoiceInkAIEnhancementPromptSettingsState(
            isEnhancementEnabled: true,
            selectedPromptId: selectedPromptId ?? state.selectedPromptId
        )
    }

    func restoringSettingsState(
        current _: VoiceInkAIEnhancementPromptSettingsState
    ) -> VoiceInkAIEnhancementPromptSettingsState? {
        guard shouldEnableAI else { return nil }

        return VoiceInkAIEnhancementPromptSettingsState(
            isEnhancementEnabled: originalEnhancementState,
            selectedPromptId: originalPromptId
        )
    }
}

public enum VoiceInkPromptDetectionPolicy {
    public static func analyzeText(
        _ text: String,
        prompts: [VoiceInkCustomPrompt],
        isEnhancementEnabled: Bool,
        selectedPromptId: UUID?
    ) -> VoiceInkPromptDetectionResult {
        let triggers = VoiceInkCustomPromptPolicy.triggerDetectablePrompts(from: prompts).map {
            VoiceInkPromptTrigger(promptId: $0.id, triggerWords: $0.triggerWords)
        }

        if let match = VoiceInkPromptTriggerPolicy.detect(in: text, triggers: triggers) {
            return VoiceInkPromptDetectionResult(
                shouldEnableAI: true,
                selectedPromptId: match.promptId,
                processedText: match.processedText,
                detectedTriggerWord: match.triggerWord,
                originalEnhancementState: isEnhancementEnabled,
                originalPromptId: selectedPromptId
            )
        }

        return VoiceInkPromptDetectionResult(
            shouldEnableAI: false,
            selectedPromptId: nil,
            processedText: text,
            detectedTriggerWord: nil,
            originalEnhancementState: isEnhancementEnabled,
            originalPromptId: selectedPromptId
        )
    }
}

public enum VoiceInkPromptTriggerPolicy {
    public static func hasTriggerWordDraft(_ word: String) -> Bool {
        !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func addingTriggerWord(_ word: String, to existingWords: [String]) -> [String]? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }

        let lowerCaseWord = trimmedWord.lowercased()
        guard !existingWords.contains(where: { $0.lowercased() == lowerCaseWord }) else { return nil }

        return existingWords + [trimmedWord]
    }

    public static func removingTriggerWord(_ word: String, from existingWords: [String]) -> [String] {
        existingWords.filter { $0 != word }
    }

    public static func detect(in text: String, triggers: [VoiceInkPromptTrigger]) -> VoiceInkPromptTriggerMatch? {
        for prompt in triggers {
            guard let result = detectAndStripTriggerWord(from: text, triggerWords: prompt.triggerWords) else {
                continue
            }

            return VoiceInkPromptTriggerMatch(
                promptId: prompt.promptId,
                triggerWord: result.triggerWord,
                processedText: result.processedText
            )
        }

        return nil
    }

    public static func detectAndStripTriggerWord(
        from text: String,
        triggerWords: [String]
    ) -> (triggerWord: String, processedText: String)? {
        let sortedTriggerWords = triggerWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for triggerWord in sortedTriggerWords {
            if let afterTrailing = stripTrailingTriggerWord(from: text, triggerWord: triggerWord) {
                if let afterBoth = stripLeadingTriggerWord(from: afterTrailing, triggerWord: triggerWord) {
                    return (triggerWord, afterBoth)
                }
                return (triggerWord, afterTrailing)
            }
        }

        for triggerWord in sortedTriggerWords {
            if let afterLeading = stripLeadingTriggerWord(from: text, triggerWord: triggerWord) {
                if let afterBoth = stripTrailingTriggerWord(from: afterLeading, triggerWord: triggerWord) {
                    return (triggerWord, afterBoth)
                }
                return (triggerWord, afterLeading)
            }
        }

        return nil
    }

    private static func stripLeadingTriggerWord(from text: String, triggerWord: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerText = trimmedText.lowercased()
        let lowerTrigger = triggerWord.lowercased()

        guard lowerText.hasPrefix(lowerTrigger) else { return nil }

        let triggerEndIndex = trimmedText.index(trimmedText.startIndex, offsetBy: triggerWord.count)

        if triggerEndIndex < trimmedText.endIndex {
            let charAfterTrigger = trimmedText[triggerEndIndex]
            if charAfterTrigger.isLetter || charAfterTrigger.isNumber {
                return nil
            }
        }

        if triggerEndIndex >= trimmedText.endIndex {
            return ""
        }

        var remainingText = String(trimmedText[triggerEndIndex...])

        remainingText = remainingText.replacingOccurrences(
            of: "^[,\\.!\\?;:\\s]+",
            with: "",
            options: .regularExpression
        )

        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !remainingText.isEmpty {
            remainingText = remainingText.prefix(1).uppercased() + remainingText.dropFirst()
        }

        return remainingText
    }

    private static func stripTrailingTriggerWord(from text: String, triggerWord: String) -> String? {
        var trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let punctuationSet = CharacterSet(charactersIn: ",.!?;:")
        while let scalar = trimmedText.unicodeScalars.last, punctuationSet.contains(scalar) {
            trimmedText.removeLast()
        }

        let lowerText = trimmedText.lowercased()
        let lowerTrigger = triggerWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard lowerText.hasSuffix(lowerTrigger) else { return nil }

        let triggerStartIndex = trimmedText.index(trimmedText.endIndex, offsetBy: -triggerWord.count)
        if triggerStartIndex > trimmedText.startIndex {
            let charBeforeTrigger = trimmedText[trimmedText.index(before: triggerStartIndex)]
            if charBeforeTrigger.isLetter || charBeforeTrigger.isNumber {
                return nil
            }
        }

        var remainingText = String(trimmedText[..<triggerStartIndex])

        remainingText = remainingText.replacingOccurrences(
            of: "[,\\.!\\?;:\\s]+$",
            with: "",
            options: .regularExpression
        )
        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !remainingText.isEmpty {
            remainingText = remainingText.prefix(1).uppercased() + remainingText.dropFirst()
        }

        return remainingText
    }
}

public struct VoiceInkPromptTriggerDraftSubmission: Equatable, Sendable {
    public let updatedWords: [String]?
    public let draftStateAfterSubmit: VoiceInkPromptTriggerDraftState

    public init(
        updatedWords: [String]?,
        draftStateAfterSubmit: VoiceInkPromptTriggerDraftState
    ) {
        self.updatedWords = updatedWords
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    @discardableResult
    public func applyRuntimeState(
        setTriggerWords: ([String]) -> Void,
        setDraftState: (VoiceInkPromptTriggerDraftState) -> Void
    ) -> Self {
        if let updatedWords {
            setTriggerWords(updatedWords)
        }
        setDraftState(draftStateAfterSubmit)
        return self
    }
}

public struct VoiceInkPromptTriggerDraftState: Equatable, Sendable {
    public var draft: String

    public init(draft: String = "") {
        self.draft = draft
    }

    public var canSubmit: Bool {
        VoiceInkPromptTriggerPolicy.hasTriggerWordDraft(draft)
    }

    public func submitting(existingWords: [String]) -> VoiceInkPromptTriggerDraftSubmission {
        let updatedWords = VoiceInkPromptTriggerPolicy.addingTriggerWord(draft, to: existingWords)
        return VoiceInkPromptTriggerDraftSubmission(
            updatedWords: updatedWords,
            draftStateAfterSubmit: VoiceInkPromptTriggerDraftState(draft: updatedWords == nil ? draft : "")
        )
    }
}
