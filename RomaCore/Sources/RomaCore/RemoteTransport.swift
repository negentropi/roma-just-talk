import Foundation
import RomaNVIDIA

struct RomaMultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    var data: Data {
        var result = body
        append("--\(boundary)--\r\n", to: &result)
        return result
    }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
        append(value, to: &body)
        append("\r\n", to: &body)
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, fileData: Data) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n", to: &body)
        append("Content-Type: \(mimeType)\r\n\r\n", to: &body)
        body.append(fileData)
        append("\r\n", to: &body)
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }
}

enum RomaRemoteHTTPResponsePolicy {
    static let successStatusCodeRange = 200..<300
    static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    static func validateSuccess(
        response: URLResponse,
        data: Data,
        errorDomain: String
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard successStatusCodeRange.contains(http.statusCode) else {
            throw apiError(statusCode: http.statusCode, data: data, errorDomain: errorDomain)
        }
    }

    static func retryableStatusCode(in response: URLResponse) -> Int? {
        guard let http = response as? HTTPURLResponse else {
            return nil
        }
        return retryableStatusCodes.contains(http.statusCode) ? http.statusCode : nil
    }

    static func apiError(statusCode: Int, data: Data, errorDomain: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: responseBodyText(from: data)]
        )
    }

    static func responseBodyText(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

public struct RomaAPIKeyVerificationResult: Equatable, Sendable {
    public let isValid: Bool
    public let errorMessage: String?

    public init(isValid: Bool, errorMessage: String?) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }

    public init(legacyResult: (Bool, String?)) {
        self.init(isValid: legacyResult.0, errorMessage: legacyResult.1)
    }
}

enum RomaAPIKeyVerificationPolicy {
    static let missingAPIKeyMessage = "API key is missing or empty."
    static let missingHTTPResponseMessage = "No HTTP response received."

    static func verify(
        apiKey: String,
        request: @autoclosure () -> URLRequest
    ) async -> RomaAPIKeyVerificationResult {
        if let blankResult = blankAPIKeyResultIfNeeded(apiKey) {
            return blankResult
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request())
            return verificationResult(data: data, response: response)
        } catch {
            return failureResult(error)
        }
    }

    static func blankAPIKeyResultIfNeeded(_ apiKey: String) -> RomaAPIKeyVerificationResult? {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? missingAPIKeyResult : nil
    }

    static var missingAPIKeyResult: RomaAPIKeyVerificationResult {
        RomaAPIKeyVerificationResult(isValid: false, errorMessage: missingAPIKeyMessage)
    }

    static func verificationResult(data: Data, response: URLResponse) -> RomaAPIKeyVerificationResult {
        guard let http = response as? HTTPURLResponse else {
            return RomaAPIKeyVerificationResult(isValid: false, errorMessage: missingHTTPResponseMessage)
        }

        guard !RomaRemoteHTTPResponsePolicy.successStatusCodeRange.contains(http.statusCode) else {
            return RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        }

        return RomaAPIKeyVerificationResult(
            isValid: false,
            errorMessage: errorMessage(data: data, statusCode: http.statusCode)
        )
    }

    static func failureResult(_ error: Error) -> RomaAPIKeyVerificationResult {
        RomaAPIKeyVerificationResult(isValid: false, errorMessage: error.localizedDescription)
    }

    static func errorMessage(data: Data, statusCode: Int) -> String {
        String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }
}

public enum RomaCartesiaRequestBuilder {
    public static let apiVersion = "2026-03-01"

    public static func makeVoicesRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.cartesiaVoicesURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Cartesia-Version")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaCartesiaClient: Sendable {
    public init() {}

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
            request: RomaCartesiaRequestBuilder.makeVoicesRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

public struct RomaAnthropicMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct RomaAnthropicMessagesRequest: Codable, Equatable, Sendable {
    public let model: String
    public let maxTokens: Int
    public let system: String?
    public let messages: [RomaAnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    public init(
        model: String,
        maxTokens: Int,
        system: String?,
        messages: [RomaAnthropicMessage]
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
    }
}

public struct RomaAnthropicContentBlock: Codable, Equatable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String?) {
        self.type = type
        self.text = text
    }
}

public struct RomaAnthropicMessagesResponse: Codable, Equatable, Sendable {
    public let content: [RomaAnthropicContentBlock]

    public init(content: [RomaAnthropicContentBlock]) {
        self.content = content
    }
}

public enum RomaAnthropicMessagesCodec {
    public static func requestBody(
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        maxTokens: Int
    ) throws -> Data {
        let system = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")
        let request = RomaAnthropicMessagesRequest(
            model: model,
            maxTokens: maxTokens,
            system: system.isEmpty ? nil : system,
            messages: messages
                .filter { $0.role != "system" }
                .map { RomaAnthropicMessage(role: $0.role, content: $0.content) }
        )
        return try JSONEncoder().encode(request)
    }

    public static func firstText(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(RomaAnthropicMessagesResponse.self, from: data)
        return response.content.first { $0.type == "text" }?.text ?? ""
    }
}

public enum RomaAnthropicRequestBuilder {
    public static let apiVersion = "2023-06-01"

    public static func makeMessagesRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        maxTokens: Int = 4096,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try RomaAnthropicMessagesCodec.requestBody(
            model: model,
            messages: messages,
            maxTokens: maxTokens
        )
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct RomaAnthropicClient: Sendable {
    public init() {}

    public func chatCompletion(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        maxTokens: Int = 4096
    ) async throws -> String {
        let request = try RomaAnthropicRequestBuilder.makeMessagesRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            maxTokens: maxTokens
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: "AnthropicPostProcessing"
        )
        return try RomaAnthropicMessagesCodec.firstText(from: data)
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> RomaAPIKeyVerificationResult {
        guard let request = try? RomaAnthropicRequestBuilder.makeMessagesRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: RomaAIModelCatalog.defaultModel(for: .anthropic),
            messages: [RomaOpenAICompatibleChatMessage(role: "user", content: "Hello")],
            maxTokens: 1,
            timeout: timeout
        ) else {
            return RomaAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Could not build Anthropic verification request."
            )
        }
        return await RomaAPIKeyVerificationPolicy.verify(apiKey: apiKey, request: request)
    }
}

public struct RomaProviderAPIKeyVerifier: Sendable {
    private let openAICompatibleClient: RomaOpenAICompatibleClient
    private let deepgramClient: RomaDeepgramTranscriptionClient
    private let geminiClient: RomaGeminiTranscriptionClient
    private let mistralClient: RomaMistralTranscriptionClient
    private let elevenLabsClient: RomaElevenLabsTranscriptionClient
    private let sonioxClient: RomaSonioxTranscriptionClient
    private let speechmaticsClient: RomaSpeechmaticsTranscriptionClient
    private let assemblyAIClient: RomaAssemblyAITranscriptionClient
    private let xaiClient: RomaXAITranscriptionClient
    private let cartesiaClient: RomaCartesiaClient
    private let anthropicClient: RomaAnthropicClient

    public init(
        openAICompatibleClient: RomaOpenAICompatibleClient = RomaOpenAICompatibleClient(),
        deepgramClient: RomaDeepgramTranscriptionClient = RomaDeepgramTranscriptionClient(),
        geminiClient: RomaGeminiTranscriptionClient = RomaGeminiTranscriptionClient(),
        mistralClient: RomaMistralTranscriptionClient = RomaMistralTranscriptionClient(),
        elevenLabsClient: RomaElevenLabsTranscriptionClient = RomaElevenLabsTranscriptionClient(),
        sonioxClient: RomaSonioxTranscriptionClient = RomaSonioxTranscriptionClient(),
        speechmaticsClient: RomaSpeechmaticsTranscriptionClient = RomaSpeechmaticsTranscriptionClient(),
        assemblyAIClient: RomaAssemblyAITranscriptionClient = RomaAssemblyAITranscriptionClient(),
        xaiClient: RomaXAITranscriptionClient = RomaXAITranscriptionClient(),
        cartesiaClient: RomaCartesiaClient = RomaCartesiaClient(),
        anthropicClient: RomaAnthropicClient = RomaAnthropicClient()
    ) {
        self.openAICompatibleClient = openAICompatibleClient
        self.deepgramClient = deepgramClient
        self.geminiClient = geminiClient
        self.mistralClient = mistralClient
        self.elevenLabsClient = elevenLabsClient
        self.sonioxClient = sonioxClient
        self.speechmaticsClient = speechmaticsClient
        self.assemblyAIClient = assemblyAIClient
        self.xaiClient = xaiClient
        self.cartesiaClient = cartesiaClient
        self.anthropicClient = anthropicClient
    }

    public func verifyAPIKey(_ apiKey: String, for provider: RomaProviderKind) async -> Bool {
        await verifyAPIKeyDetailed(apiKey, for: provider).isValid
    }

    public func verifyStoredAPIKey(
        _ storedKey: String?,
        for provider: RomaProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Bool {
        await verifyStoredAPIKeyDetailed(
            storedKey,
            for: provider,
            environment: environment
        ).isValid
    }

    public func verifyStoredAPIKeyDetailed(
        _ storedKey: String?,
        for provider: RomaProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> RomaAPIKeyVerificationResult {
        guard provider.canVerifyAPIKey else {
            return await verifyAPIKeyDetailed("", for: provider)
        }

        guard let apiKey = RomaProviderAPIKeyLookup.usableAPIKey(
            storedKey: storedKey,
            provider: provider,
            environment: environment
        ) else {
            return RomaAPIKeyVerificationPolicy.missingAPIKeyResult
        }

        return await verifyAPIKeyDetailed(apiKey, for: provider)
    }

    public func verifyAPIKeyDetailed(
        _ apiKey: String,
        for provider: RomaProviderKind
    ) async -> RomaAPIKeyVerificationResult {
        guard RomaProviderCredential.nonBlank(apiKey) != nil else {
            return RomaAPIKeyVerificationPolicy.missingAPIKeyResult
        }
        guard let transport = provider.apiKeyVerificationTransport else {
            return RomaAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "\(provider.displayName) does not support API key verification."
            )
        }

        switch transport {
        case .nvidiaRivaConfig:
            guard #available(macOS 15, iOS 18, *) else {
                return RomaAPIKeyVerificationResult(isValid: false, errorMessage: NVIDIAParakeet.minimumOSMessage)
            }
            do {
                try await NVIDIAParakeetClient.verifyAPIKey(apiKey)
                return RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            } catch {
                return RomaAPIKeyVerificationResult(isValid: false, errorMessage: error.localizedDescription)
            }
        case .openAICompatibleModels:
            return await openAICompatibleClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .customAIChat:
            guard let requestURL = provider.postProcessingChatCompletionsURL,
                  let model = provider.postProcessingDefaultModel,
                  let request = try? RomaOpenAICompatibleChatRequestBuilder.make(
                    requestURL: requestURL,
                    apiKey: apiKey,
                    model: model,
                    messages: [RomaOpenAICompatibleChatMessage(role: "user", content: "Hello")],
                    temperature: 0.2
                  ) else {
                return RomaAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "Custom provider endpoint and model are required."
                )
            }
            return await RomaAPIKeyVerificationPolicy.verify(apiKey: apiKey, request: request)
        case .deepgramProjects:
            return await deepgramClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .geminiModels:
            return await geminiClient.verifyAPIKeyDetailed(
                baseURL: provider.transcriptionAPIBaseURL,
                apiKey: apiKey
            )
        case .mistralModels:
            return await mistralClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .elevenLabsUser:
            return await elevenLabsClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .sonioxFiles:
            return await sonioxClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .speechmaticsJobs:
            return await speechmaticsClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .assemblyAITranscripts:
            return await assemblyAIClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .xaiAPIKey:
            return await xaiClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .cartesiaVoices:
            return await cartesiaClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        case .anthropicMessages:
            return await anthropicClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
        }
    }

    public func verifyAPIKeyDetailed(
        _ apiKey: String,
        for transcriptionProvider: RomaTranscriptionModelProvider
    ) async -> RomaAPIKeyVerificationResult {
        guard RomaProviderCredential.nonBlank(apiKey) != nil else {
            return RomaAPIKeyVerificationPolicy.missingAPIKeyResult
        }

        if transcriptionProvider == .cartesia {
            return await cartesiaClient.verifyAPIKeyDetailed(
                baseURL: RomaProviderEndpoint.cartesiaAPIBaseURL,
                apiKey: apiKey
            )
        }

        guard let provider = transcriptionProvider.providerKind else {
            return RomaAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "\(transcriptionProvider.rawValue) does not support API key verification."
            )
        }

        return await verifyAPIKeyDetailed(apiKey, for: provider)
    }

    public func verifyStoredAPIKeyDetailed(
        _ storedKey: String?,
        for transcriptionProvider: RomaTranscriptionModelProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> RomaAPIKeyVerificationResult {
        guard transcriptionProvider != .local else {
            return await verifyAPIKeyDetailed("", for: transcriptionProvider)
        }

        let providerName = transcriptionProvider.providerKind?.displayName ?? transcriptionProvider.rawValue
        guard let apiKey = RomaProviderAPIKeyLookup.usableAPIKey(
            storedKey: storedKey,
            providerName: providerName,
            environment: environment
        ) else {
            return RomaAPIKeyVerificationPolicy.missingAPIKeyResult
        }

        return await verifyAPIKeyDetailed(apiKey, for: transcriptionProvider)
    }

    public func verifyAPIKeyDetailed(
        _ apiKey: String,
        for macOSProvider: RomaMacOSTranscriptionModelProvider
    ) async -> RomaAPIKeyVerificationResult {
        guard let transcriptionProvider = macOSProvider.coreTranscriptionModelProvider else {
            return RomaAPIKeyVerificationResult(
                isValid: false,
                errorMessage: RomaProviderAPIKeyVerificationProgress.unsupportedProviderFailureMessage
            )
        }

        return await verifyAPIKeyDetailed(apiKey, for: transcriptionProvider)
    }

    public func verifyStoredAPIKeyDetailed(
        _ storedKey: String?,
        for macOSProvider: RomaMacOSTranscriptionModelProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> RomaAPIKeyVerificationResult {
        guard let transcriptionProvider = macOSProvider.coreTranscriptionModelProvider else {
            return RomaAPIKeyVerificationResult(
                isValid: false,
                errorMessage: RomaProviderAPIKeyVerificationProgress.unsupportedProviderFailureMessage
            )
        }

        return await verifyStoredAPIKeyDetailed(
            storedKey,
            for: transcriptionProvider,
            environment: environment
        )
    }
}

enum RomaRetriedRequest {
    static func data(
        for request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> (Data, URLResponse) {
        try await perform(
            request: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        ) { session, request in
            try await session.data(for: request)
        }
    }

    static func upload(
        request: URLRequest,
        body: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> (Data, URLResponse) {
        try await perform(
            request: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        ) { session, request in
            try await session.upload(for: request, from: body)
        }
    }

    static func validatedData(
        for request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> Data {
        let (data, response) = try await data(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try RomaRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )
        return data
    }

    static func validatedUpload(
        request: URLRequest,
        body: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> Data {
        let (data, response) = try await upload(
            request: request,
            body: body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try RomaRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )
        return data
    }

    private static func perform(
        request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int,
        errorDomain: String,
        operation: (URLSession, URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        let attempts = max(maxRetries, 0)
        var request = request
        if let timeout {
            request.timeoutInterval = timeout
        }
        var lastError: (any Error)?

        for attempt in 0...attempts {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }

            let session: URLSession
            if let timeout {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = timeout
                configuration.timeoutIntervalForResource = timeout
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.urlCache = nil
                session = URLSession(configuration: configuration)
            } else {
                session = .shared
            }
            defer {
                if timeout != nil {
                    session.finishTasksAndInvalidate()
                }
            }

            do {
                let (data, response) = try await operation(session, request)
                if let statusCode = RomaRemoteHTTPResponsePolicy.retryableStatusCode(in: response),
                   attempt < attempts {
                    lastError = RomaRemoteHTTPResponsePolicy.apiError(
                        statusCode: statusCode,
                        data: data,
                        errorDomain: errorDomain
                    )
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt < attempts {
                    continue
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}

public enum RomaOpenAICompatibleModelsRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: RomaProviderEndpoint.openAICompatibleModelsURL(from: baseURL))
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

public struct RomaOpenAICompatibleModelRecord: Codable, Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct RomaOpenAICompatibleModelsResponse: Codable, Equatable, Sendable {
    public let data: [RomaOpenAICompatibleModelRecord]

    public init(data: [RomaOpenAICompatibleModelRecord]) {
        self.data = data
    }
}

public enum RomaOpenAICompatibleModelsCodec {
    public static func modelIDs(from data: Data) throws -> [String] {
        let modelIDs = try JSONDecoder().decode(RomaOpenAICompatibleModelsResponse.self, from: data)
            .data
            .map(\.id)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var seenModelIDs = Set<String>()
        return modelIDs.filter { seenModelIDs.insert($0).inserted }
    }
}

public struct RomaOpenAICompatibleClient: Sendable {
    public init() {}

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
            request: RomaOpenAICompatibleModelsRequestBuilder.make(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    public func fetchModelIDs(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 15
    ) async throws -> [String] {
        let request = RomaOpenAICompatibleModelsRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 0,
            errorDomain: "OpenAICompatibleModels"
        )
        return try RomaOpenAICompatibleModelsCodec.modelIDs(from: data)
    }

    public func chatCompletion(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        temperature: Double? = 0.2,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) async throws -> String {
        let request = try RomaOpenAICompatibleChatRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: "LLMPostProcessing"
        )

        return try RomaOpenAICompatibleChatCodec.firstMessageContent(from: data)
    }

    public func chatCompletion(
        requestURL: URL,
        apiKey: String,
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        temperature: Double? = 0.2,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) async throws -> String {
        let request = try RomaOpenAICompatibleChatRequestBuilder.make(
            requestURL: requestURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        let data = try await RomaRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: "LLMPostProcessing"
        )
        return try RomaOpenAICompatibleChatCodec.firstMessageContent(from: data)
    }
}

public struct RomaOpenAICompatibleChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct RomaOpenAICompatibleChatRequest: Codable, Equatable, Sendable {
    public let model: String
    public let messages: [RomaOpenAICompatibleChatMessage]
    public let temperature: Double?

    public init(
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        temperature: Double?
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

public struct RomaOpenAICompatibleChatChoice: Codable, Equatable, Sendable {
    public let message: RomaOpenAICompatibleChatMessage

    public init(message: RomaOpenAICompatibleChatMessage) {
        self.message = message
    }
}

public struct RomaOpenAICompatibleChatResponse: Codable, Equatable, Sendable {
    public let choices: [RomaOpenAICompatibleChatChoice]

    public init(choices: [RomaOpenAICompatibleChatChoice]) {
        self.choices = choices
    }
}

public enum RomaOpenAICompatibleChatCodec {
    public static func requestBody(
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        temperature: Double?,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) throws -> Data {
        if reasoningEffort != nil || extraBodyParameters?.isEmpty == false {
            var body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role, "content": $0.content] }
            ]
            if let temperature {
                body["temperature"] = temperature
            }
            if let reasoningEffort {
                body["reasoning_effort"] = reasoningEffort
            }
            extraBodyParameters?.forEach { key, value in
                body[key] = value
            }
            return try JSONSerialization.data(withJSONObject: body)
        }

        let request = RomaOpenAICompatibleChatRequest(
            model: model,
            messages: messages,
            temperature: temperature
        )
        return try JSONEncoder().encode(request)
    }

    public static func firstMessageContent(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(RomaOpenAICompatibleChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
}

public enum RomaOpenAICompatibleChatRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        temperature: Double?,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) throws -> URLRequest {
        try make(
            requestURL: RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: baseURL),
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
    }

    public static func make(
        requestURL: URL,
        apiKey: String,
        model: String,
        messages: [RomaOpenAICompatibleChatMessage],
        temperature: Double?,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try RomaOpenAICompatibleChatCodec.requestBody(
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        return request
    }
}

enum RomaRemotePollingDecision<Result> {
    case finished(Result)
    case keepPolling
}

enum RomaRemotePollingPolicy {
    static let defaultIntervalNanoseconds: UInt64 = 1_000_000_000

    static func poll<Result>(
        maxWaitSeconds: TimeInterval,
        pollIntervalNanoseconds: UInt64 = defaultIntervalNanoseconds,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        operation: () async throws -> RomaRemotePollingDecision<Result>
    ) async throws -> Result {
        let start = now()

        while true {
            switch try await operation() {
            case .finished(let result):
                return result
            case .keepPolling:
                break
            }

            if now().timeIntervalSince(start) > maxWaitSeconds {
                throw URLError(.timedOut)
            }

            try await sleep(pollIntervalNanoseconds)
        }
    }

    static func pollValidatedData<Result>(
        request: () throws -> URLRequest,
        errorDomain: String,
        maxWaitSeconds: TimeInterval,
        decision: @escaping (Data) throws -> RomaRemotePollingDecision<Result>
    ) async throws -> Result {
        try await poll(maxWaitSeconds: maxWaitSeconds) {
            let request = try request()
            let (data, response) = try await URLSession.shared.data(for: request)
            try RomaRemoteHTTPResponsePolicy.validateSuccess(
                response: response,
                data: data,
                errorDomain: errorDomain
            )
            return try decision(data)
        }
    }
}
