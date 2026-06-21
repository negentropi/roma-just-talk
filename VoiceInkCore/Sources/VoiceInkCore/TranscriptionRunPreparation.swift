import Foundation

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

public struct VoiceInkAudioFileTranscriptionTextPlan: Equatable, Sendable {
    public let textForEnhancement: String
    public let cleanedText: String

    public init(textForEnhancement: String, cleanedText: String) {
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
    ) -> VoiceInkAudioFileTranscriptionTextPlan {
        let preparedText = prepareRawText(
            rawText,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: wordReplacement
        )

        return VoiceInkAudioFileTranscriptionTextPlan(
            textForEnhancement: preparedText.wordReplacedText,
            cleanedText: preparedText.cleanedText
        )
    }
}
