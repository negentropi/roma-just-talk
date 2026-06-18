import Foundation

public struct VoiceInkTranscriptionRunResult: Equatable, Sendable {
    public let cleanedText: String
    public let finalText: String
    public let transcriptionModelName: String
    public let aiEnhancementModelName: String?
    public let postProcessingError: String?
    public let postProcessingSucceeded: Bool

    public var enhancedText: String? {
        finalText == cleanedText ? nil : finalText
    }

    public init(
        cleanedText: String,
        finalText: String,
        transcriptionModelName: String,
        aiEnhancementModelName: String?,
        postProcessingError: String?,
        postProcessingSucceeded: Bool
    ) {
        self.cleanedText = cleanedText
        self.finalText = finalText
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.postProcessingError = postProcessingError
        self.postProcessingSucceeded = postProcessingSucceeded
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

    public init(postProcessor: @escaping PostProcessor) {
        self.postProcessor = postProcessor
    }

    public init(postProcessingClient: VoiceInkPostProcessingClient = VoiceInkPostProcessingClient()) {
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
        postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration? = nil,
        promptTriggerForcesPostProcessing: Bool = false,
        transcriptionLanguage: String? = nil,
        transcriptionPrompt: String? = nil,
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
        let rawText = try await transcriptionService.transcribeAudioFile(
            apiKey: usableAPIKey,
            model: model,
            fileURL: fileURL,
            language: VoiceInkTranscriptionLanguageSupport.requestLanguage(transcriptionLanguage),
            prompt: transcriptionPrompt
        )

        guard provider.transcriptionEmptyTextPolicy.accepts(rawText) else {
            throw VoiceInkTranscriptionRunError.noTranscriptionReturned
        }

        let filteredText = cleanupConfiguration.filterRawOutput(
            rawText,
            whitespacePolicy: .preserveParagraphs
        )
        let normalizedText = VoiceInkTranscriptTextNormalizer.normalizeParagraphSpacing(filteredText)
        let formattedText = cleanupConfiguration.shouldFormatParagraphs
            ? VoiceInkTranscriptParagraphFormatter.format(normalizedText)
            : normalizedText
        let cleanedText = cleanupConfiguration.applyTextPreferences(
            formattedText,
        )
        let shouldSkipPostProcessing = postProcessingSkipConfiguration.map {
            VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
                transcript: cleanedText,
                configuration: $0,
                promptTriggerForcesPostProcessing: promptTriggerForcesPostProcessing
            )
        } ?? false
        let aiEnhancementModelName = configuration.isPostProcessingEnabled && !shouldSkipPostProcessing
            ? configuration.postProcessingModel
            : nil

        var finalText = cleanedText
        var postProcessingError: String? = nil
        var postProcessingSucceeded = false

        if configuration.isPostProcessingEnabled, !shouldSkipPostProcessing {
            let prompt = configuration.prompt
            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let llmProvider = configuration.postProcessingProvider
                let llmKey = await apiKeyProvider(llmProvider)
                let llmModel = configuration.postProcessingModel

                if let usableLLMKey = VoiceInkProviderCredential.nonBlank(llmKey) {
                    do {
                        finalText = try await postProcessor(VoiceInkPostProcessingJob(
                            provider: llmProvider,
                            apiKey: usableLLMKey,
                            model: llmModel,
                            prompt: prompt,
                            transcript: cleanedText
                        ))
                        postProcessingSucceeded = true
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
            postProcessingError: postProcessingError,
            postProcessingSucceeded: postProcessingSucceeded
        )
    }
}
