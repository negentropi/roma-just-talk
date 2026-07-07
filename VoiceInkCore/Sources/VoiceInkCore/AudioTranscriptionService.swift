import Foundation

public protocol VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String
}

public enum VoiceInkCloudTranscriptionError: Error, LocalizedError {
    public static let apiStatusCodeRange: ClosedRange<Int> = 100...599

    case unsupportedProvider
    case missingAPIKey
    case audioFileNotFound
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return VoiceInkTranscriptionRunError.noTranscriptionReturned.errorDescription
        }
    }

    public static func apiRequestFailure(
        from error: NSError,
        matchingErrorDomain errorDomain: String?
    ) -> VoiceInkCloudTranscriptionError? {
        guard let errorDomain,
              error.domain == errorDomain,
              apiStatusCodeRange.contains(error.code) else {
            return nil
        }

        return .apiRequestFailed(
            statusCode: error.code,
            message: apiRequestFailureMessage(from: error)
        )
    }

    public static func apiRequestFailureMessage(from error: NSError) -> String {
        error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
    }

    public static func remoteExecutionFailure(
        from error: Error,
        matchingErrorDomain errorDomain: String?
    ) -> VoiceInkCloudTranscriptionError {
        if let cloudError = error as? VoiceInkCloudTranscriptionError {
            return cloudError
        }

        if let apiError = apiRequestFailure(
            from: error as NSError,
            matchingErrorDomain: errorDomain
        ) {
            return apiError
        }

        return .networkError(error)
    }
}

public struct VoiceInkCloudTranscriptionAudioFile: Equatable, Sendable {
    public let data: Data
    public let fileName: String

    public init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
    }

    public static func load(from url: URL) throws -> VoiceInkCloudTranscriptionAudioFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceInkCloudTranscriptionError.audioFileNotFound
        }

        return VoiceInkCloudTranscriptionAudioFile(
            data: try Data(contentsOf: url),
            fileName: url.lastPathComponent
        )
    }
}

public struct VoiceInkAudioTranscriptionServiceFactory {
    public typealias RemoteServiceFactory = (VoiceInkProviderKind) -> any VoiceInkAudioTranscriptionService
    public typealias LocalWhisperServiceFactory = () -> any VoiceInkAudioTranscriptionService

    private let remoteServiceFactory: RemoteServiceFactory
    private let localWhisperServiceFactory: LocalWhisperServiceFactory

    public init(
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        remoteServiceFactory: @escaping RemoteServiceFactory = { VoiceInkRemoteTranscriptionService(provider: $0) }
    ) {
        self.localWhisperServiceFactory = localWhisperServiceFactory
        self.remoteServiceFactory = remoteServiceFactory
    }

    public func service(for provider: VoiceInkProviderKind) -> any VoiceInkAudioTranscriptionService {
        switch provider.transcriptionServiceKind {
        case .remote:
            return remoteServiceFactory(provider)
        case .localWhisper:
            return localWhisperServiceFactory()
        }
    }
}

public struct VoiceInkRemoteTranscriptionOptions: Equatable, Sendable {
    public static var defaultOpenAICompatibleErrorDomain: String {
        guard let apiErrorDomain = VoiceInkTranscriptionModelProvider.groq.apiErrorDomain else {
            preconditionFailure("Groq provider metadata must define an API error domain")
        }
        return apiErrorDomain
    }

    public let prompt: String?
    public let customVocabulary: [String]
    public let openAICompatibleResponseFormat: String?
    public let openAICompatibleTemperature: String?
    public let openAICompatibleErrorDomain: String
    public let openAICompatibleTimeout: TimeInterval?
    public let openAICompatibleMaxRetries: Int
    public let openAICompatibleAllowsPlainTextFallback: Bool
    public let deepgramParagraphs: Bool?
    public let deepgramDiarize: Bool?
    public let deepgramTimeout: TimeInterval?

    public init(
        prompt: String? = nil,
        customVocabulary: [String] = [],
        openAICompatibleResponseFormat: String? = nil,
        openAICompatibleTemperature: String? = nil,
        openAICompatibleErrorDomain: String = VoiceInkRemoteTranscriptionOptions.defaultOpenAICompatibleErrorDomain,
        openAICompatibleTimeout: TimeInterval? = nil,
        openAICompatibleMaxRetries: Int = 0,
        openAICompatibleAllowsPlainTextFallback: Bool = true,
        deepgramParagraphs: Bool? = nil,
        deepgramDiarize: Bool? = false,
        deepgramTimeout: TimeInterval? = nil
    ) {
        self.prompt = prompt
        self.customVocabulary = customVocabulary
        self.openAICompatibleResponseFormat = openAICompatibleResponseFormat
        self.openAICompatibleTemperature = openAICompatibleTemperature
        self.openAICompatibleErrorDomain = openAICompatibleErrorDomain
        self.openAICompatibleTimeout = openAICompatibleTimeout
        self.openAICompatibleMaxRetries = openAICompatibleMaxRetries
        self.openAICompatibleAllowsPlainTextFallback = openAICompatibleAllowsPlainTextFallback
        self.deepgramParagraphs = deepgramParagraphs
        self.deepgramDiarize = deepgramDiarize
        self.deepgramTimeout = deepgramTimeout
    }

    public static func batchDefaults(
        for provider: VoiceInkTranscriptionModelProvider,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) -> Self {
        let requestPrompt = provider.providerKind.map {
            VoiceInkTranscriptionPromptUse.recordedFileTranscription($0).requestPrompt(prompt)
        } ?? nil
        let normalizedCustomVocabulary = provider.providerKind.map {
            VoiceInkCustomVocabularyTerms.normalized(customVocabulary, for: .batchTranscription($0))
        } ?? []

        switch provider {
        case .groq:
            return Self(
                prompt: requestPrompt,
                openAICompatibleResponseFormat: "json",
                openAICompatibleTemperature: "0",
                openAICompatibleErrorDomain: Self.defaultOpenAICompatibleErrorDomain,
                openAICompatibleTimeout: 60,
                openAICompatibleMaxRetries: 2
            )
        case .openAI:
            return Self(prompt: requestPrompt)
        case .deepgram:
            return Self(
                deepgramParagraphs: true,
                deepgramDiarize: nil,
                deepgramTimeout: 30
            )
        case .soniox, .speechmatics:
            return Self(customVocabulary: normalizedCustomVocabulary)
        case .assemblyAI:
            return Self(
                prompt: requestPrompt,
                customVocabulary: normalizedCustomVocabulary
            )
        case .cartesia, .elevenLabs, .gemini, .mistral, .xai, .local:
            return Self()
        }
    }

    public static func batchDefaults(
        forProviderKind provider: VoiceInkProviderKind,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) -> Self {
        let requestPrompt = VoiceInkTranscriptionPromptUse.recordedFileTranscription(provider).requestPrompt(prompt)
        guard let modelProvider = provider.transcriptionModelProvider else {
            return requestPrompt.map { Self(prompt: $0) } ?? Self()
        }

        return batchDefaults(
            for: modelProvider,
            prompt: requestPrompt,
            customVocabulary: customVocabulary
        )
    }
}

public enum VoiceInkMacOSCloudTranscriptionPolicy {
    typealias TranscriptionTransport = @Sendable (VoiceInkMacOSCloudTranscriptionRequest) async throws -> String

    public static func transcribeAudioData(
        modelProvider: VoiceInkMacOSTranscriptionModelProvider,
        apiKey: String?,
        modelName: String,
        audioData: Data,
        fileName: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        try await transcribeAudioData(
            modelProvider: modelProvider,
            apiKey: apiKey,
            modelName: modelName,
            audioData: audioData,
            fileName: fileName,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary
        ) { request in
            try await VoiceInkRemoteTranscriptionService(provider: request.provider).transcribeAudioData(
                apiKey: request.apiKey,
                model: request.modelName,
                audioData: request.audioData,
                fileName: request.fileName,
                language: request.language,
                options: request.options
            )
        }
    }

    static func transcribeAudioData(
        modelProvider: VoiceInkMacOSTranscriptionModelProvider,
        apiKey: String?,
        modelName: String,
        audioData: Data,
        fileName: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String],
        transport: TranscriptionTransport
    ) async throws -> String {
        guard let usableAPIKey = VoiceInkProviderCredential.nonBlank(apiKey) else {
            throw VoiceInkCloudTranscriptionError.missingAPIKey
        }

        guard let provider = modelProvider.remoteTranscriptionProviderKind else {
            throw VoiceInkCloudTranscriptionError.unsupportedProvider
        }

        let request = VoiceInkMacOSCloudTranscriptionRequest(
            provider: provider,
            apiKey: usableAPIKey,
            modelName: modelName,
            audioData: audioData,
            fileName: fileName,
            language: language,
            options: modelProvider.remoteTranscriptionOptions(
                prompt: prompt,
                customVocabulary: customVocabulary
            )
        )

        do {
            let text = try await transport(request)
            guard modelProvider.acceptsRemoteTranscriptionText(text) else {
                throw VoiceInkCloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch {
            throw VoiceInkCloudTranscriptionError.remoteExecutionFailure(
                from: error,
                matchingErrorDomain: modelProvider.apiErrorDomain
            )
        }
    }
}

struct VoiceInkMacOSCloudTranscriptionRequest: Equatable, Sendable {
    let provider: VoiceInkProviderKind
    let apiKey: String
    let modelName: String
    let audioData: Data
    let fileName: String
    let language: String?
    let options: VoiceInkRemoteTranscriptionOptions
}

public struct VoiceInkPreparedElevenLabsTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkElevenLabsTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkElevenLabsTranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkElevenLabsRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedElevenLabsTranscriptionRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        form.addField(name: "model_id", value: model)
        form.addField(name: "temperature", value: "0.0")
        form.addField(name: "tag_audio_events", value: "false")
        if let language, !language.isEmpty {
            form.addField(name: "language_code", value: language)
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.elevenLabsSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedElevenLabsTranscriptionRequest(request: request, body: form.data)
    }

    public static func makeUserRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.elevenLabsUserURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkElevenLabsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        errorDomain: String = VoiceInkTranscriptionModelProvider.elevenLabs.requiredAPIErrorDomain,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try VoiceInkElevenLabsTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkElevenLabsRequestBuilder.makeUserRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkElevenLabsTranscriptionResponse: Decodable {
    let text: String
}

public struct VoiceInkPreparedXAITranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkXAITranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkXAITranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkXAIRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        format: Bool = false,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedXAITranscriptionRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        if let language, !language.isEmpty, language != "auto" {
            form.addField(name: "language", value: language)
            if format {
                form.addField(name: "format", value: "true")
            }
        }
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.xaiSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedXAITranscriptionRequest(request: request, body: form.data)
    }

    public static func makeAPIKeyRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.xaiAPIKeyURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkXAITranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        format: Bool = false,
        errorDomain: String = VoiceInkTranscriptionModelProvider.xai.requiredAPIErrorDomain,
        timeout: TimeInterval = 60,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkXAIRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            format: format,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try VoiceInkXAITranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkXAIRequestBuilder.makeAPIKeyRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkXAITranscriptionResponse: Decodable {
    let text: String
}

public struct VoiceInkRemoteTranscriptionService: VoiceInkAudioTranscriptionService, Sendable {
    private let provider: VoiceInkProviderKind?
    private let transport: VoiceInkTranscriptionTransport
    private let apiBaseURL: URL
    private let openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient
    private let deepgramClient: VoiceInkDeepgramTranscriptionClient
    private let geminiClient: VoiceInkGeminiTranscriptionClient
    private let mistralClient: VoiceInkMistralTranscriptionClient
    private let elevenLabsClient: VoiceInkElevenLabsTranscriptionClient
    private let sonioxClient: VoiceInkSonioxTranscriptionClient
    private let speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient
    private let assemblyAIClient: VoiceInkAssemblyAITranscriptionClient
    private let xaiClient: VoiceInkXAITranscriptionClient

    public init(
        provider: VoiceInkProviderKind,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.init(
            provider: provider,
            transport: provider.transcriptionTransport,
            apiBaseURL: provider.transcriptionAPIBaseURL,
            openAICompatibleClient: openAICompatibleClient,
            deepgramClient: deepgramClient,
            geminiClient: geminiClient,
            mistralClient: mistralClient,
            elevenLabsClient: elevenLabsClient,
            sonioxClient: sonioxClient,
            speechmaticsClient: speechmaticsClient,
            assemblyAIClient: assemblyAIClient,
            xaiClient: xaiClient
        )
    }

    public init(
        transport: VoiceInkTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.init(
            provider: nil,
            transport: transport,
            apiBaseURL: apiBaseURL,
            openAICompatibleClient: openAICompatibleClient,
            deepgramClient: deepgramClient,
            geminiClient: geminiClient,
            mistralClient: mistralClient,
            elevenLabsClient: elevenLabsClient,
            sonioxClient: sonioxClient,
            speechmaticsClient: speechmaticsClient,
            assemblyAIClient: assemblyAIClient,
            xaiClient: xaiClient
        )
    }

    init(
        provider: VoiceInkProviderKind?,
        transport: VoiceInkTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.provider = provider
        self.transport = transport
        self.apiBaseURL = apiBaseURL
        self.openAICompatibleClient = openAICompatibleClient
        self.deepgramClient = deepgramClient
        self.geminiClient = geminiClient
        self.mistralClient = mistralClient
        self.elevenLabsClient = elevenLabsClient
        self.sonioxClient = sonioxClient
        self.speechmaticsClient = speechmaticsClient
        self.assemblyAIClient = assemblyAIClient
        self.xaiClient = xaiClient
    }

    public func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        let audioFile = try VoiceInkCloudTranscriptionAudioFile.load(from: fileURL)
        return try await transcribeAudioData(
            apiKey: apiKey,
            model: model,
            audioData: audioFile.data,
            fileName: audioFile.fileName,
            language: language,
            options: fileTranscriptionOptions(
                prompt: prompt,
                customVocabulary: customVocabulary
            )
        )
    }

    func fileTranscriptionOptions(
        prompt: String?,
        customVocabulary: [String] = []
    ) -> VoiceInkRemoteTranscriptionOptions {
        guard let provider else {
            return VoiceInkRemoteTranscriptionOptions(
                prompt: VoiceInkTranscriptionPromptUse.directTranscription.requestPrompt(prompt),
                customVocabulary: customVocabulary
            )
        }

        return VoiceInkRemoteTranscriptionOptions.batchDefaults(
            forProviderKind: provider,
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    func providerAPIErrorDomain(defaultingTo defaultProvider: VoiceInkTranscriptionModelProvider) -> String {
        guard provider?.transcriptionTransport == transport,
              let providerErrorDomain = provider?.transcriptionModelProvider?.apiErrorDomain else {
            return defaultProvider.apiErrorDomain ?? VoiceInkRemoteTranscriptionOptions.defaultOpenAICompatibleErrorDomain
        }
        return providerErrorDomain
    }

    public func transcribeAudioData(
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        options: VoiceInkRemoteTranscriptionOptions = VoiceInkRemoteTranscriptionOptions()
    ) async throws -> String {
        switch transport {
        case .openAICompatible:
            return try await openAICompatibleClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                prompt: options.prompt,
                responseFormat: options.openAICompatibleResponseFormat,
                temperature: options.openAICompatibleTemperature,
                errorDomain: options.openAICompatibleErrorDomain,
                timeout: options.openAICompatibleTimeout,
                maxRetries: options.openAICompatibleMaxRetries,
                allowPlainTextFallback: options.openAICompatibleAllowsPlainTextFallback
            )
        case .deepgram:
            return try await deepgramClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language,
                paragraphs: options.deepgramParagraphs,
                diarize: options.deepgramDiarize,
                timeout: options.deepgramTimeout
            )
        case .geminiGenerateContent:
            return try await geminiClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                timeout: 60
            )
        case .mistral:
            return try await mistralClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                errorDomain: providerAPIErrorDomain(defaultingTo: .mistral),
                timeout: 30,
                maxRetries: 2
            )
        case .elevenLabs:
            return try await elevenLabsClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                timeout: 30,
                maxRetries: 2
            )
        case .soniox:
            return try await sonioxClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                customVocabulary: options.customVocabulary
            )
        case .speechmatics:
            return try await speechmaticsClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileName,
                language: language,
                customVocabulary: options.customVocabulary
            )
        case .assemblyAI:
            return try await assemblyAIClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language,
                prompt: options.prompt,
                customVocabulary: options.customVocabulary,
                errorDomain: providerAPIErrorDomain(defaultingTo: .assemblyAI)
            )
        case .xai:
            return try await xaiClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileName,
                language: language,
                format: true,
                errorDomain: providerAPIErrorDomain(defaultingTo: .xai),
                timeout: 60,
                maxRetries: 2
            )
        case .localWhisper:
            throw URLError(.unsupportedURL)
        }
    }

}
