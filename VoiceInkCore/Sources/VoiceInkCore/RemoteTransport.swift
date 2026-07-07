import Foundation

struct VoiceInkMultipartFormData {
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

enum VoiceInkRemoteHTTPResponsePolicy {
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

public struct VoiceInkAPIKeyVerificationResult: Equatable, Sendable {
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

enum VoiceInkAPIKeyVerificationPolicy {
    static let missingAPIKeyMessage = "API key is missing or empty."
    static let missingHTTPResponseMessage = "No HTTP response received."

    static func verify(
        apiKey: String,
        request: @autoclosure () -> URLRequest
    ) async -> VoiceInkAPIKeyVerificationResult {
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

    static func blankAPIKeyResultIfNeeded(_ apiKey: String) -> VoiceInkAPIKeyVerificationResult? {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? missingAPIKeyResult : nil
    }

    static var missingAPIKeyResult: VoiceInkAPIKeyVerificationResult {
        VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: missingAPIKeyMessage)
    }

    static func verificationResult(data: Data, response: URLResponse) -> VoiceInkAPIKeyVerificationResult {
        guard let http = response as? HTTPURLResponse else {
            return VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: missingHTTPResponseMessage)
        }

        guard !VoiceInkRemoteHTTPResponsePolicy.successStatusCodeRange.contains(http.statusCode) else {
            return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        }

        return VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: errorMessage(data: data, statusCode: http.statusCode)
        )
    }

    static func failureResult(_ error: Error) -> VoiceInkAPIKeyVerificationResult {
        VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: error.localizedDescription)
    }

    static func errorMessage(data: Data, statusCode: Int) -> String {
        String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }
}

public enum VoiceInkCartesiaRequestBuilder {
    public static let apiVersion = "2026-03-01"

    public static func makeVoicesRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.cartesiaVoicesURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Cartesia-Version")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkCartesiaClient: Sendable {
    public init() {}

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
            request: VoiceInkCartesiaRequestBuilder.makeVoicesRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

public struct VoiceInkProviderAPIKeyVerifier: Sendable {
    private let openAICompatibleClient: VoiceInkOpenAICompatibleClient
    private let deepgramClient: VoiceInkDeepgramTranscriptionClient
    private let geminiClient: VoiceInkGeminiTranscriptionClient
    private let mistralClient: VoiceInkMistralTranscriptionClient
    private let elevenLabsClient: VoiceInkElevenLabsTranscriptionClient
    private let sonioxClient: VoiceInkSonioxTranscriptionClient
    private let speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient
    private let assemblyAIClient: VoiceInkAssemblyAITranscriptionClient
    private let xaiClient: VoiceInkXAITranscriptionClient
    private let cartesiaClient: VoiceInkCartesiaClient

    public init(
        openAICompatibleClient: VoiceInkOpenAICompatibleClient = VoiceInkOpenAICompatibleClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient(),
        cartesiaClient: VoiceInkCartesiaClient = VoiceInkCartesiaClient()
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
    }

    public func verifyAPIKey(_ apiKey: String, for provider: VoiceInkProviderKind) async -> Bool {
        await verifyAPIKeyDetailed(apiKey, for: provider).isValid
    }

    public func verifyStoredAPIKey(
        _ storedKey: String?,
        for provider: VoiceInkProviderKind,
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
        for provider: VoiceInkProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard provider.canVerifyAPIKey else {
            return await verifyAPIKeyDetailed("", for: provider)
        }

        guard let apiKey = VoiceInkProviderAPIKeyLookup.usableAPIKey(
            storedKey: storedKey,
            provider: provider,
            environment: environment
        ) else {
            return VoiceInkAPIKeyVerificationPolicy.missingAPIKeyResult
        }

        return await verifyAPIKeyDetailed(apiKey, for: provider)
    }

    public func verifyAPIKeyDetailed(
        _ apiKey: String,
        for provider: VoiceInkProviderKind
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard let transport = provider.apiKeyVerificationTransport else {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "\(provider.displayName) does not support API key verification."
            )
        }

        switch transport {
        case .openAICompatibleModels:
            return await openAICompatibleClient.verifyAPIKeyDetailed(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey
            )
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
        }
    }

    public func verifyAPIKeyDetailed(
        _ apiKey: String,
        for transcriptionProvider: VoiceInkTranscriptionModelProvider
    ) async -> VoiceInkAPIKeyVerificationResult {
        if transcriptionProvider == .cartesia {
            return await cartesiaClient.verifyAPIKeyDetailed(
                baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
                apiKey: apiKey
            )
        }

        guard let provider = transcriptionProvider.providerKind else {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "\(transcriptionProvider.rawValue) does not support API key verification."
            )
        }

        return await verifyAPIKeyDetailed(apiKey, for: provider)
    }

    public func verifyStoredAPIKeyDetailed(
        _ storedKey: String?,
        for transcriptionProvider: VoiceInkTranscriptionModelProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard transcriptionProvider != .local else {
            return await verifyAPIKeyDetailed("", for: transcriptionProvider)
        }

        let providerName = transcriptionProvider.providerKind?.displayName ?? transcriptionProvider.rawValue
        guard let apiKey = VoiceInkProviderAPIKeyLookup.usableAPIKey(
            storedKey: storedKey,
            providerName: providerName,
            environment: environment
        ) else {
            return VoiceInkAPIKeyVerificationPolicy.missingAPIKeyResult
        }

        return await verifyAPIKeyDetailed(apiKey, for: transcriptionProvider)
    }

    public func verifyAPIKeyDetailed(
        _ apiKey: String,
        for macOSProvider: VoiceInkMacOSTranscriptionModelProvider
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard let transcriptionProvider = macOSProvider.coreTranscriptionModelProvider else {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: VoiceInkProviderAPIKeyVerificationProgress.unsupportedProviderFailureMessage
            )
        }

        return await verifyAPIKeyDetailed(apiKey, for: transcriptionProvider)
    }

    public func verifyStoredAPIKeyDetailed(
        _ storedKey: String?,
        for macOSProvider: VoiceInkMacOSTranscriptionModelProvider,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard let transcriptionProvider = macOSProvider.coreTranscriptionModelProvider else {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: VoiceInkProviderAPIKeyVerificationProgress.unsupportedProviderFailureMessage
            )
        }

        return await verifyStoredAPIKeyDetailed(
            storedKey,
            for: transcriptionProvider,
            environment: environment
        )
    }
}

enum VoiceInkRetriedRequest {
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
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
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
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
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
                if let statusCode = VoiceInkRemoteHTTPResponsePolicy.retryableStatusCode(in: response),
                   attempt < attempts {
                    lastError = VoiceInkRemoteHTTPResponsePolicy.apiError(
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

public enum VoiceInkOpenAICompatibleModelsRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.openAICompatibleModelsURL(from: baseURL))
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

public struct VoiceInkOpenAICompatibleClient: Sendable {
    public init() {}

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
            request: VoiceInkOpenAICompatibleModelsRequestBuilder.make(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    public func chatCompletion(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double? = 0.2,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) async throws -> String {
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: "LLMPostProcessing"
        )

        return try VoiceInkOpenAICompatibleChatCodec.firstMessageContent(from: data)
    }
}

public struct VoiceInkOpenAICompatibleChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct VoiceInkOpenAICompatibleChatRequest: Codable, Equatable, Sendable {
    public let model: String
    public let messages: [VoiceInkOpenAICompatibleChatMessage]
    public let temperature: Double?

    public init(
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double?
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

public struct VoiceInkOpenAICompatibleChatChoice: Codable, Equatable, Sendable {
    public let message: VoiceInkOpenAICompatibleChatMessage

    public init(message: VoiceInkOpenAICompatibleChatMessage) {
        self.message = message
    }
}

public struct VoiceInkOpenAICompatibleChatResponse: Codable, Equatable, Sendable {
    public let choices: [VoiceInkOpenAICompatibleChatChoice]

    public init(choices: [VoiceInkOpenAICompatibleChatChoice]) {
        self.choices = choices
    }
}

public enum VoiceInkOpenAICompatibleChatCodec {
    public static func requestBody(
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
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

        let request = VoiceInkOpenAICompatibleChatRequest(
            model: model,
            messages: messages,
            temperature: temperature
        )
        return try JSONEncoder().encode(request)
    }

    public static func firstMessageContent(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(VoiceInkOpenAICompatibleChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
}

public enum VoiceInkOpenAICompatibleChatRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [VoiceInkOpenAICompatibleChatMessage],
        temperature: Double?,
        reasoningEffort: String? = nil,
        extraBodyParameters: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try VoiceInkOpenAICompatibleChatCodec.requestBody(
            model: model,
            messages: messages,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            extraBodyParameters: extraBodyParameters
        )
        return request
    }
}

enum VoiceInkRemotePollingDecision<Result> {
    case finished(Result)
    case keepPolling
}

enum VoiceInkRemotePollingPolicy {
    static let defaultIntervalNanoseconds: UInt64 = 1_000_000_000

    static func poll<Result>(
        maxWaitSeconds: TimeInterval,
        pollIntervalNanoseconds: UInt64 = defaultIntervalNanoseconds,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        operation: () async throws -> VoiceInkRemotePollingDecision<Result>
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
        decision: @escaping (Data) throws -> VoiceInkRemotePollingDecision<Result>
    ) async throws -> Result {
        try await poll(maxWaitSeconds: maxWaitSeconds) {
            let request = try request()
            let (data, response) = try await URLSession.shared.data(for: request)
            try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
                response: response,
                data: data,
                errorDomain: errorDomain
            )
            return try decision(data)
        }
    }
}
