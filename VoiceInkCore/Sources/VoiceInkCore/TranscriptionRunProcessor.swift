import Foundation

public enum VoiceInkErrorDescription {
    public static func text(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

public enum VoiceInkEngineError: Error, Identifiable, Sendable {
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

extension VoiceInkEngineError: LocalizedError {
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

public struct VoiceInkAIEnhancementResult: Equatable, Sendable {
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
    ) -> VoiceInkAIEnhancementResult {
        VoiceInkAIEnhancementResult(
            text: text,
            duration: endDate.timeIntervalSince(startDate),
            modelName: modelName,
            promptName: promptName,
            requestSystemMessage: requestSystemMessage,
            requestUserMessage: requestUserMessage
        )
    }
}

public struct VoiceInkTranscriptionRunResult: Equatable, Sendable {
    public let cleanedText: String
    public let finalText: String
    public let transcriptionModelName: String
    public let aiEnhancementModelName: String?
    public let transcriptionDuration: TimeInterval?
    public let postProcessingResult: VoiceInkAIEnhancementResult?
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
        postProcessingResult: VoiceInkAIEnhancementResult? = nil,
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

public enum VoiceInkTranscriptionRunError: LocalizedError, Equatable {
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

public struct VoiceInkPostProcessingJob: Equatable, Sendable {
    public let provider: VoiceInkProviderKind
    public let apiKey: String
    public let model: String
    public let prompt: String
    public let transcript: String

    public init(
        provider: VoiceInkProviderKind,
        apiKey: String,
        model: String,
        prompt: String,
        transcript: String
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.prompt = prompt
        self.transcript = transcript
    }
}

struct VoiceInkPostProcessingRequest: Equatable, Sendable {
    static let defaultTemperature = 0.2

    private let messages: [VoiceInkOpenAICompatibleChatMessage]
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
            VoiceInkOpenAICompatibleChatMessage(
                role: "system",
                content: VoiceInkAIRequestPrompts.postProcessingSystemPrompt
            ),
            VoiceInkOpenAICompatibleChatMessage(
                role: "user",
                content: VoiceInkAIRequestPrompts.postProcessingUserPrompt(
                    prompt: prompt,
                    transcript: transcript
                )
            )
        ]
        self.temperature = temperature
    }

    func applyRuntimeState<Result>(
        execute: ([VoiceInkOpenAICompatibleChatMessage], Double) async throws -> Result
    ) async throws -> Result {
        try await execute(messages, temperature)
    }

    static func finalizedTranscript(
        from responseText: String,
        fallbackTranscript: String
    ) -> String {
        let filteredText = VoiceInkAIEnhancementOutputFilter.filter(responseText)
        return filteredText.isEmpty ? fallbackTranscript : filteredText
    }
}

public struct VoiceInkPostProcessingClient: Sendable {
    private let client: VoiceInkOpenAICompatibleClient

    public init(client: VoiceInkOpenAICompatibleClient = VoiceInkOpenAICompatibleClient()) {
        self.client = client
    }

    public func postProcessTranscript(
        provider: VoiceInkProviderKind,
        apiKey: String,
        model: String,
        prompt: String,
        transcript: String
    ) async throws -> String {
        guard let request = VoiceInkPostProcessingRequest(prompt: prompt, transcript: transcript) else {
            return transcript
        }
        let result = try await request.applyRuntimeState { messages, temperature in
            let requestParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
                for: provider.aiModelProvider,
                modelName: model,
                defaultTemperature: temperature
            )

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

        return VoiceInkPostProcessingRequest.finalizedTranscript(
            from: result,
            fallbackTranscript: transcript
        )
    }
}

public struct VoiceInkTranscriptionRunSettings: Equatable, Sendable {
    public let configuration: VoiceInkModeRuntimeConfiguration
    public let cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration
    public let postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration?
    public let transcriptionLanguage: String?
    public let transcriptionPrompt: String?
    public let wordReplacementRules: [VoiceInkWordReplacementRule]
    public let customVocabulary: [String]

    public init(
        configuration: VoiceInkModeRuntimeConfiguration,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration = .disabled,
        postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration? = nil,
        transcriptionLanguage: String? = nil,
        transcriptionPrompt: String? = nil,
        wordReplacementRules: [VoiceInkWordReplacementRule] = [],
        customVocabulary: [String] = []
    ) {
        self.configuration = configuration
        self.cleanupConfiguration = cleanupConfiguration
        self.postProcessingSkipConfiguration = postProcessingSkipConfiguration
        self.transcriptionLanguage = transcriptionLanguage
        self.transcriptionPrompt = transcriptionPrompt
        self.wordReplacementRules = wordReplacementRules
        self.customVocabulary = customVocabulary
    }

    public func transcribe(
        fileURL: URL,
        processor: VoiceInkTranscriptionRunProcessor,
        apiKeyProvider: VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        transcriptionServiceProvider: VoiceInkTranscriptionRunProcessor.TranscriptionServiceProvider
    ) async throws -> VoiceInkTranscriptionRunResult {
        try await processor.transcribe(
            fileURL: fileURL,
            configuration: configuration,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: { text in
                VoiceInkWordReplacementEngine.apply(wordReplacementRules, to: text)
            },
            postProcessingSkipConfiguration: postProcessingSkipConfiguration,
            transcriptionLanguage: transcriptionLanguage,
            transcriptionPrompt: transcriptionPrompt,
            customVocabulary: customVocabulary,
            apiKeyProvider: apiKeyProvider,
            transcriptionServiceProvider: transcriptionServiceProvider
        )
    }
}

public struct VoiceInkIOSAppSettingsRunSnapshot {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let selectedTranscriptionLanguage: String
    public let wordReplacementRules: [VoiceInkWordReplacementRule]
    public let customVocabulary: [String]

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String,
        wordReplacementRules: [VoiceInkWordReplacementRule],
        customVocabulary: [String]
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.wordReplacementRules = wordReplacementRules
        self.customVocabulary = customVocabulary
    }

    public func transcriptionRunSettings(defaults: UserDefaults = .standard) -> VoiceInkTranscriptionRunSettings {
        VoiceInkTranscriptionRunSettings(
            configuration: modes.runtimeConfiguration(selectedModeId: selectedModeId),
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration.current(in: defaults),
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration.current(in: defaults),
            transcriptionLanguage: selectedTranscriptionLanguage,
            transcriptionPrompt: VoiceInkTranscriptionPromptPreference.localWhisperPrompt(
                from: defaults,
                fallback: VoiceInkLocalWhisperPromptCatalog.prompt(
                    for: selectedTranscriptionLanguage,
                    customPrompts: VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults)
                )
            ),
            wordReplacementRules: wordReplacementRules,
            customVocabulary: customVocabulary
        )
    }
}

public struct VoiceInkTranscriptionRunProcessor {
    public typealias APIKeyProvider = (VoiceInkProviderKind) async -> String
    public typealias TranscriptionServiceProvider = (VoiceInkProviderKind) -> any VoiceInkAudioTranscriptionService
    public typealias PostProcessor = (VoiceInkPostProcessingJob) async throws -> String

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
        postProcessingClient: VoiceInkPostProcessingClient = VoiceInkPostProcessingClient(),
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.currentDate = currentDate
        self.postProcessor = { job in
            try await postProcessingClient.postProcessTranscript(
                provider: job.provider,
                apiKey: job.apiKey,
                model: job.model,
                prompt: job.prompt,
                transcript: job.transcript
            )
        }
    }

    public func transcribe(
        fileURL: URL,
        configuration: VoiceInkModeRuntimeConfiguration,
        cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration = .disabled,
        applyingWordReplacements wordReplacement: (String) -> String = { $0 },
        postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration? = nil,
        promptTriggerForcesPostProcessing: Bool = false,
        transcriptionLanguage: String? = nil,
        transcriptionPrompt: String? = nil,
        customVocabulary: [String] = [],
        apiKeyProvider: APIKeyProvider,
        transcriptionServiceProvider: TranscriptionServiceProvider
    ) async throws -> VoiceInkTranscriptionRunResult {
        let provider = configuration.transcriptionProvider
        let apiKey = await apiKeyProvider(provider)
        let model = configuration.transcriptionModel

        guard let usableAPIKey = VoiceInkProviderCredential.nonBlank(apiKey) else {
            throw VoiceInkTranscriptionRunError.noAPIKey
        }

        let transcriptionService = transcriptionServiceProvider(provider)
        let transcriptionStart = currentDate()
        let rawText = try await transcriptionService.transcribeAudioFile(
            apiKey: usableAPIKey,
            model: model,
            fileURL: fileURL,
            language: VoiceInkTranscriptionLanguageSupport.requestLanguage(transcriptionLanguage),
            prompt: VoiceInkTranscriptionPromptUse.recordedFileTranscription(provider).requestPrompt(transcriptionPrompt),
            customVocabulary: VoiceInkCustomVocabularyTerms.normalized(
                customVocabulary,
                for: .batchTranscription(provider)
            )
        )
        let transcriptionDuration = currentDate().timeIntervalSince(transcriptionStart)

        guard provider.transcriptionEmptyTextPolicy.accepts(rawText) else {
            throw VoiceInkTranscriptionRunError.noTranscriptionReturned
        }

        let preparedRunText = VoiceInkTranscriptionRunPreparation.prepareRawText(
            rawText,
            cleanupConfiguration: cleanupConfiguration,
            whitespacePolicy: .preserveParagraphs,
            normalizeParagraphSpacingBeforeFormatting: true,
            applyingWordReplacements: wordReplacement
        )
        let cleanedText = preparedRunText.cleanedText
        let shouldSkipPostProcessing = preparedRunText.shouldSkipPostProcessing(
            configuration: postProcessingSkipConfiguration,
            promptTriggerForcesPostProcessing: promptTriggerForcesPostProcessing
        )
        let aiEnhancementModelName = configuration.isPostProcessingEnabled && !shouldSkipPostProcessing
            ? configuration.postProcessingModel
            : nil

        var finalText = cleanedText
        var postProcessingResult: VoiceInkAIEnhancementResult? = nil
        var postProcessingError: String? = nil

        if configuration.isPostProcessingEnabled, !shouldSkipPostProcessing {
            let prompt = configuration.prompt
            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let llmProvider = configuration.postProcessingProvider
                let llmKey = await apiKeyProvider(llmProvider)
                let llmModel = configuration.postProcessingModel

                if let usableLLMKey = VoiceInkProviderCredential.nonBlank(llmKey) {
                    do {
                        let enhancementStart = currentDate()
                        let enhancedText = try await postProcessor(VoiceInkPostProcessingJob(
                            provider: llmProvider,
                            apiKey: usableLLMKey,
                            model: llmModel,
                            prompt: prompt,
                            transcript: cleanedText
                        ))
                        let enhancementEnd = currentDate()
                        postProcessingResult = VoiceInkAIEnhancementResult.completed(
                            text: enhancedText,
                            startedAt: enhancementStart,
                            endedAt: enhancementEnd,
                            modelName: llmModel,
                            promptName: nil,
                            requestSystemMessage: nil,
                            requestUserMessage: nil
                        )
                        finalText = enhancedText
                    } catch {
                        postProcessingError = VoiceInkPostProcessingFailurePresentation.postProcessingFailureText(
                            reason: VoiceInkErrorDescription.text(for: error)
                        )
                        finalText = cleanedText
                    }
                }
            }
        }

        return VoiceInkTranscriptionRunResult(
            cleanedText: cleanedText,
            finalText: finalText,
            transcriptionModelName: model,
            aiEnhancementModelName: aiEnhancementModelName,
            transcriptionDuration: transcriptionDuration,
            postProcessingResult: postProcessingResult,
            postProcessingError: postProcessingError
        )
    }
}
