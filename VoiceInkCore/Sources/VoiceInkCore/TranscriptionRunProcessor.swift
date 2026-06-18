import Foundation

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
            prompt: transcriptionPrompt,
            customVocabulary: VoiceInkCustomVocabularyTerms.normalized(customVocabulary)
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
                        let enhancementDuration = currentDate().timeIntervalSince(enhancementStart)
                        postProcessingResult = VoiceInkAIEnhancementResult(
                            text: enhancedText,
                            duration: enhancementDuration,
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
