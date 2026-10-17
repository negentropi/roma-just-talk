import Foundation
import NaturalLanguage

public struct RomaPostProcessingSkipConfiguration: Equatable, Sendable {
    public static func current(in defaults: UserDefaults = .standard) -> RomaPostProcessingSkipConfiguration {
        RomaPostProcessingSkipConfiguration(
            isEnabled: defaults.object(forKey: RomaUserDefaultsKey.skipShortEnhancement) as? Bool
                ?? RomaPreferenceDefault.skipShortEnhancement,
            wordThreshold: defaults.object(forKey: RomaUserDefaultsKey.shortEnhancementWordThreshold) as? Int
                ?? RomaPreferenceDefault.shortEnhancementWordThreshold
        )
    }

    public let isEnabled: Bool
    public let wordThreshold: Int

    public init(isEnabled: Bool, wordThreshold: Int) {
        self.isEnabled = isEnabled
        self.wordThreshold = wordThreshold > 0
            ? wordThreshold
            : RomaPreferenceDefault.shortEnhancementWordThreshold
    }
}

public enum RomaPostProcessingSkipPolicy {
    public static func shouldSkipPostProcessing(
        transcript: String,
        configuration: RomaPostProcessingSkipConfiguration,
        promptTriggerForcesPostProcessing: Bool
    ) -> Bool {
        guard configuration.isEnabled, !promptTriggerForcesPostProcessing else {
            return false
        }

        return RomaWordCounter.count(in: transcript) <= configuration.wordThreshold
    }
}

public enum RomaWordCounter {
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

public enum RomaTranscriptionPromptUse: Equatable, Sendable {
    case recordedFileTranscription(RomaProviderKind)
    case streamingTranscription(RomaProviderKind)
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

public enum RomaPreparedTranscriptRole: Sendable {
    case cleanedText
    case wordReplacedText
}

public struct RomaTranscriptionRunPreparedText: Equatable, Sendable {
    public let filteredText: String
    public let preparedText: RomaPreparedTranscriptionText

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
        preparedText: RomaPreparedTranscriptionText
    ) {
        self.filteredText = filteredText
        self.preparedText = preparedText
    }

    public func transcript(for role: RomaPreparedTranscriptRole) -> String {
        switch role {
        case .cleanedText:
            return cleanedText
        case .wordReplacedText:
            return wordReplacedText
        }
    }

    public func shouldSkipPostProcessing(
        configuration: RomaPostProcessingSkipConfiguration?,
        promptTriggerForcesPostProcessing: Bool = false,
        transcriptRole: RomaPreparedTranscriptRole = .cleanedText
    ) -> Bool {
        guard let configuration else {
            return false
        }

        return RomaPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: transcript(for: transcriptRole),
            configuration: configuration,
            promptTriggerForcesPostProcessing: promptTriggerForcesPostProcessing
        )
    }
}

public struct RomaTranscriptionEnhancementTextPlan: Equatable, Sendable {
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
        configuration: RomaPostProcessingSkipConfiguration?,
        promptTriggerForcesEnhancement: Bool = false
    ) -> Bool {
        guard let configuration else {
            return false
        }

        return RomaPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: textForEnhancement,
            configuration: configuration,
            promptTriggerForcesPostProcessing: promptTriggerForcesEnhancement
        )
    }

    public func enhancementRequest(
        isEnhancementEnabled: Bool,
        isEnhancementConfigured: Bool,
        promptDetectionResult: RomaPromptDetectionResult? = nil,
        skipConfiguration: RomaPostProcessingSkipConfiguration? = nil
    ) -> RomaTranscriptionEnhancementRequest? {
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

        return RomaTranscriptionEnhancementRequest(
            text: promptDetectionResult?.processedText ?? textForEnhancement
        )
    }
}

public struct RomaTranscriptionEnhancementRequest: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum RomaTranscriptionRunPreparation {
    public static func prepareRawText(
        _ rawText: String,
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration,
        whitespacePolicy: RomaTranscriptionOutputWhitespacePolicy = .collapseRuns,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> RomaTranscriptionRunPreparedText {
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
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> RomaTranscriptionRunPreparedText {
        RomaTranscriptionRunPreparedText(
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
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> RomaTranscriptionEnhancementTextPlan {
        prepareRawTextForEnhancement(
            rawText,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: wordReplacement
        )
    }

    public static func prepareRawTextForEnhancement(
        _ rawText: String,
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration,
        whitespacePolicy: RomaTranscriptionOutputWhitespacePolicy = .collapseRuns,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> RomaTranscriptionEnhancementTextPlan {
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
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration,
        normalizeParagraphSpacingBeforeFormatting: Bool = false,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 }
    ) -> RomaTranscriptionEnhancementTextPlan {
        let preparedText = prepareFilteredText(
            filteredText,
            cleanupConfiguration: cleanupConfiguration,
            normalizeParagraphSpacingBeforeFormatting: normalizeParagraphSpacingBeforeFormatting,
            applyingWordReplacements: wordReplacement
        )

        return textPlan(from: preparedText)
    }

    private static func textPlan(
        from preparedText: RomaTranscriptionRunPreparedText
    ) -> RomaTranscriptionEnhancementTextPlan {
        RomaTranscriptionEnhancementTextPlan(
            filteredText: preparedText.filteredText,
            textForEnhancement: preparedText.wordReplacedText,
            cleanedText: preparedText.cleanedText
        )
    }
}

public enum RomaErrorDescription {
    public static func text(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

public enum RomaEngineError: Error, Identifiable, Sendable {
    case modelLoadFailed
    case transcriptionFailed
    case whisperCoreFailed
    case unzipFailed
    case unknownError
    case localModelUnavailable
    case localModelLoadFailed
    case audioProcessingFailed
    case whisperTranscriptionFailed
    case audioFileNotFound
    case noTranscriptionModelSelected

    public var id: String { UUID().uuidString }
}

extension RomaEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load the transcription model."
        case .transcriptionFailed:
            return "Failed to transcribe the audio."
        case .whisperCoreFailed:
            return "The core transcription engine failed."
        case .unzipFailed:
            return "Failed to unzip the downloaded Core ML model."
        case .unknownError:
            return "An unknown error occurred."
        case .localModelUnavailable:
            return "No local Whisper model is available. Please download a model first."
        case .localModelLoadFailed:
            return "Failed to load the Whisper model."
        case .audioProcessingFailed:
            return "Failed to process audio file for transcription."
        case .whisperTranscriptionFailed:
            return "Whisper transcription failed."
        case .audioFileNotFound:
            return "Audio file not found"
        case .noTranscriptionModelSelected:
            return "No transcription model selected"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .modelLoadFailed:
            return "Try selecting a different model or redownloading the current model."
        case .transcriptionFailed:
            return "Check the default model try again. If the problem persists, try a different model."
        case .whisperCoreFailed:
            return "This can happen due to an issue with the audio recording or insufficient system resources. Please try again, or restart the app."
        case .unzipFailed:
            return "The downloaded Core ML model archive might be corrupted. Try deleting the model and downloading it again. Check available disk space."
        case .unknownError:
            return "Please restart the application. If the problem persists, contact support."
        case .localModelUnavailable:
            return "Download a local Whisper model before recording or retrying."
        case .localModelLoadFailed:
            return "Try redownloading the selected Whisper model."
        case .audioProcessingFailed:
            return "Check that the recording file exists and is a valid WAV recording."
        case .whisperTranscriptionFailed:
            return "Try recording again or switch to a different local model."
        case .audioFileNotFound:
            return "Keep the saved recording available before retrying transcription."
        case .noTranscriptionModelSelected:
            return "Select a transcription model before importing audio."
        }
    }
}

public struct RomaAIEnhancementResult: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let modelName: String?
    public let promptName: String?
    public let requestSystemMessage: String?
    public let requestUserMessage: String?

    public init(
        text: String,
        duration: TimeInterval,
        modelName: String?,
        promptName: String?,
        requestSystemMessage: String?,
        requestUserMessage: String?
    ) {
        self.text = text
        self.duration = duration
        self.modelName = modelName
        self.promptName = promptName
        self.requestSystemMessage = requestSystemMessage
        self.requestUserMessage = requestUserMessage
    }

    public static func completed(
        text: String,
        startedAt startDate: Date,
        endedAt endDate: Date,
        modelName: String?,
        promptName: String?,
        requestSystemMessage: String?,
        requestUserMessage: String?
    ) -> RomaAIEnhancementResult {
        RomaAIEnhancementResult(
            text: text,
            duration: endDate.timeIntervalSince(startDate),
            modelName: modelName,
            promptName: promptName,
            requestSystemMessage: requestSystemMessage,
            requestUserMessage: requestUserMessage
        )
    }
}

public struct RomaTranscriptionRunResult: Equatable, Sendable {
    public let cleanedText: String
    public let finalText: String
    public let transcriptionModelName: String
    public let aiEnhancementModelName: String?
    public let transcriptionDuration: TimeInterval?
    public let postProcessingResult: RomaAIEnhancementResult?
    public let postProcessingError: String?

    public var enhancedText: String? {
        finalText == cleanedText ? nil : finalText
    }

    public var postProcessingSucceeded: Bool {
        postProcessingResult != nil
    }

    public var enhancementDuration: TimeInterval? {
        postProcessingResult?.duration
    }

    public init(
        cleanedText: String,
        finalText: String,
        transcriptionModelName: String,
        aiEnhancementModelName: String?,
        transcriptionDuration: TimeInterval? = nil,
        postProcessingResult: RomaAIEnhancementResult? = nil,
        postProcessingError: String?
    ) {
        self.cleanedText = cleanedText
        self.finalText = finalText
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.transcriptionDuration = transcriptionDuration
        self.postProcessingResult = postProcessingResult
        self.postProcessingError = postProcessingError
    }
}

public enum RomaTranscriptionRunError: LocalizedError, Equatable {
    case noAPIKey
    case noTranscriptionReturned

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .noTranscriptionReturned:
            return "The API returned an empty or invalid response."
        }
    }
}

public struct RomaPostProcessingJob: Equatable, Sendable {
    public let provider: RomaProviderKind
    public let apiKey: String
    public let model: String
    public let prompt: String
    public let transcript: String
    public let executionConfiguration: RomaPostProcessingExecutionConfiguration

    public init(
        provider: RomaProviderKind,
        apiKey: String,
        model: String,
        prompt: String,
        transcript: String,
        executionConfiguration: RomaPostProcessingExecutionConfiguration = .default
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.prompt = prompt
        self.transcript = transcript
        self.executionConfiguration = executionConfiguration
    }
}

struct RomaPostProcessingRequest: Equatable, Sendable {
    static let defaultTemperature = 0.2

    private let messages: [RomaOpenAICompatibleChatMessage]
    private let temperature: Double

    init?(
        prompt: String,
        transcript: String,
        temperature: Double = Self.defaultTemperature
    ) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.messages = [
            RomaOpenAICompatibleChatMessage(
                role: "system",
                content: RomaAIRequestPrompts.postProcessingSystemPrompt
            ),
            RomaOpenAICompatibleChatMessage(
                role: "user",
                content: RomaAIRequestPrompts.postProcessingUserPrompt(
                    prompt: prompt,
                    transcript: transcript
                )
            )
        ]
        self.temperature = temperature
    }

    func applyRuntimeState<Result>(
        execute: ([RomaOpenAICompatibleChatMessage], Double) async throws -> Result
    ) async throws -> Result {
        try await execute(messages, temperature)
    }

    static func finalizedTranscript(
        from responseText: String,
        fallbackTranscript: String
    ) -> String {
        let filteredText = RomaAIEnhancementOutputFilter.filter(responseText)
        return filteredText.isEmpty ? fallbackTranscript : filteredText
    }
}

public struct RomaPostProcessingClient: Sendable {
    private let client: RomaOpenAICompatibleClient
    private let anthropicClient: RomaAnthropicClient

    public init(
        client: RomaOpenAICompatibleClient = RomaOpenAICompatibleClient(),
        anthropicClient: RomaAnthropicClient = RomaAnthropicClient()
    ) {
        self.client = client
        self.anthropicClient = anthropicClient
    }

    public func postProcessTranscript(
        provider: RomaProviderKind,
        apiKey: String,
        model: String,
        prompt: String,
        transcript: String,
        executionConfiguration: RomaPostProcessingExecutionConfiguration = .default
    ) async throws -> String {
        guard let request = RomaPostProcessingRequest(prompt: prompt, transcript: transcript) else {
            return transcript
        }
        let result = try await RomaPostProcessingExecutionPolicy.execute(
            configuration: executionConfiguration
        ) {
            try await request.applyRuntimeState { messages, temperature in
                let requestParameters = RomaAIReasoningConfig.chatRequestParameters(
                    for: provider.aiModelProvider,
                    modelName: model,
                    defaultTemperature: temperature
                )

                if provider == .anthropic {
                    return try await anthropicClient.chatCompletion(
                        baseURL: provider.apiBaseURL,
                        apiKey: apiKey,
                        model: model,
                        messages: messages
                    )
                }

                if provider == .customAI,
                   let requestURL = provider.postProcessingChatCompletionsURL {
                    return try await client.chatCompletion(
                        requestURL: requestURL,
                        apiKey: apiKey,
                        model: model,
                        messages: messages,
                        temperature: requestParameters.temperature,
                        reasoningEffort: requestParameters.reasoningEffort,
                        extraBodyParameters: requestParameters.extraBodyParameters
                    )
                }

                return try await client.chatCompletion(
                    baseURL: provider.apiBaseURL,
                    apiKey: apiKey,
                    model: model,
                    messages: messages,
                    temperature: requestParameters.temperature,
                    reasoningEffort: requestParameters.reasoningEffort,
                    extraBodyParameters: requestParameters.extraBodyParameters
                )
            }
        }

        return RomaPostProcessingRequest.finalizedTranscript(
            from: result,
            fallbackTranscript: transcript
        )
    }
}

public struct RomaTranscriptionRunSettings: Equatable, Sendable {
    public let configuration: RomaModeRuntimeConfiguration
    public let cleanupConfiguration: RomaTranscriptionCleanupConfiguration
    public let postProcessingSkipConfiguration: RomaPostProcessingSkipConfiguration?
    public let postProcessingExecutionConfiguration: RomaPostProcessingExecutionConfiguration
    public let transcriptionLanguage: String?
    public let transcriptionPrompt: String?
    public let wordReplacementRules: [RomaWordReplacementRule]
    public let customVocabulary: [String]
    public let promptLibrary: [RomaCustomPrompt]
    public let selectedPromptId: UUID?
    public let enhancementContext: RomaAIEnhancementPromptContext

    public init(
        configuration: RomaModeRuntimeConfiguration,
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration = .disabled,
        postProcessingSkipConfiguration: RomaPostProcessingSkipConfiguration? = nil,
        postProcessingExecutionConfiguration: RomaPostProcessingExecutionConfiguration = .default,
        transcriptionLanguage: String? = nil,
        transcriptionPrompt: String? = nil,
        wordReplacementRules: [RomaWordReplacementRule] = [],
        customVocabulary: [String] = [],
        promptLibrary: [RomaCustomPrompt] = [],
        selectedPromptId: UUID? = nil,
        enhancementContext: RomaAIEnhancementPromptContext = RomaAIEnhancementPromptContext()
    ) {
        self.configuration = configuration
        self.cleanupConfiguration = cleanupConfiguration
        self.postProcessingSkipConfiguration = postProcessingSkipConfiguration
        self.postProcessingExecutionConfiguration = postProcessingExecutionConfiguration
        self.transcriptionLanguage = transcriptionLanguage
        self.transcriptionPrompt = transcriptionPrompt
        self.wordReplacementRules = wordReplacementRules
        self.customVocabulary = customVocabulary
        self.promptLibrary = promptLibrary
        self.selectedPromptId = selectedPromptId
        self.enhancementContext = enhancementContext
    }

    public func selectingPrompt(_ promptId: UUID?, from prompts: [RomaCustomPrompt]) -> Self {
        let prompt = RomaCustomPromptPolicy.activePrompt(
            selectedPromptId: promptId,
            prompts: prompts
        )
        return RomaTranscriptionRunSettings(
            configuration: configuration.applyingPrompt(prompt),
            cleanupConfiguration: cleanupConfiguration,
            postProcessingSkipConfiguration: postProcessingSkipConfiguration,
            postProcessingExecutionConfiguration: postProcessingExecutionConfiguration,
            transcriptionLanguage: transcriptionLanguage,
            transcriptionPrompt: transcriptionPrompt,
            wordReplacementRules: wordReplacementRules,
            customVocabulary: customVocabulary,
            promptLibrary: prompts,
            selectedPromptId: promptId,
            enhancementContext: enhancementContext
        )
    }

    public func applyingEnhancementContext(_ context: RomaAIEnhancementPromptContext) -> Self {
        RomaTranscriptionRunSettings(
            configuration: configuration,
            cleanupConfiguration: cleanupConfiguration,
            postProcessingSkipConfiguration: postProcessingSkipConfiguration,
            postProcessingExecutionConfiguration: postProcessingExecutionConfiguration,
            transcriptionLanguage: transcriptionLanguage,
            transcriptionPrompt: transcriptionPrompt,
            wordReplacementRules: wordReplacementRules,
            customVocabulary: customVocabulary,
            promptLibrary: promptLibrary,
            selectedPromptId: selectedPromptId,
            enhancementContext: context
        )
    }

    public func transcribe(
        fileURL: URL,
        processor: RomaTranscriptionRunProcessor,
        apiKeyProvider: RomaTranscriptionRunProcessor.APIKeyProvider,
        transcriptionServiceProvider: RomaTranscriptionRunProcessor.TranscriptionServiceProvider
    ) async throws -> RomaTranscriptionRunResult {
        try await processor.transcribe(
            fileURL: fileURL,
            configuration: configuration,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: { text in
                RomaWordReplacementEngine.apply(wordReplacementRules, to: text)
            },
            postProcessingSkipConfiguration: postProcessingSkipConfiguration,
            postProcessingExecutionConfiguration: postProcessingExecutionConfiguration,
            promptLibrary: promptLibrary,
            selectedPromptId: selectedPromptId,
            enhancementContext: enhancementContext,
            transcriptionLanguage: transcriptionLanguage,
            transcriptionPrompt: transcriptionPrompt,
            customVocabulary: customVocabulary,
            apiKeyProvider: apiKeyProvider,
            transcriptionServiceProvider: transcriptionServiceProvider
        )
    }

    public func processTranscribedText(
        _ rawText: String,
        transcriptionDuration: TimeInterval? = nil,
        forcePostProcessing: Bool = false,
        processor: RomaTranscriptionRunProcessor,
        apiKeyProvider: RomaTranscriptionRunProcessor.APIKeyProvider
    ) async throws -> RomaTranscriptionRunResult {
        try await processor.processTranscribedText(
            rawText,
            transcriptionModelName: configuration.transcriptionModel,
            transcriptionDuration: transcriptionDuration,
            configuration: configuration,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: { text in
                RomaWordReplacementEngine.apply(wordReplacementRules, to: text)
            },
            postProcessingSkipConfiguration: postProcessingSkipConfiguration,
            postProcessingExecutionConfiguration: postProcessingExecutionConfiguration,
            promptLibrary: promptLibrary,
            selectedPromptId: selectedPromptId,
            enhancementContext: enhancementContext,
            promptTriggerForcesPostProcessing: forcePostProcessing,
            apiKeyProvider: apiKeyProvider
        )
    }
}

public struct RomaIOSAppSettingsRunSnapshot {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let selectedTranscriptionLanguage: String
    public let wordReplacementRules: [RomaWordReplacementRule]
    public let customVocabulary: [String]
    public let additionalLocalWhisperModelNames: [String]
    public let promptLibrary: [RomaCustomPrompt]
    public let recordingPromptOverrideId: UUID?

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String,
        wordReplacementRules: [RomaWordReplacementRule],
        customVocabulary: [String],
        additionalLocalWhisperModelNames: [String] = [],
        promptLibrary: [RomaCustomPrompt] = [],
        recordingPromptOverrideId: UUID? = nil
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.wordReplacementRules = wordReplacementRules
        self.customVocabulary = customVocabulary
        self.additionalLocalWhisperModelNames = additionalLocalWhisperModelNames
        self.promptLibrary = promptLibrary
        self.recordingPromptOverrideId = recordingPromptOverrideId
    }

    public func transcriptionRunSettings(defaults: UserDefaults = .standard) -> RomaTranscriptionRunSettings {
        RomaTranscriptionRunSettings(
            configuration: modes.runtimeConfiguration(
                selectedModeId: selectedModeId,
                additionalLocalWhisperModelNames: additionalLocalWhisperModelNames,
                prompts: promptLibrary,
                recordingPromptOverrideId: recordingPromptOverrideId
            ),
            cleanupConfiguration: RomaTranscriptionCleanupConfiguration.current(in: defaults),
            postProcessingSkipConfiguration: RomaPostProcessingSkipConfiguration.current(in: defaults),
            postProcessingExecutionConfiguration: RomaPostProcessingExecutionConfiguration.current(in: defaults),
            transcriptionLanguage: selectedTranscriptionLanguage,
            transcriptionPrompt: RomaLocalWhisperPromptCatalog.prompt(
                for: selectedTranscriptionLanguage,
                customPrompts: RomaLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults)
            ),
            wordReplacementRules: wordReplacementRules,
            customVocabulary: customVocabulary,
            promptLibrary: promptLibrary,
            selectedPromptId: recordingPromptOverrideId
                ?? modes.activeMode(selectedModeId: selectedModeId)?.selectedPromptId
        )
    }
}

public struct RomaTranscriptionRunProcessor {
    public typealias APIKeyProvider = (RomaProviderKind) async -> String
    public typealias TranscriptionServiceProvider = (RomaProviderKind) -> any RomaAudioTranscriptionService
    public typealias PostProcessor = (RomaPostProcessingJob) async throws -> String

    private let postProcessor: PostProcessor
    private let currentDate: () -> Date

    public init(postProcessor: @escaping PostProcessor) {
        self.currentDate = Date.init
        self.postProcessor = postProcessor
    }

    public init(currentDate: @escaping () -> Date, postProcessor: @escaping PostProcessor) {
        self.currentDate = currentDate
        self.postProcessor = postProcessor
    }

    public init(
        postProcessingClient: RomaPostProcessingClient = RomaPostProcessingClient(),
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.currentDate = currentDate
        self.postProcessor = { job in
            try await postProcessingClient.postProcessTranscript(
                provider: job.provider,
                apiKey: job.apiKey,
                model: job.model,
                prompt: job.prompt,
                transcript: job.transcript,
                executionConfiguration: job.executionConfiguration
            )
        }
    }

    public func transcribe(
        fileURL: URL,
        configuration: RomaModeRuntimeConfiguration,
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration = .disabled,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 },
        postProcessingSkipConfiguration: RomaPostProcessingSkipConfiguration? = nil,
        postProcessingExecutionConfiguration: RomaPostProcessingExecutionConfiguration = .default,
        promptLibrary: [RomaCustomPrompt] = [],
        selectedPromptId: UUID? = nil,
        enhancementContext: RomaAIEnhancementPromptContext = RomaAIEnhancementPromptContext(),
        promptTriggerForcesPostProcessing: Bool = false,
        transcriptionLanguage: String? = nil,
        transcriptionPrompt: String? = nil,
        customVocabulary: [String] = [],
        apiKeyProvider: APIKeyProvider,
        transcriptionServiceProvider: TranscriptionServiceProvider
    ) async throws -> RomaTranscriptionRunResult {
        try Task.checkCancellation()
        let provider = configuration.transcriptionProvider
        let apiKey = await apiKeyProvider(provider)
        try Task.checkCancellation()
        let model = configuration.transcriptionModel

        guard let usableAPIKey = RomaProviderCredential.nonBlank(apiKey) else {
            throw RomaTranscriptionRunError.noAPIKey
        }

        let transcriptionService = transcriptionServiceProvider(provider)
        let transcriptionStart = currentDate()
        let rawText = try await transcriptionService.transcribeAudioFile(
            apiKey: usableAPIKey,
            model: model,
            fileURL: fileURL,
            language: RomaTranscriptionLanguageSupport.requestLanguage(transcriptionLanguage),
            prompt: RomaTranscriptionPromptUse.recordedFileTranscription(provider).requestPrompt(transcriptionPrompt),
            customVocabulary: RomaCustomVocabularyTerms.normalized(
                customVocabulary,
                for: .batchTranscription(provider)
            )
        )
        try Task.checkCancellation()
        let transcriptionDuration = currentDate().timeIntervalSince(transcriptionStart)

        return try await processTranscribedText(
            rawText,
            transcriptionModelName: model,
            transcriptionDuration: transcriptionDuration,
            configuration: configuration,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: wordReplacement,
            postProcessingSkipConfiguration: postProcessingSkipConfiguration,
            postProcessingExecutionConfiguration: postProcessingExecutionConfiguration,
            promptLibrary: promptLibrary,
            selectedPromptId: selectedPromptId,
            enhancementContext: enhancementContext,
            promptTriggerForcesPostProcessing: promptTriggerForcesPostProcessing,
            apiKeyProvider: apiKeyProvider
        )
    }

    public func processTranscribedText(
        _ rawText: String,
        transcriptionModelName: String,
        transcriptionDuration: TimeInterval? = nil,
        configuration: RomaModeRuntimeConfiguration,
        cleanupConfiguration: RomaTranscriptionCleanupConfiguration = .disabled,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 },
        postProcessingSkipConfiguration: RomaPostProcessingSkipConfiguration? = nil,
        postProcessingExecutionConfiguration: RomaPostProcessingExecutionConfiguration = .default,
        promptLibrary: [RomaCustomPrompt] = [],
        selectedPromptId: UUID? = nil,
        enhancementContext: RomaAIEnhancementPromptContext = RomaAIEnhancementPromptContext(),
        promptTriggerForcesPostProcessing: Bool = false,
        apiKeyProvider: APIKeyProvider
    ) async throws -> RomaTranscriptionRunResult {
        try Task.checkCancellation()
        guard configuration.transcriptionProvider.transcriptionEmptyTextPolicy.accepts(rawText) else {
            throw RomaTranscriptionRunError.noTranscriptionReturned
        }

        let preparedRunText = RomaTranscriptionRunPreparation.prepareRawText(
            rawText,
            cleanupConfiguration: cleanupConfiguration,
            whitespacePolicy: .preserveParagraphs,
            normalizeParagraphSpacingBeforeFormatting: true,
            applyingWordReplacements: wordReplacement
        )
        let cleanedText = preparedRunText.cleanedText
        let promptDetection = RomaPromptDetectionPolicy.analyzeText(
            cleanedText,
            prompts: promptLibrary,
            isEnhancementEnabled: configuration.isPostProcessingEnabled,
            selectedPromptId: selectedPromptId
        )
        let selectedPrompt = RomaCustomPromptPolicy.activePrompt(
            selectedPromptId: promptDetection.selectedPromptId ?? selectedPromptId,
            prompts: promptLibrary
        )
        let effectiveConfiguration = configuration.applyingPrompt(
            selectedPrompt,
            forceEnablement: promptDetection.shouldEnableAI
        )
        let shouldForcePostProcessing = promptTriggerForcesPostProcessing || promptDetection.shouldEnableAI
        let shouldSkipPostProcessing = preparedRunText.shouldSkipPostProcessing(
            configuration: postProcessingSkipConfiguration,
            promptTriggerForcesPostProcessing: shouldForcePostProcessing
        )
        let aiEnhancementModelName = effectiveConfiguration.isPostProcessingEnabled && !shouldSkipPostProcessing
            ? effectiveConfiguration.postProcessingModel
            : nil

        var finalText = cleanedText
        var postProcessingResult: RomaAIEnhancementResult? = nil
        var postProcessingError: String? = nil

        if effectiveConfiguration.isPostProcessingEnabled, !shouldSkipPostProcessing {
            let prompt = RomaAIEnhancementPromptBuilder.systemMessage(
                basePrompt: effectiveConfiguration.prompt,
                context: enhancementContext
            )
            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let llmProvider = effectiveConfiguration.postProcessingProvider
                let llmKey = await apiKeyProvider(llmProvider)
                try Task.checkCancellation()
                let llmModel = effectiveConfiguration.postProcessingModel

                if let usableLLMKey = RomaProviderCredential.nonBlank(llmKey) {
                    do {
                        let enhancementStart = currentDate()
                        let enhancedText = try await postProcessor(RomaPostProcessingJob(
                            provider: llmProvider,
                            apiKey: usableLLMKey,
                            model: llmModel,
                            prompt: prompt,
                            transcript: promptDetection.processedText,
                            executionConfiguration: postProcessingExecutionConfiguration
                        ))
                        try Task.checkCancellation()
                        let enhancementEnd = currentDate()
                        postProcessingResult = RomaAIEnhancementResult.completed(
                            text: enhancedText,
                            startedAt: enhancementStart,
                            endedAt: enhancementEnd,
                            modelName: llmModel,
                            promptName: effectiveConfiguration.promptName,
                            requestSystemMessage: nil,
                            requestUserMessage: nil
                        )
                        finalText = enhancedText
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        postProcessingError = RomaPostProcessingFailurePresentation.postProcessingFailureText(
                            reason: RomaErrorDescription.text(for: error)
                        )
                        finalText = cleanedText
                    }
                }
            }
        }

        try Task.checkCancellation()
        return RomaTranscriptionRunResult(
            cleanedText: cleanedText,
            finalText: finalText,
            transcriptionModelName: transcriptionModelName,
            aiEnhancementModelName: aiEnhancementModelName,
            transcriptionDuration: transcriptionDuration,
            postProcessingResult: postProcessingResult,
            postProcessingError: postProcessingError
        )
    }
}
