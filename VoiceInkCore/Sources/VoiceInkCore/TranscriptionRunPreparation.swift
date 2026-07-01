import Foundation
import NaturalLanguage

public struct VoiceInkPostProcessingSkipConfiguration: Equatable, Sendable {
    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkPostProcessingSkipConfiguration {
        VoiceInkPostProcessingSkipConfiguration(
            isEnabled: defaults.object(forKey: VoiceInkUserDefaultsKey.skipShortEnhancement) as? Bool
                ?? VoiceInkPreferenceDefault.skipShortEnhancement,
            wordThreshold: defaults.object(forKey: VoiceInkUserDefaultsKey.shortEnhancementWordThreshold) as? Int
                ?? VoiceInkPreferenceDefault.shortEnhancementWordThreshold
        )
    }

    public let isEnabled: Bool
    public let wordThreshold: Int

    public init(isEnabled: Bool, wordThreshold: Int) {
        self.isEnabled = isEnabled
        self.wordThreshold = wordThreshold > 0
            ? wordThreshold
            : VoiceInkPreferenceDefault.shortEnhancementWordThreshold
    }
}

public enum VoiceInkPostProcessingSkipPolicy {
    public static func shouldSkipPostProcessing(
        transcript: String,
        configuration: VoiceInkPostProcessingSkipConfiguration,
        promptTriggerForcesPostProcessing: Bool
    ) -> Bool {
        guard configuration.isEnabled, !promptTriggerForcesPostProcessing else {
            return false
        }

        return VoiceInkWordCounter.count(in: transcript) <= configuration.wordThreshold
    }
}

public enum VoiceInkWordCounter {
    public static func count(in text: String) -> Int {
        count(in: text, language: nil)
    }

    static func count(in text: String, language: NLLanguage?) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        if let language {
            tokenizer.setLanguage(language)
        }
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}

public enum VoiceInkTranscriptionPromptUse: Equatable, Sendable {
    case recordedFileTranscription(VoiceInkProviderKind)
    case streamingTranscription(VoiceInkProviderKind)
    case directTranscription

    public func requestPrompt(_ prompt: String?) -> String? {
        guard acceptsPrompt else { return nil }
        return Self.nonBlankRequestPrompt(prompt)
    }

    public static func nonBlankRequestPrompt(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt
    }

    private var acceptsPrompt: Bool {
        switch self {
        case .recordedFileTranscription(let provider):
            return provider.transcriptionTransport == .openAICompatible
                || provider == .assemblyAI
                || provider == .localWhisper
        case .streamingTranscription(.assemblyAI),
             .directTranscription:
            return true
        case .streamingTranscription:
            return false
        }
    }
}

public enum VoiceInkPreparedTranscriptRole: Sendable {
    case cleanedText
    case wordReplacedText
}

public struct VoiceInkTranscriptionRunPreparedText: Equatable, Sendable {
    public let filteredText: String
    public let preparedText: VoiceInkPreparedTranscriptionText

    public var textForWordReplacement: String {
        preparedText.textForWordReplacement
    }

    public var wordReplacedText: String {
        preparedText.wordReplacedText
    }

    public var cleanedText: String {
        preparedText.cleanedText
    }

    public init(
        filteredText: String,
        preparedText: VoiceInkPreparedTranscriptionText
    ) {
        self.filteredText = filteredText
        self.preparedText = preparedText
    }

    public func transcript(for role: VoiceInkPreparedTranscriptRole) -> String {
        switch role {
        case .cleanedText:
            return cleanedText
        case .wordReplacedText:
            return wordReplacedText
        }
    }

    public func shouldSkipPostProcessing(
        configuration: VoiceInkPostProcessingSkipConfiguration?,
        promptTriggerForcesPostProcessing: Bool = false,
        transcriptRole: VoiceInkPreparedTranscriptRole = .cleanedText
    ) -> Bool {
        guard let configuration else {
            return false
        }

        return VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: transcript(for: transcriptRole),
            configuration: configuration,
            promptTriggerForcesPostProcessing: promptTriggerForcesPostProcessing
        )
    }
}

public struct VoiceInkTranscriptionEnhancementTextPlan: Equatable, Sendable {
    public let filteredText: String?
    public let textForEnhancement: String
    public let cleanedText: String

    public init(
        filteredText: String? = nil,
        textForEnhancement: String,
        cleanedText: String
    ) {
        self.filteredText = filteredText
        self.textForEnhancement = textForEnhancement
        self.cleanedText = cleanedText
    }

    public func shouldSkipEnhancement(
        configuration: VoiceInkPostProcessingSkipConfiguration?,
        promptTriggerForcesEnhancement: Bool = false
    ) -> Bool {
        guard let configuration else {
            return false
        }

        return VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: textForEnhancement,
            configuration: configuration,
            promptTriggerForcesPostProcessing: promptTriggerForcesEnhancement
        )
    }

    public func enhancementRequest(
        isEnhancementEnabled: Bool,
        isEnhancementConfigured: Bool,
        promptDetectionResult: VoiceInkPromptDetectionResult? = nil,
        skipConfiguration: VoiceInkPostProcessingSkipConfiguration? = nil
    ) -> VoiceInkTranscriptionEnhancementRequest? {
        guard isEnhancementEnabled, isEnhancementConfigured else {
            return nil
        }

        let promptTriggerForcesEnhancement = promptDetectionResult?.shouldEnableAI == true
        guard !shouldSkipEnhancement(
            configuration: skipConfiguration,
            promptTriggerForcesEnhancement: promptTriggerForcesEnhancement
        ) else {
            return nil
        }

        return VoiceInkTranscriptionEnhancementRequest(
            text: promptDetectionResult?.processedText ?? textForEnhancement
        )
    }
}

public struct VoiceInkTranscriptionEnhancementRequest: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum VoiceInkTranscriptionRunPreparation {
    public static func prepareRawText(
        _ rawText: String,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration,
        whitespacePolicy: VoiceInkTranscriptionOutputWhitespacePolicy = .collapseRuns,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> VoiceInkTranscriptionRunPreparedText {
        let filteredText = cleanupConfiguration.filterRawOutput(
            rawText,
            whitespacePolicy: whitespacePolicy
        )
        return prepareFilteredText(
            filteredText,
            cleanupConfiguration: cleanupConfiguration,
            normalizeParagraphSpacingBeforeFormatting: normalizeParagraphSpacingBeforeFormatting,
            applyingWordReplacements: wordReplacement
        )
    }

    public static func prepareFilteredText(
        _ filteredText: String,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> VoiceInkTranscriptionRunPreparedText {
        VoiceInkTranscriptionRunPreparedText(
            filteredText: filteredText,
            preparedText: cleanupConfiguration.prepareFilteredText(
                filteredText,
                normalizeParagraphSpacingBeforeFormatting: normalizeParagraphSpacingBeforeFormatting,
                applyingWordReplacements: wordReplacement
            )
        )
    }

    public static func prepareAudioFileText(
        _ rawText: String,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> VoiceInkTranscriptionEnhancementTextPlan {
        prepareRawTextForEnhancement(
            rawText,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: wordReplacement
        )
    }

    public static func prepareRawTextForEnhancement(
        _ rawText: String,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration,
        whitespacePolicy: VoiceInkTranscriptionOutputWhitespacePolicy = .collapseRuns,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> VoiceInkTranscriptionEnhancementTextPlan {
        let preparedText = prepareRawText(
            rawText,
            cleanupConfiguration: cleanupConfiguration,
            whitespacePolicy: whitespacePolicy,
            normalizeParagraphSpacingBeforeFormatting: normalizeParagraphSpacingBeforeFormatting,
            applyingWordReplacements: wordReplacement
        )

        return textPlan(from: preparedText)
    }

    public static func prepareFilteredTextForEnhancement(
        _ filteredText: String,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> VoiceInkTranscriptionEnhancementTextPlan {
        let preparedText = prepareFilteredText(
            filteredText,
            cleanupConfiguration: cleanupConfiguration,
            normalizeParagraphSpacingBeforeFormatting: normalizeParagraphSpacingBeforeFormatting,
            applyingWordReplacements: wordReplacement
        )

        return textPlan(from: preparedText)
    }

    private static func textPlan(
        from preparedText: VoiceInkTranscriptionRunPreparedText
    ) -> VoiceInkTranscriptionEnhancementTextPlan {
        VoiceInkTranscriptionEnhancementTextPlan(
            filteredText: preparedText.filteredText,
            textForEnhancement: preparedText.wordReplacedText,
            cleanedText: preparedText.cleanedText
        )
    }
}
