import Foundation
import RomaNVIDIA

public protocol RomaAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String
}

public struct RomaUnsupportedAudioTranscriptionService: RomaAudioTranscriptionService {
    public init() {}

    public func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        throw RomaCloudTranscriptionError.unsupportedProvider
    }
}

public enum RomaCloudTranscriptionError: Error, LocalizedError {
    public static let apiStatusCodeRange: ClosedRange<Int> = 100...599

    case unsupportedProvider
    case missingAPIKey
    case audioFileNotFound
    case invalidAudioFormat(String)
    case unsupportedOperatingSystem(String)
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .invalidAudioFormat(let message), .unsupportedOperatingSystem(let message):
            return message
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return RomaTranscriptionRunError.noTranscriptionReturned.errorDescription
        }
    }

    public static func apiRequestFailure(
        from error: NSError,
        matchingErrorDomain errorDomain: String?
    ) -> RomaCloudTranscriptionError? {
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
    ) -> RomaCloudTranscriptionError {
        if let cloudError = error as? RomaCloudTranscriptionError {
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

public struct RomaCloudTranscriptionAudioFile: Equatable, Sendable {
    public let data: Data
    public let fileName: String

    public init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
    }

    public static func load(from url: URL) throws -> RomaCloudTranscriptionAudioFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RomaCloudTranscriptionError.audioFileNotFound
        }

        return RomaCloudTranscriptionAudioFile(
            data: try Data(contentsOf: url),
            fileName: url.lastPathComponent
        )
    }
}

public struct RomaAudioTranscriptionServiceFactory {
    public typealias RemoteServiceFactory = (RomaProviderKind) -> any RomaAudioTranscriptionService
    public typealias LocalWhisperServiceFactory = () -> any RomaAudioTranscriptionService
    public typealias LocalFluidAudioServiceFactory = () -> any RomaAudioTranscriptionService
    public typealias NativeAppleServiceFactory = () -> any RomaAudioTranscriptionService
    public typealias CustomCloudServiceFactory = () -> any RomaAudioTranscriptionService

    private let remoteServiceFactory: RemoteServiceFactory
    private let localWhisperServiceFactory: LocalWhisperServiceFactory
    private let localFluidAudioServiceFactory: LocalFluidAudioServiceFactory
    private let nativeAppleServiceFactory: NativeAppleServiceFactory
    private let customCloudServiceFactory: CustomCloudServiceFactory

    public init(
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        remoteServiceFactory: @escaping RemoteServiceFactory = { RomaRemoteTranscriptionService(provider: $0) }
    ) {
        self.localWhisperServiceFactory = localWhisperServiceFactory
        self.localFluidAudioServiceFactory = localFluidAudioServiceFactory
        self.nativeAppleServiceFactory = nativeAppleServiceFactory
        self.customCloudServiceFactory = customCloudServiceFactory
        self.remoteServiceFactory = remoteServiceFactory
    }

    public func service(for provider: RomaProviderKind) -> any RomaAudioTranscriptionService {
        switch provider.transcriptionServiceKind {
        case .remote:
            return remoteServiceFactory(provider)
        case .streamingOnly:
            return RomaUnsupportedAudioTranscriptionService()
        case .customCloud:
            return customCloudServiceFactory()
        case .localWhisper:
            return localWhisperServiceFactory()
        case .localFluidAudio:
            return localFluidAudioServiceFactory()
        case .nativeApple:
            return nativeAppleServiceFactory()
        }
    }
}

public struct RomaRemoteTranscriptionOptions: Equatable, Sendable {
    public static var defaultOpenAICompatibleErrorDomain: String {
        guard let apiErrorDomain = RomaTranscriptionModelProvider.groq.apiErrorDomain else {
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
        openAICompatibleErrorDomain: String = RomaRemoteTranscriptionOptions.defaultOpenAICompatibleErrorDomain,
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
        for provider: RomaTranscriptionModelProvider,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) -> Self {
        let requestPrompt = provider.providerKind.map {
            RomaTranscriptionPromptUse.recordedFileTranscription($0).requestPrompt(prompt)
        } ?? nil
        let normalizedCustomVocabulary = provider.providerKind.map {
            RomaCustomVocabularyTerms.normalized(customVocabulary, for: .batchTranscription($0))
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
        case .cartesia, .elevenLabs, .gemini, .mistral, .xai, .nvidia, .local, .nativeApple:
            return Self()
        }
    }

    public static func batchDefaults(
        forProviderKind provider: RomaProviderKind,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) -> Self {
        let requestPrompt = RomaTranscriptionPromptUse.recordedFileTranscription(provider).requestPrompt(prompt)
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

public enum RomaMacOSCloudTranscriptionPolicy {
    typealias TranscriptionTransport = @Sendable (RomaMacOSCloudTranscriptionRequest) async throws -> String

    public static func transcribeAudioData(
        modelProvider: RomaMacOSTranscriptionModelProvider,
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
            try await RomaRemoteTranscriptionService(provider: request.provider).transcribeAudioData(
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
        modelProvider: RomaMacOSTranscriptionModelProvider,
        apiKey: String?,
        modelName: String,
        audioData: Data,
        fileName: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String],
        transport: TranscriptionTransport
    ) async throws -> String {
        guard let usableAPIKey = RomaProviderCredential.nonBlank(apiKey) else {
            throw RomaCloudTranscriptionError.missingAPIKey
        }

        guard let provider = modelProvider.remoteTranscriptionProviderKind else {
            throw RomaCloudTranscriptionError.unsupportedProvider
        }

        let request = RomaMacOSCloudTranscriptionRequest(
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
                throw RomaCloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch {
            throw RomaCloudTranscriptionError.remoteExecutionFailure(
                from: error,
                matchingErrorDomain: modelProvider.apiErrorDomain
            )
        }
    }
}

struct RomaMacOSCloudTranscriptionRequest: Equatable, Sendable {
    let provider: RomaProviderKind
    let apiKey: String
    let modelName: String
    let audioData: Data
    let fileName: String
    let language: String?
    let options: RomaRemoteTranscriptionOptions
}

public struct RomaOpenAICompatibleTranscriptionResponse: Decodable, Equatable, Sendable {
    public let text: String?
    public let language: String?
    public let duration: Double?

    public init(text: String?, language: String? = nil, duration: Double? = nil) {
        self.text = text
        self.language = language
        self.duration = duration
    }
}

public enum RomaOpenAICompatibleTranscriptionCodec {
    public static func multipartContentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public static func requestBody(
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> Data {
        var form = RomaMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        form.addField(name: "model", value: model)
        if let responseFormat, !responseFormat.isEmpty {
            form.addField(name: "response_format", value: responseFormat)
        }
        if let temperature, !temperature.isEmpty {
            form.addField(name: "temperature", value: temperature)
        }
        if let language, !language.isEmpty {
            form.addField(name: "language", value: language)
        }
        if let prompt, !prompt.isEmpty {
            form.addField(name: "prompt", value: prompt)
        }

        return form.data
    }

    public static func textIfPresent(from data: Data) throws -> String? {
        try JSONDecoder()
            .decode(RomaOpenAICompatibleTranscriptionResponse.self, from: data)
            .text
    }

    static func transcriptionText(from data: Data, allowPlainTextFallback: Bool) -> String {
        if let text = try? textIfPresent(from: data) {
            return text
        }
        guard allowPlainTextFallback else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct RomaOpenAICompatibleTranscriptionClient: Sendable {
    private let modelsClient: RomaOpenAICompatibleClient

    public init(modelsClient: RomaOpenAICompatibleClient = RomaOpenAICompatibleClient()) {
        self.modelsClient = modelsClient
    }

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0,
        allowPlainTextFallback: Bool = true
    ) async throws -> String {
        return try await transcribeAudioData(
            url: RomaProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: baseURL),
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature,
            errorDomain: errorDomain,
            timeout: timeout,
            maxRetries: maxRetries,
            allowPlainTextFallback: allowPlainTextFallback
        )
    }

    public func transcribeAudioData(
        url: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0,
        allowPlainTextFallback: Bool = true
    ) async throws -> String {
        let preparedRequest = RomaOpenAICompatibleTranscriptionRequestBuilder.make(
            url: url,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        let data = try await RomaRetriedRequest.validatedData(
            for: preparedRequest.requestWithHTTPBody(),
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return RomaOpenAICompatibleTranscriptionCodec.transcriptionText(
            from: data,
            allowPlainTextFallback: allowPlainTextFallback
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await modelsClient.verifyAPIKey(baseURL: baseURL, apiKey: apiKey)
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await modelsClient.verifyAPIKeyDetailed(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )
    }
}

public struct RomaPreparedOpenAICompatibleTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }

    public func requestWithHTTPBody() -> URLRequest {
        var copy = request
        copy.httpBody = body
        return copy
    }
}

public enum RomaOpenAICompatibleTranscriptionRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> RomaPreparedOpenAICompatibleTranscriptionRequest {
        make(
            url: RomaProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: baseURL),
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }

    public static func make(
        url: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> RomaPreparedOpenAICompatibleTranscriptionRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            RomaOpenAICompatibleTranscriptionCodec.multipartContentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = RomaOpenAICompatibleTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        return RomaPreparedOpenAICompatibleTranscriptionRequest(request: request, body: body)
    }
}

public enum RomaDeepgramTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(DeepgramTranscriptionResponse.self, from: data)
        return decoded.results.channels.first?.alternatives.first?.transcript ?? ""
    }
}

public enum RomaDeepgramRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        smartFormat: Bool = true,
        punctuate: Bool = true,
        paragraphs: Bool? = nil,
        diarize: Bool? = false,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: smartFormat ? "true" : "false"),
            URLQueryItem(name: "punctuate", value: punctuate ? "true" : "false")
        ]

        if let paragraphs {
            queryItems.append(URLQueryItem(name: "paragraphs", value: paragraphs ? "true" : "false"))
        }

        if let diarize {
            queryItems.append(URLQueryItem(name: "diarize", value: diarize ? "true" : "false"))
        }

        if let language, !language.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }

        for term in customVocabulary where !term.isEmpty {
            queryItems.append(URLQueryItem(name: "keyterm", value: term))
        }

        var components = URLComponents(
            url: RomaProviderEndpoint.deepgramListenURL(from: baseURL),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems

        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeProjectsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.deepgramProjectsURL(from: baseURL))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaDeepgramTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        smartFormat: Bool = true,
        punctuate: Bool = true,
        paragraphs: Bool? = nil,
        diarize: Bool? = false,
        customVocabulary: [String] = [],
        errorDomain: String = RomaTranscriptionModelProvider.deepgram.requiredAPIErrorDomain,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        let request = try RomaDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            language: language,
            smartFormat: smartFormat,
            punctuate: punctuate,
            paragraphs: paragraphs,
            diarize: diarize,
            customVocabulary: customVocabulary,
            timeout: timeout
        )

        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: errorDomain
        )

        return try RomaDeepgramTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaDeepgramRequestBuilder.makeProjectsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct DeepgramTranscriptionResponse: Decodable {
    let results: DeepgramResults
}

private struct DeepgramResults: Decodable {
    let channels: [DeepgramChannel]
}

private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}

private struct DeepgramAlternative: Decodable {
    let transcript: String
}

public enum RomaGeminiTranscriptionCodec {
    public static let defaultPrompt = "Please transcribe this audio file. Provide only the transcribed text."

    public static func requestBody(
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = defaultPrompt
    ) throws -> Data {
        try JSONEncoder().encode(
            RomaGeminiTranscriptionRequest(
                contents: [
                    RomaGeminiContent(parts: [
                        RomaGeminiPart(text: prompt, inlineData: nil),
                        RomaGeminiPart(
                            text: nil,
                            inlineData: RomaGeminiInlineData(
                                mimeType: mimeType,
                                data: audioData.base64EncodedString()
                            )
                        )
                    ])
                ]
            )
        )
    }

    public static func transcript(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(RomaGeminiTranscriptionResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public enum RomaGeminiRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = RomaGeminiTranscriptionCodec.defaultPrompt,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.geminiGenerateContentURL(from: baseURL, model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try RomaGeminiTranscriptionCodec.requestBody(
            audioData: audioData,
            mimeType: mimeType,
            prompt: prompt
        )
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeModelsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.geminiModelsURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaGeminiTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = RomaGeminiTranscriptionCodec.defaultPrompt,
        errorDomain: String = RomaTranscriptionModelProvider.gemini.requiredAPIErrorDomain,
        timeout: TimeInterval? = 60
    ) async throws -> String {
        let request = try RomaGeminiRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            mimeType: mimeType,
            prompt: prompt,
            timeout: timeout
        )

        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: errorDomain
        )

        return try RomaGeminiTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaGeminiRequestBuilder.makeModelsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct RomaGeminiTranscriptionRequest: Encodable {
    let contents: [RomaGeminiContent]
}

private struct RomaGeminiContent: Encodable {
    let parts: [RomaGeminiPart]
}

private struct RomaGeminiPart: Encodable {
    let text: String?
    let inlineData: RomaGeminiInlineData?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let inlineData {
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }
}

private struct RomaGeminiInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct RomaGeminiTranscriptionResponse: Decodable {
    let candidates: [RomaGeminiCandidate]
}

private struct RomaGeminiCandidate: Decodable {
    let content: RomaGeminiResponseContent
}

private struct RomaGeminiResponseContent: Decodable {
    let parts: [RomaGeminiResponsePart]
}

private struct RomaGeminiResponsePart: Decodable {
    let text: String
}

public struct RomaPreparedMistralTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum RomaMistralTranscriptionCodec {
    public static func multipartContentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public static func requestBody(
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String
    ) -> Data {
        var form = RomaMultipartFormData(boundary: boundary)
        form.addField(name: "model", value: model)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        return form.data
    }

    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaMistralTranscriptionResponse.self, from: data).text
    }
}

public enum RomaMistralRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> RomaPreparedMistralTranscriptionRequest {
        let body = RomaMistralTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary
        )

        var request = URLRequest(url: RomaProviderEndpoint.mistralAudioTranscriptionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(
            RomaMistralTranscriptionCodec.multipartContentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return RomaPreparedMistralTranscriptionRequest(request: request, body: body)
    }

    public static func makeModelsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.mistralModelsURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaMistralTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        errorDomain: String = RomaTranscriptionModelProvider.mistral.requiredAPIErrorDomain,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = RomaMistralRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout
        )

        let data = try await RomaRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try RomaMistralTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaMistralRequestBuilder.makeModelsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct RomaMistralTranscriptionResponse: Decodable {
    let text: String
}

public struct RomaPreparedElevenLabsTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum RomaElevenLabsTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaElevenLabsTranscriptionResponse.self, from: data).text
    }
}

public enum RomaElevenLabsRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> RomaPreparedElevenLabsTranscriptionRequest {
        var form = RomaMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        form.addField(name: "model_id", value: model)
        form.addField(name: "temperature", value: "0.0")
        form.addField(name: "tag_audio_events", value: "false")
        if let language, !language.isEmpty {
            form.addField(name: "language_code", value: language)
        }

        var request = URLRequest(url: RomaProviderEndpoint.elevenLabsSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return RomaPreparedElevenLabsTranscriptionRequest(request: request, body: form.data)
    }

    public static func makeUserRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.elevenLabsUserURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaElevenLabsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        errorDomain: String = RomaTranscriptionModelProvider.elevenLabs.requiredAPIErrorDomain,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = RomaElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            timeout: timeout
        )

        let data = try await RomaRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try RomaElevenLabsTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaElevenLabsRequestBuilder.makeUserRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct RomaElevenLabsTranscriptionResponse: Decodable {
    let text: String
}

public struct RomaPreparedXAITranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum RomaXAITranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaXAITranscriptionResponse.self, from: data).text
    }
}

public enum RomaXAIRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        format: Bool = false,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> RomaPreparedXAITranscriptionRequest {
        var form = RomaMultipartFormData(boundary: boundary)
        if let language, !language.isEmpty, language != "auto" {
            form.addField(name: "language", value: language)
            if format {
                form.addField(name: "format", value: "true")
            }
        }
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: RomaProviderEndpoint.xaiSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return RomaPreparedXAITranscriptionRequest(request: request, body: form.data)
    }

    public static func makeAPIKeyRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.xaiAPIKeyURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaXAITranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        format: Bool = false,
        errorDomain: String = RomaTranscriptionModelProvider.xai.requiredAPIErrorDomain,
        timeout: TimeInterval = 60,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = RomaXAIRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            format: format,
            timeout: timeout
        )

        let data = try await RomaRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try RomaXAITranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaXAIRequestBuilder.makeAPIKeyRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct RomaXAITranscriptionResponse: Decodable {
    let text: String
}

public struct RomaSonioxTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        errorDomain: String = RomaTranscriptionModelProvider.soniox.requiredAPIErrorDomain
    ) async throws -> String {
        let fileID = try await uploadFile(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout,
            errorDomain: errorDomain
        )
        let transcriptionID = try await createTranscription(
            baseURL: baseURL,
            apiKey: apiKey,
            fileID: fileID,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout,
            errorDomain: errorDomain
        )
        try await pollTranscriptionStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptionID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptionID,
            timeout: timeout,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaSonioxRequestBuilder.makeFilesRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func uploadFile(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = RomaSonioxRequestBuilder.makeUploadFileRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return try RomaSonioxTranscriptionCodec.uploadedFileID(from: data)
    }

    private func createTranscription(
        baseURL: URL,
        apiKey: String,
        fileID: String,
        model: String,
        language: String?,
        customVocabulary: [String],
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let request = try RomaSonioxRequestBuilder.makeCreateTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            fileID: fileID,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return try RomaSonioxTranscriptionCodec.createdTranscriptionID(from: data)
    }

    private func pollTranscriptionStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        try await RomaRemotePollingPolicy.pollValidatedData(
            request: {
                RomaSonioxRequestBuilder.makeTranscriptionStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            if let status = try? RomaSonioxTranscriptionCodec.status(from: data).lowercased() {
                switch status {
                case "completed":
                    return .finished(())
                case "failed":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Soniox transcription job failed."]
                    )
                default:
                    break
                }
            }

            return .keepPolling
        }
    }

    private func fetchTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let request = RomaSonioxRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return RomaSonioxTranscriptionCodec.transcript(from: data)
    }
}

public struct RomaPreparedSonioxUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum RomaSonioxTranscriptionCodec {
    public static func uploadedFileID(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaSonioxIDResponse.self, from: data).id
    }

    public static func createdTranscriptionID(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaSonioxIDResponse.self, from: data).id
    }

    public static func status(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaSonioxStatusResponse.self, from: data).status
    }

    public static func transcript(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(RomaSonioxTranscriptResponse.self, from: data) {
            return decoded.text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum RomaSonioxRequestBuilder {
    public static func makeUploadFileRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> RomaPreparedSonioxUploadRequest {
        var form = RomaMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: RomaProviderEndpoint.sonioxFilesURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return RomaPreparedSonioxUploadRequest(request: request, body: form.data)
    }

    public static func makeCreateTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        fileID: String,
        model: String,
        language: String? = nil,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var payload: [String: Any] = [
            "file_id": fileID,
            "model": model,
            "enable_speaker_diarization": false
        ]

        if !customVocabulary.isEmpty {
            payload["context"] = ["terms": customVocabulary]
        }

        if let language, !language.isEmpty {
            payload["language_hints"] = [language]
            payload["language_hints_strict"] = true
            payload["enable_language_identification"] = true
        } else {
            payload["enable_language_identification"] = true
        }

        var request = URLRequest(url: RomaProviderEndpoint.sonioxTranscriptionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptionStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.sonioxTranscriptionURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.sonioxTranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeFilesRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.sonioxFilesURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private struct RomaSonioxIDResponse: Decodable {
    let id: String
}

private struct RomaSonioxStatusResponse: Decodable {
    let status: String
}

private struct RomaSonioxTranscriptResponse: Decodable {
    let text: String
}

public struct RomaSpeechmaticsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = RomaTranscriptionModelProvider.speechmatics.requiredAPIErrorDomain
    ) async throws -> String {
        let jobID = try await submitJob(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try await pollJobStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaSpeechmaticsRequestBuilder.makeJobsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func submitJob(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String?,
        operatingPoint: String,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = try RomaSpeechmaticsRequestBuilder.makeSubmitJobRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try RomaSpeechmaticsTranscriptionCodec.submittedJobID(from: data)
    }

    private func pollJobStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        try await RomaRemotePollingPolicy.pollValidatedData(
            request: {
                RomaSpeechmaticsRequestBuilder.makeJobStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            if let status = try? RomaSpeechmaticsTranscriptionCodec.jobStatus(from: data).lowercased() {
                switch status {
                case "done":
                    return .finished(())
                case "rejected":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was rejected."]
                    )
                case "deleted":
                    throw NSError(
                        domain: errorDomain,
                        code: 410,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was deleted."]
                    )
                default:
                    break
                }
            }

            return .keepPolling
        }
    }

    private func fetchTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = RomaSpeechmaticsRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return RomaSpeechmaticsTranscriptionCodec.transcript(from: data)
    }
}

public struct RomaPreparedSpeechmaticsUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum RomaSpeechmaticsTranscriptionCodec {
    public static func submittedJobID(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaSpeechmaticsSubmitJobResponse.self, from: data).id
    }

    public static func jobStatus(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaSpeechmaticsJobStatusResponse.self, from: data).job.status
    }

    public static func transcript(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    public static func speechmaticsLanguage(from language: String?) -> String {
        guard let language, !language.isEmpty, language != "auto" else { return "auto" }
        switch language {
        case "zh":
            return "cmn"
        default:
            return language
        }
    }
}

public enum RomaSpeechmaticsRequestBuilder {
    public static func makeSubmitJobRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) throws -> RomaPreparedSpeechmaticsUploadRequest {
        let config = RomaSpeechmaticsSubmitJobConfig.make(
            language: RomaSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: language),
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary
        )
        let configData = try JSONSerialization.data(withJSONObject: config)
        guard let configString = String(data: configData, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        var form = RomaMultipartFormData(boundary: boundary)
        form.addField(name: "config", value: configString)
        form.addFile(name: "data_file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: RomaProviderEndpoint.speechmaticsJobsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return RomaPreparedSpeechmaticsUploadRequest(request: request, body: form.data)
    }

    public static func makeJobStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.speechmaticsJobURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.speechmaticsTranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeJobsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.speechmaticsJobsURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private enum RomaSpeechmaticsSubmitJobConfig {
    static func make(
        language: String,
        operatingPoint: String,
        customVocabulary: [String]
    ) -> [String: Any] {
        var transcriptionConfig: [String: Any] = [
            "language": language,
            "operating_point": operatingPoint
        ]
        if !customVocabulary.isEmpty {
            transcriptionConfig["additional_vocab"] = customVocabulary.map { ["content": $0] }
        }
        return [
            "type": "transcription",
            "transcription_config": transcriptionConfig
        ]
    }
}

private struct RomaSpeechmaticsSubmitJobResponse: Decodable {
    let id: String
}

private struct RomaSpeechmaticsJobStatusResponse: Decodable {
    let job: Job

    struct Job: Decodable {
        let status: String
    }
}

public struct RomaAssemblyAITranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = RomaTranscriptionModelProvider.assemblyAI.requiredAPIErrorDomain
    ) async throws -> String {
        let uploadURL = try await uploadAudio(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        let transcriptID = try await createTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            audioURL: uploadURL,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try await pollTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        await RomaAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: RomaAssemblyAIRequestBuilder.makeTranscriptsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func uploadAudio(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = RomaAssemblyAIRequestBuilder.makeUploadAudioRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try RomaAssemblyAITranscriptionCodec.uploadedAudioURL(from: data)
    }

    private func createTranscript(
        baseURL: URL,
        apiKey: String,
        audioURL: String,
        model: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = try RomaAssemblyAIRequestBuilder.makeCreateTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioURL: audioURL,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try RomaAssemblyAITranscriptionCodec.createdTranscriptID(from: data)
    }

    private func pollTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        try await RomaRemotePollingPolicy.pollValidatedData(
            request: {
                RomaAssemblyAIRequestBuilder.makeTranscriptStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            let transcript = try RomaAssemblyAITranscriptionCodec.transcriptStatus(from: data)
            switch transcript.status.lowercased() {
            case "completed":
                return .finished(transcript.text ?? "")
            case "error":
                throw NSError(
                    domain: errorDomain,
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: transcript.error ?? "AssemblyAI transcription failed."]
                )
            default:
                return .keepPolling
            }
        }
    }
}

public struct RomaPreparedAssemblyAIUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public struct RomaAssemblyAITranscriptStatus: Equatable, Sendable {
    public let status: String
    public let text: String?
    public let error: String?

    public init(status: String, text: String?, error: String?) {
        self.status = status
        self.text = text
        self.error = error
    }
}

public enum RomaAssemblyAITranscriptionCodec {
    public static func uploadedAudioURL(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaAssemblyAIUploadResponse.self, from: data).uploadURL
    }

    public static func createdTranscriptID(from data: Data) throws -> String {
        try JSONDecoder().decode(RomaAssemblyAITranscriptCreateResponse.self, from: data).id
    }

    public static func transcriptStatus(from data: Data) throws -> RomaAssemblyAITranscriptStatus {
        let decoded = try JSONDecoder().decode(RomaAssemblyAITranscriptStatusResponse.self, from: data)
        return RomaAssemblyAITranscriptStatus(
            status: decoded.status,
            text: decoded.text,
            error: decoded.error
        )
    }
}

public enum RomaAssemblyAIRequestBuilder {
    public static func makeUploadAudioRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        timeout: TimeInterval? = nil
    ) -> RomaPreparedAssemblyAIUploadRequest {
        var request = URLRequest(url: RomaProviderEndpoint.assemblyAIUploadURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return RomaPreparedAssemblyAIUploadRequest(request: request, body: audioData)
    }

    public static func makeCreateTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        audioURL: String,
        model: String,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        let speechModels = speechModels(for: model)
        let primarySpeechModel = speechModels.first ?? model
        var payload: [String: Any] = [
            "audio_url": audioURL,
            "speech_models": speechModels,
            "punctuate": true,
            "format_text": true
        ]

        if let language, !language.isEmpty, language != "auto" {
            payload["language_code"] = language
        } else {
            payload["language_detection"] = true
        }

        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyterms = normalizedKeyterms(customVocabulary, model: primarySpeechModel)
        if supportsPrompt(speechModels), !trimmedPrompt.isEmpty {
            payload["prompt"] = appendedKeyterms(keyterms, to: trimmedPrompt)
        } else if !keyterms.isEmpty {
            payload["keyterms_prompt"] = keyterms
        }

        var request = URLRequest(url: RomaProviderEndpoint.assemblyAITranscriptsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.assemblyAITranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.assemblyAITranscriptsURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    static func speechModels(for model: String) -> [String] {
        switch model {
        case "universal-3-pro":
            return ["universal-3-pro", "universal-2"]
        case "universal-2":
            return ["universal-2"]
        case "universal-streaming", "universal-streaming-english", "universal-streaming-multilingual", "whisper-rt":
            return ["universal-2"]
        default:
            return [model]
        }
    }

    static func supportsPrompt(_ speechModels: [String]) -> Bool {
        speechModels.contains("universal-3-pro")
    }

    static func normalizedKeyterms(_ terms: [String], model: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let limit = model == "universal-2" ? 200 : 1_000
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split(separator: " ").count
            guard !trimmed.isEmpty, trimmed.count <= 50, wordCount <= 6 else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }

    static func appendedKeyterms(_ keyterms: [String], to prompt: String) -> String {
        guard !keyterms.isEmpty else { return prompt }
        return "\(prompt)\n\nBoost these terms when they appear in the audio: \(keyterms.joined(separator: ", "))."
    }
}

private struct RomaAssemblyAIUploadResponse: Decodable {
    let uploadURL: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
    }
}

private struct RomaAssemblyAITranscriptCreateResponse: Decodable {
    let id: String
}

private struct RomaAssemblyAITranscriptStatusResponse: Decodable {
    let status: String
    let text: String?
    let error: String?
}

public struct RomaRemoteTranscriptionService: RomaAudioTranscriptionService, Sendable {
    private let provider: RomaProviderKind?
    private let transport: RomaTranscriptionTransport
    private let apiBaseURL: URL
    private let openAICompatibleClient: RomaOpenAICompatibleTranscriptionClient
    private let deepgramClient: RomaDeepgramTranscriptionClient
    private let geminiClient: RomaGeminiTranscriptionClient
    private let mistralClient: RomaMistralTranscriptionClient
    private let elevenLabsClient: RomaElevenLabsTranscriptionClient
    private let sonioxClient: RomaSonioxTranscriptionClient
    private let speechmaticsClient: RomaSpeechmaticsTranscriptionClient
    private let assemblyAIClient: RomaAssemblyAITranscriptionClient
    private let xaiClient: RomaXAITranscriptionClient

    public init(
        provider: RomaProviderKind,
        openAICompatibleClient: RomaOpenAICompatibleTranscriptionClient = RomaOpenAICompatibleTranscriptionClient(),
        deepgramClient: RomaDeepgramTranscriptionClient = RomaDeepgramTranscriptionClient(),
        geminiClient: RomaGeminiTranscriptionClient = RomaGeminiTranscriptionClient(),
        mistralClient: RomaMistralTranscriptionClient = RomaMistralTranscriptionClient(),
        elevenLabsClient: RomaElevenLabsTranscriptionClient = RomaElevenLabsTranscriptionClient(),
        sonioxClient: RomaSonioxTranscriptionClient = RomaSonioxTranscriptionClient(),
        speechmaticsClient: RomaSpeechmaticsTranscriptionClient = RomaSpeechmaticsTranscriptionClient(),
        assemblyAIClient: RomaAssemblyAITranscriptionClient = RomaAssemblyAITranscriptionClient(),
        xaiClient: RomaXAITranscriptionClient = RomaXAITranscriptionClient()
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
        transport: RomaTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: RomaOpenAICompatibleTranscriptionClient = RomaOpenAICompatibleTranscriptionClient(),
        deepgramClient: RomaDeepgramTranscriptionClient = RomaDeepgramTranscriptionClient(),
        geminiClient: RomaGeminiTranscriptionClient = RomaGeminiTranscriptionClient(),
        mistralClient: RomaMistralTranscriptionClient = RomaMistralTranscriptionClient(),
        elevenLabsClient: RomaElevenLabsTranscriptionClient = RomaElevenLabsTranscriptionClient(),
        sonioxClient: RomaSonioxTranscriptionClient = RomaSonioxTranscriptionClient(),
        speechmaticsClient: RomaSpeechmaticsTranscriptionClient = RomaSpeechmaticsTranscriptionClient(),
        assemblyAIClient: RomaAssemblyAITranscriptionClient = RomaAssemblyAITranscriptionClient(),
        xaiClient: RomaXAITranscriptionClient = RomaXAITranscriptionClient()
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
        provider: RomaProviderKind?,
        transport: RomaTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: RomaOpenAICompatibleTranscriptionClient = RomaOpenAICompatibleTranscriptionClient(),
        deepgramClient: RomaDeepgramTranscriptionClient = RomaDeepgramTranscriptionClient(),
        geminiClient: RomaGeminiTranscriptionClient = RomaGeminiTranscriptionClient(),
        mistralClient: RomaMistralTranscriptionClient = RomaMistralTranscriptionClient(),
        elevenLabsClient: RomaElevenLabsTranscriptionClient = RomaElevenLabsTranscriptionClient(),
        sonioxClient: RomaSonioxTranscriptionClient = RomaSonioxTranscriptionClient(),
        speechmaticsClient: RomaSpeechmaticsTranscriptionClient = RomaSpeechmaticsTranscriptionClient(),
        assemblyAIClient: RomaAssemblyAITranscriptionClient = RomaAssemblyAITranscriptionClient(),
        xaiClient: RomaXAITranscriptionClient = RomaXAITranscriptionClient()
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
        let audioFile = try RomaCloudTranscriptionAudioFile.load(from: fileURL)
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
    ) -> RomaRemoteTranscriptionOptions {
        guard let provider else {
            return RomaRemoteTranscriptionOptions(
                prompt: RomaTranscriptionPromptUse.directTranscription.requestPrompt(prompt),
                customVocabulary: customVocabulary
            )
        }

        return RomaRemoteTranscriptionOptions.batchDefaults(
            forProviderKind: provider,
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    func providerAPIErrorDomain(defaultingTo defaultProvider: RomaTranscriptionModelProvider) -> String {
        guard provider?.transcriptionTransport == transport,
              let providerErrorDomain = provider?.transcriptionModelProvider?.apiErrorDomain else {
            return defaultProvider.apiErrorDomain ?? RomaRemoteTranscriptionOptions.defaultOpenAICompatibleErrorDomain
        }
        return providerErrorDomain
    }

    public func transcribeAudioData(
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        options: RomaRemoteTranscriptionOptions = RomaRemoteTranscriptionOptions()
    ) async throws -> String {
        switch transport {
        case .nvidiaRiva:
            guard #available(macOS 15, iOS 18, *) else {
                throw RomaCloudTranscriptionError.unsupportedOperatingSystem(NVIDIAParakeet.minimumOSMessage)
            }
            guard model == NVIDIAParakeet.modelName else {
                throw RomaCloudTranscriptionError.unsupportedProvider
            }
            guard let pcmData = RomaPCM16Audio.littleEndianPCM16Data(fromWAVData: audioData), !pcmData.isEmpty else {
                throw RomaCloudTranscriptionError.invalidAudioFormat("NVIDIA requires nonempty 16 kHz mono PCM16 WAV audio.")
            }
            do {
                return try await NVIDIAParakeetClient.transcribe(pcm16Data: pcmData, apiKey: apiKey)
            } catch NVIDIAParakeetError.emptyTranscript {
                throw RomaCloudTranscriptionError.noTranscriptionReturned
            }
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
        case .localWhisper, .localFluidAudio:
            throw URLError(.unsupportedURL)
        case .nativeApple:
            throw RomaCloudTranscriptionError.unsupportedProvider
        }
    }

}
