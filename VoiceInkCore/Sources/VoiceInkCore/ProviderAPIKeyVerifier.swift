import Foundation

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
