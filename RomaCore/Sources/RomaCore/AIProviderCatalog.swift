import Foundation

public enum RomaLocalCLIExecutionError: Error, LocalizedError, Equatable, Sendable {
    case commandNotConfigured
    case commandNotFound(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int, stderr: String)
    case emptyOutput
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return "Local CLI command is not configured. Load a template or enter a command first."
        case .commandNotFound(let details):
            return "Local CLI command was not found. Use an absolute path or fix your shell PATH. Details: \(details)"
        case .timeout(let seconds):
            return "Local CLI command timed out after \(Int(seconds)) seconds."
        case .nonZeroExit(let status, let stderr):
            if stderr.isEmpty {
                return "Local CLI command failed with exit code \(status)."
            }

            return "Local CLI command failed with exit code \(status): \(stderr)"
        case .emptyOutput:
            return "Local CLI command returned empty output."
        case .executionFailed(let message):
            return "Failed to execute Local CLI command: \(message)"
        }
    }
}

public enum RomaAIEnhancementError: Error, Equatable, Sendable {
    case notConfigured
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)

    public static func transportFailure(
        _ failure: RomaAIEnhancementTransportFailure
    ) -> RomaAIEnhancementError {
        switch failure {
        case .missingAPIKey:
            return .notConfigured
        case .httpStatus(let statusCode, let message):
            return httpError(statusCode: statusCode, message: message)
        case .noResultReturned:
            return .enhancementFailed
        case .network:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidRequest(let description):
            guard let description, !description.isEmpty else {
                return .customError("An unknown error occurred.")
            }
            return .customError(description)
        }
    }

    public static func httpError(statusCode: Int, message: String) -> RomaAIEnhancementError {
        if statusCode == 429 {
            return .rateLimitExceeded
        }
        if (500...599).contains(statusCode) {
            return .serverError
        }
        return .customError("HTTP \(statusCode): \(message)")
    }

    public static func transportNetworkError(for error: Error) -> RomaAIEnhancementError? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }

        let retryableNetworkCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost
        ]

        return retryableNetworkCodes.contains(nsError.code) ? .networkError : nil
    }

    public static func localCLIExecutionFailure(_ error: Error) -> RomaAIEnhancementError {
        if let localCLIError = error as? RomaLocalCLIExecutionError {
            return .customError(localCLIError.errorDescription ?? "An unknown Local CLI error occurred.")
        }

        return .customError(error.localizedDescription)
    }
}

public enum RomaAIEnhancementTransportFailure: Equatable, Sendable {
    case missingAPIKey
    case httpStatus(statusCode: Int, message: String)
    case noResultReturned
    case network
    case timeout
    case invalidRequest(description: String?)
}

public enum RomaOllamaEnhancementFailure: Error, Equatable, Sendable {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    case timeout

    public static func transportFailure(
        _ failure: RomaOllamaTransportFailure
    ) -> RomaOllamaEnhancementFailure {
        switch failure {
        case .invalidURL:
            return .invalidURL
        case .httpStatus(let statusCode):
            return httpFailure(statusCode: statusCode)
        case .network:
            return .serviceUnavailable
        case .invalidResponse, .missingCredential:
            return .invalidResponse
        case .invalidRequest:
            return .invalidRequest
        case .timeout:
            return .timeout
        }
    }

    public static func httpFailure(statusCode: Int) -> RomaOllamaEnhancementFailure {
        if statusCode == 404 {
            return .modelNotFound
        }
        if statusCode == 500 {
            return .serverError
        }
        return .invalidResponse
    }

    public var enhancementError: RomaAIEnhancementError {
        switch self {
        case .timeout:
            return .timeout
        case .invalidURL, .serviceUnavailable, .invalidResponse, .modelNotFound, .serverError, .invalidRequest:
            return .customError(message)
        }
    }

    public var message: String {
        switch self {
        case .invalidURL:
            return "Invalid Ollama server URL"
        case .serviceUnavailable:
            return "Ollama service is not available"
        case .invalidResponse:
            return "Invalid response from Ollama server"
        case .modelNotFound:
            return "Selected model not found"
        case .serverError:
            return "Ollama server error"
        case .invalidRequest:
            return "System prompt is required"
        case .timeout:
            return "Ollama request timed out"
        }
    }
}

public enum RomaOllamaTransportFailure: Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case network
    case invalidResponse
    case invalidRequest
    case missingCredential
    case timeout
}

public enum RomaOllamaServiceDiagnostics {
    public static let invalidBaseURLMessage = "Invalid Ollama base URL"

    public static func modelFetchFailedMessage(errorDescription: String) -> String {
        "Error fetching models: \(errorDescription)"
    }
}

extension RomaOllamaEnhancementFailure: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

extension RomaAIEnhancementError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        }
    }
}

public enum RomaAIEnhancementRetryDecision: Equatable, Sendable {
    case retryAfterDelay(TimeInterval)
    case retryImmediately
    case fail(RomaAIEnhancementError)
}

public struct RomaAIEnhancementRetryState: Equatable, Sendable {
    public let maxAttempts: Int
    public let retryOnTimeout: Bool
    public private(set) var failedAttempts: Int
    public private(set) var nextDelay: TimeInterval

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1,
        retryOnTimeout: Bool = true
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryOnTimeout = retryOnTimeout
        self.failedAttempts = 0
        self.nextDelay = initialDelay
    }

    public mutating func recordFailure(_ error: RomaAIEnhancementError) -> RomaAIEnhancementRetryDecision {
        switch error {
        case .networkError, .serverError, .rateLimitExceeded:
            return recordBackoffFailure(error)
        case .timeout where retryOnTimeout:
            return recordImmediateFailure(error)
        case .timeout, .notConfigured, .enhancementFailed, .customError:
            return .fail(error)
        }
    }

    public mutating func recordTransportNetworkFailure() -> RomaAIEnhancementRetryDecision {
        recordBackoffFailure(.networkError)
    }

    public mutating func recordNonEnhancementError(_ error: Error) -> RomaAIEnhancementNonEnhancementErrorRetryPlan? {
        guard RomaAIEnhancementError.transportNetworkError(for: error) == .networkError else {
            return nil
        }

        return RomaAIEnhancementNonEnhancementErrorRetryPlan(
            decision: recordTransportNetworkFailure(),
            isTransportNetworkFailure: true
        )
    }

    private mutating func recordBackoffFailure(_ error: RomaAIEnhancementError) -> RomaAIEnhancementRetryDecision {
        failedAttempts += 1
        guard failedAttempts < maxAttempts else {
            return .fail(error)
        }

        let delay = nextDelay
        nextDelay *= 2
        return .retryAfterDelay(delay)
    }

    private mutating func recordImmediateFailure(_ error: RomaAIEnhancementError) -> RomaAIEnhancementRetryDecision {
        failedAttempts += 1
        guard failedAttempts < maxAttempts else {
            return .fail(error)
        }

        return .retryImmediately
    }
}

public struct RomaAIEnhancementNonEnhancementErrorRetryPlan: Equatable, Sendable {
    private let decision: RomaAIEnhancementRetryDecision
    private let isTransportNetworkFailure: Bool

    init(decision: RomaAIEnhancementRetryDecision, isTransportNetworkFailure: Bool) {
        self.decision = decision
        self.isTransportNetworkFailure = isTransportNetworkFailure
    }

    public func applyRuntimeState(
        handleRetryDecision: (RomaAIEnhancementRetryDecision, Bool) async throws -> Void
    ) async throws {
        try await handleRetryDecision(decision, isTransportNetworkFailure)
    }
}

public struct RomaAIEnhancementRateLimitPolicy: Equatable, Sendable {
    public let minimumInterval: TimeInterval

    public init(minimumInterval: TimeInterval = 1) {
        self.minimumInterval = max(0, minimumInterval)
    }

    public func delaySinceLastRequest(lastRequest: Date?, now: Date) -> TimeInterval? {
        guard let lastRequest else {
            return nil
        }

        let remainingDelay = minimumInterval - now.timeIntervalSince(lastRequest)
        return remainingDelay > 0 ? remainingDelay : nil
    }
}

public enum RomaAIEnhancementRetryProgressPresentation {
    public static func diagnosticMessage(
        for decision: RomaAIEnhancementRetryDecision,
        failedAttempts: Int,
        maxAttempts: Int
    ) -> String? {
        switch decision {
        case .retryAfterDelay(let delay):
            return "Request failed, retrying in \(delay)s... (Attempt \(failedAttempts)/\(maxAttempts))"
        case .retryImmediately:
            return "Request timed out, retrying immediately... (Attempt \(failedAttempts)/\(maxAttempts))"
        case .fail:
            return nil
        }
    }
}

public enum RomaAIEnhancementRetryFailurePresentation {
    public static func diagnosticMessage(
        for error: RomaAIEnhancementError,
        attempts: Int,
        retryOnTimeoutEnabled: Bool,
        transportNetworkFailure: Bool = false
    ) -> String? {
        switch error {
        case .timeout where retryOnTimeoutEnabled:
            return "Request timed out after \(attempts) retries."
        case .timeout:
            return "Request timed out, failing immediately (retry disabled)."
        case .networkError where transportNetworkFailure:
            return "Request failed after \(attempts) retries with network error."
        case .networkError, .serverError, .rateLimitExceeded:
            return "Request failed after \(attempts) retries."
        default:
            return nil
        }
    }
}

public enum RomaAIEnhancementOutputFilter {
    public static func filter(_ text: String) -> String {
        var processedText = text
        let patterns = [
            #"(?s)<thinking>(.*?)</thinking>"#,
            #"(?s)<think>(.*?)</think>"#,
            #"(?s)<reasoning>(.*?)</reasoning>"#,
            #"(?s)\s*```json\s*\{.*?"codex_follow_up"\s*:\s*true.*?\}\s*```\s*$"#,
            #"(?s)\s*\{\s*"codex_follow_up"\s*:\s*true.*\}\s*$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(processedText.startIndex..., in: processedText)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: "")
            }
        }

        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RomaAIEnhancementRequestPayload: Equatable, Sendable {
    public let userMessage: String

    public init?(transcript: String) {
        guard !transcript.isEmpty else {
            return nil
        }

        self.userMessage = RomaAIRequestPrompts.taggedTranscript(transcript)
    }

    public static func enhancedText(from providerOutput: String) -> String {
        RomaAIEnhancementOutputFilter.filter(providerOutput)
    }
}

public enum RomaAIEnhancementRequestPreparation: Equatable, Sendable {
    case skipEmptyTranscript
    case execute(RomaAIEnhancementRequestPayload)

    public static func preparing(
        transcript: String,
        isConfigured: Bool
    ) throws -> RomaAIEnhancementRequestPreparation {
        guard isConfigured else {
            throw RomaAIEnhancementError.notConfigured
        }

        guard let requestPayload = RomaAIEnhancementRequestPayload(transcript: transcript) else {
            return .skipEmptyTranscript
        }

        return .execute(requestPayload)
    }
}

public struct RomaAIEnhancementPromptContext: Equatable, Sendable {
    public let surroundingTextBeforeCursor: String?
    public let selectedText: String?
    public let clipboardText: String?
    public let currentWindowText: String?
    public let customVocabulary: String

    public init(
        surroundingTextBeforeCursor: String? = nil,
        selectedText: String? = nil,
        clipboardText: String? = nil,
        currentWindowText: String? = nil,
        customVocabulary: String = ""
    ) {
        self.surroundingTextBeforeCursor = surroundingTextBeforeCursor
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.currentWindowText = currentWindowText
        self.customVocabulary = customVocabulary
    }
}

public enum RomaSelectedTextDiagnostics {
    public static func fetchFailedMessage(errorDescription: String) -> String {
        "Failed to get selected text: \(errorDescription)"
    }
}

public enum RomaAIEnhancementPromptBuilder {
    public static func systemMessage(
        basePrompt: String,
        context: RomaAIEnhancementPromptContext = RomaAIEnhancementPromptContext()
    ) -> String {
        basePrompt
            + taggedSection("SURROUNDING_TEXT_BEFORE_CURSOR", text: context.surroundingTextBeforeCursor)
            + taggedSection("CURRENTLY_SELECTED_TEXT", text: context.selectedText)
            + taggedSection("CLIPBOARD_CONTEXT", text: context.clipboardText)
            + taggedSection("CURRENT_WINDOW_CONTEXT", text: context.currentWindowText)
            + customVocabularySection(context.customVocabulary)
    }

    private static func taggedSection(_ tag: String, text: String?) -> String {
        guard let text, !text.isEmpty else {
            return ""
        }

        return "\n\n<\(tag)>\n\(text)\n</\(tag)>"
    }

    private static func customVocabularySection(_ customVocabulary: String) -> String {
        guard !customVocabulary.isEmpty else {
            return ""
        }

        return """


        The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
        <CUSTOM_VOCABULARY>
        \(customVocabulary)
        </CUSTOM_VOCABULARY>
        """
    }
}

public enum RomaAIEnhancementVocabularyContext {
    public static func formatted(from terms: [String]) -> String {
        let normalizedTerms = RomaCustomVocabularyTerms.normalized(terms, for: .postProcessingContext)
        guard !normalizedTerms.isEmpty else {
            return ""
        }

        return "Important Vocabulary: \(normalizedTerms.joined(separator: ", "))"
    }
}

public struct RomaScreenCaptureWindowFacts: Equatable, Sendable {
    public let processID: Int?
    public let layer: Int
    public let isOnScreen: Bool
    public let title: String?
    public let applicationName: String?

    public init(
        processID: Int?,
        layer: Int,
        isOnScreen: Bool,
        title: String?,
        applicationName: String?
    ) {
        self.processID = processID
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.title = title
        self.applicationName = applicationName
    }
}

public enum RomaAIEnhancementScreenContext {
    public static let unknownWindowValue = "Unknown"
    public static let noTextDetectedMessage = "No text detected via OCR"

    public static func preferredWindowIndex(
        in windows: [RomaScreenCaptureWindowFacts],
        currentProcessID: Int,
        frontmostProcessID: Int?
    ) -> Int? {
        if let frontmostProcessID,
           let frontmostIndex = windows.firstIndex(where: {
               isCaptureCandidate($0, currentProcessID: currentProcessID)
                   && $0.processID == frontmostProcessID
           }) {
            return frontmostIndex
        }

        return windows.firstIndex {
            isCaptureCandidate($0, currentProcessID: currentProcessID)
        }
    }

    public static func contextText(
        window: RomaScreenCaptureWindowFacts,
        extractedText: String?
    ) -> String {
        let title = window.title ?? window.applicationName ?? unknownWindowValue
        let appName = window.applicationName ?? unknownWindowValue
        let content = if let extractedText, !extractedText.isEmpty {
            extractedText
        } else {
            noTextDetectedMessage
        }

        return """
        Active Window: \(title)
        Application: \(appName)

        Window Content:
        \(content)
        """
    }

    public static func extractedText(fromRecognizedCandidates candidates: [String]) -> String? {
        let text = candidates.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func isCaptureCandidate(
        _ window: RomaScreenCaptureWindowFacts,
        currentProcessID: Int
    ) -> Bool {
        window.processID != currentProcessID
            && window.layer == 0
            && window.isOnScreen
    }
}

public enum RomaAIEnhancementProviderKeyChangeRequest {
    public static let notificationName = Notification.Name("aiProviderKeyChanged")
}

public enum RomaAIModelProvider: String, CaseIterable, Sendable {
    case anthropic
    case assemblyAI
    case cerebras
    case deepgram
    case elevenLabs
    case groq
    case gemini
    case mistral
    case openAI
    case openRouter
    case soniox
    case speechmatics
}

public enum RomaAIModelCatalog {
    public static func defaultModel(for provider: RomaAIModelProvider) -> String {
        switch provider {
        case .anthropic:
            return "claude-sonnet-4-6"
        case .assemblyAI:
            return "universal-3-pro"
        case .cerebras:
            return "gpt-oss-120b"
        case .deepgram:
            return "whisper-1"
        case .elevenLabs:
            return "scribe_v2"
        case .groq:
            return "openai/gpt-oss-120b"
        case .gemini:
            return "gemini-2.5-flash-lite"
        case .mistral:
            return "mistral-large-latest"
        case .openAI:
            return "gpt-5.4"
        case .openRouter:
            return "openai/gpt-oss-120b"
        case .soniox:
            return "stt-async-v4"
        case .speechmatics:
            return "speechmatics-enhanced"
        }
    }

    public static func firstAvailableModel(for provider: RomaAIModelProvider) -> String {
        availableModels(for: provider).first ?? defaultModel(for: provider)
    }

    public static func availableModels(for provider: RomaAIModelProvider) -> [String] {
        switch provider {
        case .anthropic:
            return [
                "claude-opus-4-7",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        case .assemblyAI:
            return ["universal-3-pro"]
        case .cerebras:
            return [
                "gpt-oss-120b",
                "zai-glm-4.7"
            ]
        case .deepgram:
            return ["whisper-1"]
        case .elevenLabs:
            return ["scribe_v1", "scribe_v2"]
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "qwen/qwen3-32b",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-3.5-flash",
                "gemini-3.1-pro-preview",
                "gemini-3-flash-preview",
                "gemini-3.1-flash-lite",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite"
            ]
        case .mistral:
            return [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest"
            ]
        case .openAI:
            return [
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-5.2",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano"
            ]
        case .openRouter:
            return []
        case .soniox:
            return ["stt-async-v4"]
        case .speechmatics:
            return ["speechmatics-enhanced"]
        }
    }
}

public struct RomaAIChatRequestParameters {
    public let temperature: Double
    public let reasoningEffort: String?
    public let extraBodyParameters: [String: Any]?

    public init(
        temperature: Double,
        reasoningEffort: String?,
        extraBodyParameters: [String: Any]?
    ) {
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.extraBodyParameters = extraBodyParameters
    }
}

public enum RomaAIReasoningConfig {
    public static func temperature(forModelName modelName: String, defaultTemperature: Double = 0.3) -> Double {
        modelName.lowercased().hasPrefix("gpt-5") ? 1.0 : defaultTemperature
    }

    public static func chatRequestParameters(
        for provider: RomaAIModelProvider?,
        modelName: String,
        defaultTemperature: Double = 0.3
    ) -> RomaAIChatRequestParameters {
        RomaAIChatRequestParameters(
            temperature: temperature(forModelName: modelName, defaultTemperature: defaultTemperature),
            reasoningEffort: provider.flatMap {
                reasoningEffort(for: $0, modelName: modelName)
            },
            extraBodyParameters: provider.flatMap {
                extraBodyParameters(for: $0, modelName: modelName)
            }
        )
    }

    private static let geminiNoneReasoningModels: Set<String> = [
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite"
    ]

    private static let geminiLowReasoningModels: Set<String> = [
        "gemini-3.1-pro-preview"
    ]

    private static let geminiMinimalReasoningModels: Set<String> = [
        "gemini-3.5-flash",
        "gemini-2.5-pro",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite"
    ]

    private static let openAINoneReasoningModels: Set<String> = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
        "gpt-5.2"
    ]

    private static let cerebrasGPTOSSMinimumReasoningModels: Set<String> = [
        "gpt-oss-120b"
    ]

    private static let groqGPTOSSMinimumReasoningModels: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b"
    ]

    private static let cerebrasNoneReasoningModels: Set<String> = [
        "zai-glm-4.7"
    ]

    private static let groqQwenReasoningModels: Set<String> = [
        "qwen/qwen3-32b"
    ]

    public static func reasoningEffort(
        for provider: RomaAIModelProvider,
        modelName: String
    ) -> String? {
        switch provider {
        case .gemini:
            if geminiNoneReasoningModels.contains(modelName) { return "none" }
            if geminiLowReasoningModels.contains(modelName) { return "low" }
            if geminiMinimalReasoningModels.contains(modelName) { return "minimal" }
        case .openAI:
            if openAINoneReasoningModels.contains(modelName) { return "none" }
        case .cerebras:
            if cerebrasGPTOSSMinimumReasoningModels.contains(modelName) { return "low" }
            if cerebrasNoneReasoningModels.contains(modelName) { return "none" }
        case .groq:
            if groqGPTOSSMinimumReasoningModels.contains(modelName) { return "low" }
            if groqQwenReasoningModels.contains(modelName) { return "none" }
        case .anthropic, .assemblyAI, .deepgram, .elevenLabs, .mistral, .openRouter, .soniox, .speechmatics:
            break
        }
        return nil
    }

    public static func extraBodyParameters(
        for provider: RomaAIModelProvider,
        modelName: String
    ) -> [String: Any]? {
        if provider == .cerebras && modelName == "gpt-oss-120b" {
            return ["reasoning_format": "hidden"]
        }
        if provider == .groq && (modelName == "openai/gpt-oss-120b" || modelName == "openai/gpt-oss-20b") {
            return ["include_reasoning": false]
        }
        return nil
    }
}

private enum RomaAIEnhancementRequestExecutionAction: Sendable, Equatable {
    case ollama
    case localCLI
    case anthropicMessages
    case openAICompatibleChatCompletions
}

struct RomaAIEnhancementOpenAICompatibleRequestPlan {
    let requestURL: URL
    let requestParameters: RomaAIChatRequestParameters

    func applyRuntimeState<Result>(
        modelName: String,
        execute: (String, URL, RomaAIChatRequestParameters) async throws -> Result
    ) async throws -> Result {
        try await execute(modelName, requestURL, requestParameters)
    }
}

public struct RomaAIEnhancementRequestExecutionPlan {
    private let action: RomaAIEnhancementRequestExecutionAction
    private let modelName: String
    private let openAICompatibleRequest: RomaAIEnhancementOpenAICompatibleRequestPlan?
    private let requestPreparationError: RomaAIEnhancementError?

    public static func planning(
        provider: RomaAIEnhancementProviderKind,
        modelName: String,
        defaults: UserDefaults = .standard
    ) -> RomaAIEnhancementRequestExecutionPlan {
        let action: RomaAIEnhancementRequestExecutionAction
        switch provider {
        case .ollama:
            action = .ollama
        case .localCLI:
            action = .localCLI
        case .anthropic:
            action = .anthropicMessages
        case .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .groq, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            action = .openAICompatibleChatCompletions
        }

        guard action == .openAICompatibleChatCompletions else {
            return RomaAIEnhancementRequestExecutionPlan(
                action: action,
                modelName: modelName,
                openAICompatibleRequest: nil,
                requestPreparationError: nil
            )
        }

        guard let requestURL = provider.textEnhancementRequestURL(from: defaults) else {
            return RomaAIEnhancementRequestExecutionPlan(
                action: action,
                modelName: modelName,
                openAICompatibleRequest: nil,
                requestPreparationError: .customError(provider.invalidTextEnhancementRequestURLMessage)
            )
        }

        return RomaAIEnhancementRequestExecutionPlan(
            action: action,
            modelName: modelName,
            openAICompatibleRequest: RomaAIEnhancementOpenAICompatibleRequestPlan(
                requestURL: requestURL,
                requestParameters: RomaAIReasoningConfig.chatRequestParameters(
                    for: provider.aiModelProvider,
                    modelName: modelName
                )
            ),
            requestPreparationError: nil
        )
    }

    public func applyRuntimeState<Result>(
        ollama: (String) async throws -> Result,
        localCLI: (String) async throws -> Result,
        anthropicMessages: (String) async throws -> Result,
        openAICompatibleChatCompletions: (String, URL, RomaAIChatRequestParameters) async throws -> Result
    ) async throws -> Result {
        switch action {
        case .ollama:
            return try await ollama(modelName)
        case .localCLI:
            return try await localCLI(modelName)
        case .anthropicMessages:
            return try await anthropicMessages(modelName)
        case .openAICompatibleChatCompletions:
            return try await openAICompatibleRequestOrThrow().applyRuntimeState(
                modelName: modelName,
                execute: openAICompatibleChatCompletions
            )
        }
    }

    private func openAICompatibleRequestOrThrow() throws -> RomaAIEnhancementOpenAICompatibleRequestPlan {
        if let openAICompatibleRequest {
            return openAICompatibleRequest
        }

        if let requestPreparationError {
            throw requestPreparationError
        }

        preconditionFailure("OpenAI-compatible request plan is only available for OpenAI-compatible routes.")
    }
}

public struct RomaAIEnhancementProviderSelectionPlan: Sendable, Equatable {
    let selectedProviderToSave: RomaAIEnhancementProviderKind
    private let shouldRefreshOllamaRuntimeModels: Bool

    init(
        selectedProviderToSave: RomaAIEnhancementProviderKind,
        shouldRefreshOllamaRuntimeModels: Bool
    ) {
        self.selectedProviderToSave = selectedProviderToSave
        self.shouldRefreshOllamaRuntimeModels = shouldRefreshOllamaRuntimeModels
    }

    public static func selecting(
        _ provider: RomaAIEnhancementProviderKind
    ) -> RomaAIEnhancementProviderSelectionPlan {
        RomaAIEnhancementProviderSelectionPlan(
            selectedProviderToSave: provider,
            shouldRefreshOllamaRuntimeModels: provider == .ollama
        )
    }
}

public extension RomaAIEnhancementProviderSelectionPlan {
    func applyRuntimeState(
        applyPersistence: (RomaAIEnhancementProviderSelectionPlan) -> Void,
        applyCredentialState: () -> Void,
        refreshOllamaRuntimeModels: () -> Void,
        postSettingsChanged: () -> Void
    ) {
        applyPersistence(self)
        applyCredentialState()
        if shouldRefreshOllamaRuntimeModels {
            refreshOllamaRuntimeModels()
        }
        postSettingsChanged()
    }
}

public struct RomaAIEnhancementModelRefreshPlan: Sendable, Equatable {
    let refreshedModelNames: [String]
    let selectedModelToSave: String?

    init(refreshedModelNames: [String], selectedModelToSave: String?) {
        self.refreshedModelNames = refreshedModelNames
        self.selectedModelToSave = selectedModelToSave
    }

    public static func refreshed(
        provider: RomaAIEnhancementProviderKind,
        currentModel: String,
        refreshedModels: [String],
        defaultModel: String
    ) -> RomaAIEnhancementModelRefreshPlan {
        RomaAIEnhancementModelRefreshPlan(
            refreshedModelNames: refreshedModels,
            selectedModelToSave: provider.textEnhancementModelToSelectAfterRefresh(
                currentModel: currentModel,
                refreshedModels: refreshedModels,
                defaultModel: defaultModel
            )
        )
    }

    public static let failed = RomaAIEnhancementModelRefreshPlan(
        refreshedModelNames: [],
        selectedModelToSave: nil
    )
}

public extension RomaAIEnhancementModelRefreshPlan {
    func applyOpenRouterRuntimeState(
        setOpenRouterModels: ([String]) -> Void,
        applyPersistence: (RomaAIEnhancementModelRefreshPlan) -> String?,
        setSelectedOpenRouterModel: (String) -> Void,
        postSettingsChanged: () -> Void,
        sendObjectWillChange: () -> Void
    ) {
        setOpenRouterModels(refreshedModelNames)
        if let refreshedModel = applyPersistence(self) {
            setSelectedOpenRouterModel(refreshedModel)
            postSettingsChanged()
        }
        sendObjectWillChange()
    }
}

public struct RomaAIEnhancementModelSelectionPlan: Sendable, Equatable {
    let selectedModels: [RomaAIEnhancementProviderKind: String]
    let provider: RomaAIEnhancementProviderKind
    let selectedModelToSave: String
    let ollamaModelToApply: String?

    init(
        selectedModels: [RomaAIEnhancementProviderKind: String],
        provider: RomaAIEnhancementProviderKind,
        selectedModelToSave: String,
        ollamaModelToApply: String?
    ) {
        self.selectedModels = selectedModels
        self.provider = provider
        self.selectedModelToSave = selectedModelToSave
        self.ollamaModelToApply = ollamaModelToApply
    }

    public static func selecting(
        _ model: String,
        provider: RomaAIEnhancementProviderKind,
        selectedModels: [RomaAIEnhancementProviderKind: String]
    ) -> RomaAIEnhancementModelSelectionPlan? {
        guard !model.isEmpty else { return nil }

        var updatedSelectedModels = selectedModels
        updatedSelectedModels[provider] = model

        return RomaAIEnhancementModelSelectionPlan(
            selectedModels: updatedSelectedModels,
            provider: provider,
            selectedModelToSave: model,
            ollamaModelToApply: provider == .ollama ? model : nil
        )
    }
}

public extension RomaAIEnhancementModelSelectionPlan {
    func applyRuntimeState(
        setSelectedModels: ([RomaAIEnhancementProviderKind: String]) -> Void,
        applyPersistence: (RomaAIEnhancementModelSelectionPlan) -> Void,
        setOllamaRuntimeModel: (String) -> Void,
        sendObjectWillChange: () -> Void,
        postSettingsChanged: () -> Void
    ) {
        setSelectedModels(selectedModels)
        applyPersistence(self)
        if let ollamaModelToApply {
            setOllamaRuntimeModel(ollamaModelToApply)
        }
        sendObjectWillChange()
        postSettingsChanged()
    }
}

public enum RomaAIEnhancementConnectionStatusTone: Sendable, Equatable {
    case connected
    case disconnected
}

public enum RomaAIEnhancementConnectionStatusPresentation: Sendable, Equatable {
    case checking
    case status(text: String, tone: RomaAIEnhancementConnectionStatusTone)
}

public struct RomaAIEnhancementModelPickerPresentation: Sendable, Equatable {
    public let isModelPickerVisible: Bool
    public let isRefreshButtonVisible: Bool
    public let emptyStateText: String?

    public init(
        isModelPickerVisible: Bool,
        isRefreshButtonVisible: Bool,
        emptyStateText: String?
    ) {
        self.isModelPickerVisible = isModelPickerVisible
        self.isRefreshButtonVisible = isRefreshButtonVisible
        self.emptyStateText = emptyStateText
    }
}

public struct RomaAIEnhancementAPIKeyControlPresentation: Sendable, Equatable {
    public let isVerificationProgressVisible: Bool
    public let isDefaultVerifyAndSaveButtonDisabled: Bool
    public let isCustomVerifyAndSaveButtonDisabled: Bool

    public init(
        isVerificationProgressVisible: Bool,
        isDefaultVerifyAndSaveButtonDisabled: Bool,
        isCustomVerifyAndSaveButtonDisabled: Bool
    ) {
        self.isVerificationProgressVisible = isVerificationProgressVisible
        self.isDefaultVerifyAndSaveButtonDisabled = isDefaultVerifyAndSaveButtonDisabled
        self.isCustomVerifyAndSaveButtonDisabled = isCustomVerifyAndSaveButtonDisabled
    }
}

public struct RomaMacOSLocalCLISettingsPresentation: Equatable, Sendable {
    public let commandTitle: String
    public let loadTemplateButtonTitle: String
    public let timeoutPickerTitle: String
    public let environmentHelpText: String
    public let configurationRequiredHelpText: String

    public static let macOS = RomaMacOSLocalCLISettingsPresentation(
        commandTitle: "Command",
        loadTemplateButtonTitle: "Load Template",
        timeoutPickerTitle: "Timeout",
        environmentHelpText: "Environment variables available: ROMA_SYSTEM_PROMPT, ROMA_USER_PROMPT, ROMA_FULL_PROMPT. Roma Just Talk also writes ROMA_FULL_PROMPT to stdin for every command.",
        configurationRequiredHelpText: "Load a template or enter a command to enable Local CLI enhancement."
    )
}

public enum RomaLocalCLITemplate: String, CaseIterable, Identifiable, Sendable {
    case pi
    case claude
    case codex
    case copilot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pi:
            return "Pi"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .copilot:
            return "Copilot"
        }
    }

    public var commandTemplate: String {
        switch self {
        case .pi:
            return "pi -ne -ns -p --no-tools --system-prompt \"$ROMA_SYSTEM_PROMPT\" \"$ROMA_USER_PROMPT\""
        case .claude:
            return "claude -p \"$ROMA_FULL_PROMPT\""
        case .codex:
            return "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --output-last-message \"$TMPFILE\" \"$ROMA_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        case .copilot:
            return "copilot -p \"$ROMA_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        }
    }
}

public enum RomaLocalCLIPreference {
    public static let commandTemplateKey = "localCLICommandTemplate"
    public static let selectedTemplateKey = "localCLISelectedTemplate"
    public static let timeoutSecondsKey = "localCLITimeoutSeconds"
    public static let macOSSettingsPresentation = RomaMacOSLocalCLISettingsPresentation.macOS
    public static let defaultTimeoutSeconds: Double = 45
    public static let minimumTimeoutSeconds: Double = 5
    public static let timeoutOptions: [Double] = [15, 30, 45, 60, 90, 120, 180, 300]

    public static func commandTemplate(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: commandTemplateKey) ?? ""
    }

    public static func saveCommandTemplate(
        _ commandTemplate: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(commandTemplate, forKey: commandTemplateKey)
    }

    public static func selectedTemplate(from defaults: UserDefaults = .standard) -> RomaLocalCLITemplate {
        guard let rawValue = defaults.string(forKey: selectedTemplateKey),
              let template = RomaLocalCLITemplate(rawValue: rawValue)
        else {
            return .pi
        }

        return template
    }

    public static func saveSelectedTemplate(
        _ template: RomaLocalCLITemplate,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(template.rawValue, forKey: selectedTemplateKey)
    }

    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> Double {
        let storedTimeout = defaults.double(forKey: timeoutSecondsKey)
        guard storedTimeout > 0 else {
            return defaultTimeoutSeconds
        }

        return storedTimeout
    }

    public static func saveTimeoutSeconds(
        _ timeoutSeconds: Double,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(boundedTimeoutSeconds(timeoutSeconds), forKey: timeoutSecondsKey)
    }

    public static func boundedTimeoutSeconds(_ timeoutSeconds: Double) -> Double {
        max(minimumTimeoutSeconds, timeoutSeconds)
    }

    public static func timeoutLabel(for timeoutSeconds: Double) -> String {
        "\(Int(timeoutSeconds))s"
    }

    public static func isCommandConfigured(_ commandTemplate: String) -> Bool {
        !commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func cleanedOutput(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func commandFailureError(
        terminationStatus: Int,
        stderr: String,
        commandTemplate: String
    ) -> RomaLocalCLIExecutionError {
        let cleanedStderr = cleanedOutput(stderr)
        let looksLikeCommandNotFound = terminationStatus == 127 ||
            cleanedStderr.lowercased().contains("command not found")

        if looksLikeCommandNotFound {
            return .commandNotFound(cleanedStderr.isEmpty ? commandTemplate : cleanedStderr)
        }

        return .nonZeroExit(status: terminationStatus, stderr: cleanedStderr)
    }

    public static func fullPrompt(systemPrompt: String, userPrompt: String) -> String {
        """
        <SYSTEM_PROMPT>
        \(systemPrompt)
        </SYSTEM_PROMPT>

        <USER_PROMPT>
        \(userPrompt)
        </USER_PROMPT>
        """
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: commandTemplateKey)
        defaults.removeObject(forKey: selectedTemplateKey)
        defaults.removeObject(forKey: timeoutSecondsKey)
    }
}

public struct RomaAIEnhancementProviderSettingsPresentation: Sendable, Equatable {
    public let sectionTitle: String
    public let providerPickerTitle: String
    public let modelPickerTitle: String
    public let noModelsLoadedText: String
    public let refreshButtonTitle: String
    public let defaultAPIKeyRemoveButtonTitle: String
    public let getAPIKeyButtonTitle: String
    public let errorAlertTitle: String
    public let errorAlertDismissButtonTitle: String
    public let connectedText: String
    public let disconnectedText: String
    public let apiKeyFieldTitle: String
    public let verifyAndSaveButtonTitle: String
    public let ollamaBaseURLFieldTitle: String
    public let ollamaSaveButtonTitle: String
    public let ollamaEditButtonTitle: String
    public let ollamaResetButtonHelp: String
    public let ollamaConnectionFailureMessage: String
    public let customProviderBaseURLFieldTitle: String
    public let customProviderBaseURLPlaceholder: String
    public let customProviderModelFieldTitle: String
    public let customProviderModelPlaceholder: String
    public let customProviderAPIKeySetText: String
    public let customProviderRemoveKeyButtonTitle: String

    public static let macOS = RomaAIEnhancementProviderSettingsPresentation(
        sectionTitle: "AI Provider Integration",
        providerPickerTitle: "Provider",
        modelPickerTitle: "Model",
        noModelsLoadedText: "No models loaded",
        refreshButtonTitle: "Refresh",
        defaultAPIKeyRemoveButtonTitle: "Remove",
        getAPIKeyButtonTitle: "Get API Key",
        errorAlertTitle: "Error",
        errorAlertDismissButtonTitle: "OK",
        connectedText: "Connected",
        disconnectedText: "Disconnected",
        apiKeyFieldTitle: "API Key",
        verifyAndSaveButtonTitle: "Verify and Save",
        ollamaBaseURLFieldTitle: "Base URL",
        ollamaSaveButtonTitle: "Save",
        ollamaEditButtonTitle: "Edit",
        ollamaResetButtonHelp: "Reset to default",
        ollamaConnectionFailureMessage: "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct.",
        customProviderBaseURLFieldTitle: "API Endpoint URL",
        customProviderBaseURLPlaceholder: "e.g. https://api.openai.com/v1/chat/completions",
        customProviderModelFieldTitle: "Model Name",
        customProviderModelPlaceholder: "e.g. gemini-3.1-pro-preview, gpt-5.5",
        customProviderAPIKeySetText: "API Key Set",
        customProviderRemoveKeyButtonTitle: "Remove Key"
    )

    public static let iOS = macOS

    public func connectionStatus(
        provider: RomaAIEnhancementProviderKind,
        isAPIKeyValid: Bool,
        isCheckingOllama: Bool,
        hasOllamaModels: Bool
    ) -> RomaAIEnhancementConnectionStatusPresentation? {
        switch provider {
        case .ollama:
            if isCheckingOllama {
                return .checking
            }

            return hasOllamaModels
                ? .status(text: connectedText, tone: .connected)
                : .status(text: disconnectedText, tone: .disconnected)
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .groq, .localCLI, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            return isAPIKeyValid
                ? .status(text: connectedText, tone: .connected)
                : nil
        }
    }

    public func modelPickerPresentation(
        provider: RomaAIEnhancementProviderKind,
        availableModels: [String]
    ) -> RomaAIEnhancementModelPickerPresentation {
        switch provider {
        case .openRouter:
            return RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: !availableModels.isEmpty,
                isRefreshButtonVisible: true,
                emptyStateText: availableModels.isEmpty ? noModelsLoadedText : nil
            )
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .soniox, .speechmatics:
            return RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: !availableModels.isEmpty,
                isRefreshButtonVisible: false,
                emptyStateText: nil
            )
        case .custom, .localCLI, .ollama:
            return RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: false,
                isRefreshButtonVisible: false,
                emptyStateText: nil
            )
        }
    }

    public func ollamaServerText(baseURL: String) -> String {
        "Server: \(baseURL)"
    }

    public func canSubmitCustomProvider(
        baseURL: String,
        modelName: String,
        hasDraftAPIKey: Bool
    ) -> Bool {
        !baseURL.isEmpty && !modelName.isEmpty && hasDraftAPIKey
    }

    public func apiKeyControlPresentation(
        formState: RomaAIEnhancementAPIKeyFormState,
        provider: RomaAIEnhancementProviderKind,
        customProviderBaseURL: String,
        customProviderModelName: String
    ) -> RomaAIEnhancementAPIKeyControlPresentation {
        let draft = formState.draft(for: provider)
        return RomaAIEnhancementAPIKeyControlPresentation(
            isVerificationProgressVisible: formState.isVerifying,
            isDefaultVerifyAndSaveButtonDisabled: !draft.hasEnteredKey,
            isCustomVerifyAndSaveButtonDisabled: !canSubmitCustomProvider(
                baseURL: customProviderBaseURL,
                modelName: customProviderModelName,
                hasDraftAPIKey: draft.hasEnteredKey
            )
        )
    }
}

public struct RomaAIEnhancementAPIKeyDraft: Equatable, Sendable {
    private let provider: RomaAIEnhancementProviderKind
    private let providerKeyDraft: RomaProviderAPIKeyDraft

    public init(
        provider: RomaAIEnhancementProviderKind,
        enteredKey: String?,
        storedRuntimeKey: String? = nil
    ) {
        self.provider = provider
        self.providerKeyDraft = RomaProviderAPIKeyDraft(
            enteredKey: enteredKey,
            storedRuntimeKey: storedRuntimeKey
        )
    }

    public var hasEnteredKey: Bool {
        providerKeyDraft.hasEnteredKey
    }

    public var canVerify: Bool {
        provider.requiresUserAPIKey && providerKeyDraft.canVerify
    }

    public var keyToSaveAfterSuccessfulVerification: String? {
        guard provider.requiresUserAPIKey else {
            return nil
        }
        return providerKeyDraft.keyToSaveAfterSuccessfulVerification
    }

    public func resolvedVerificationCandidate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard provider.requiresUserAPIKey,
              let candidate = providerKeyDraft.verificationCandidate else {
            return nil
        }
        return RomaAPIKeyReference.resolvedValue(candidate, environment: environment)
    }

    public func verificationRequestPlan(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RomaAIEnhancementAPIKeyVerificationRequestPlan {
        guard provider.requiresUserAPIKey else {
            return RomaAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        }

        guard let resolvedKey = resolvedVerificationCandidate(environment: environment) else {
            return RomaAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: RomaAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: RomaAIEnhancementProviderKind.missingVerificationCandidateMessage
                )
            )
        }

        return RomaAIEnhancementAPIKeyVerificationRequestPlan(
            resolvedKeyToVerify: resolvedKey,
            immediateResult: nil
        )
    }

    public func verificationApplicationPlan(
        for result: RomaAPIKeyVerificationResult,
        resolvedRuntimeKey: String
    ) -> RomaAIEnhancementAPIKeyVerificationApplicationPlan {
        guard provider.requiresUserAPIKey else {
            return RomaAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: nil
            )
        }

        guard result.isValid else {
            return RomaAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: false,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: result.errorMessage
            )
        }

        return RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: resolvedRuntimeKey,
            keyToSave: keyToSaveAfterSuccessfulVerification,
            providerKeyStorageNameToSave: provider.userAPIKeyStorageName,
            errorMessage: nil
        )
    }
}

public struct RomaAIEnhancementAPIKeyVerificationRequestPlan: Equatable, Sendable {
    private let resolvedKeyToVerify: String?
    private let immediateResult: RomaAPIKeyVerificationResult?

    public init(
        resolvedKeyToVerify: String?,
        immediateResult: RomaAPIKeyVerificationResult?
    ) {
        self.resolvedKeyToVerify = resolvedKeyToVerify
        self.immediateResult = immediateResult
    }

    public func applyRuntimeState(
        completeImmediateResult: (RomaAPIKeyVerificationResult) -> Void,
        verifyResolvedKey: (String) -> Void
    ) {
        if let immediateResult {
            completeImmediateResult(immediateResult)
            return
        }

        if let resolvedKeyToVerify {
            verifyResolvedKey(resolvedKeyToVerify)
        }
    }
}

public struct RomaAIEnhancementAPIKeyVerificationApplicationPlan: Equatable, Sendable {
    private let isValid: Bool
    private let runtimeAPIKey: String?
    private let keyToSave: String?
    private let providerKeyStorageNameToSave: String?
    private let errorMessage: String?

    init(
        isValid: Bool,
        runtimeAPIKey: String?,
        keyToSave: String?,
        providerKeyStorageNameToSave: String?,
        errorMessage: String?
    ) {
        self.isValid = isValid
        self.runtimeAPIKey = runtimeAPIKey
        self.keyToSave = keyToSave
        self.providerKeyStorageNameToSave = providerKeyStorageNameToSave
        self.errorMessage = errorMessage
    }
}

struct RomaAIEnhancementAPIKeyVerificationPersistencePlan: Equatable, Sendable {
    let runtimeAPIKey: String
    let keyToSave: String?
    let providerKeyStorageNameToSave: String?

    init(
        runtimeAPIKey: String,
        keyToSave: String?,
        providerKeyStorageNameToSave: String?
    ) {
        self.runtimeAPIKey = runtimeAPIKey
        self.keyToSave = keyToSave
        self.providerKeyStorageNameToSave = providerKeyStorageNameToSave
    }
}

struct RomaAIEnhancementAPIKeyVerificationServiceStatePlan: Equatable, Sendable {
    private let apiKeyToApply: String?
    private let isAPIKeyValid: Bool
    private let shouldPostProviderKeyChanged: Bool
    private let completionResult: RomaAPIKeyVerificationResult

    init(
        apiKeyToApply: String?,
        isAPIKeyValid: Bool,
        shouldPostProviderKeyChanged: Bool,
        completionResult: RomaAPIKeyVerificationResult
    ) {
        self.apiKeyToApply = apiKeyToApply
        self.isAPIKeyValid = isAPIKeyValid
        self.shouldPostProviderKeyChanged = shouldPostProviderKeyChanged
        self.completionResult = completionResult
    }
}

extension RomaAIEnhancementAPIKeyVerificationApplicationPlan {
    var successPersistencePlan: RomaAIEnhancementAPIKeyVerificationPersistencePlan? {
        guard let runtimeAPIKey else { return nil }
        return RomaAIEnhancementAPIKeyVerificationPersistencePlan(
            runtimeAPIKey: runtimeAPIKey,
            keyToSave: keyToSave,
            providerKeyStorageNameToSave: providerKeyStorageNameToSave
        )
    }

    var serviceStateApplicationPlan: RomaAIEnhancementAPIKeyVerificationServiceStatePlan {
        let persistencePlan = successPersistencePlan
        return RomaAIEnhancementAPIKeyVerificationServiceStatePlan(
            apiKeyToApply: persistencePlan?.runtimeAPIKey,
            isAPIKeyValid: isValid,
            shouldPostProviderKeyChanged: persistencePlan != nil,
            completionResult: RomaAPIKeyVerificationResult(
                isValid: isValid,
                errorMessage: errorMessage
            )
        )
    }

    func applySuccessPersistence(
        saveKey: (String, String) -> Void
    ) {
        guard let persistencePlan = successPersistencePlan,
              let keyToSave = persistencePlan.keyToSave,
              let providerKeyStorageNameToSave = persistencePlan.providerKeyStorageNameToSave else {
            return
        }

        saveKey(keyToSave, providerKeyStorageNameToSave)
    }
}

public extension RomaAIEnhancementAPIKeyVerificationApplicationPlan {
    func applyRuntimeState(
        saveKey: (String, String) -> Void,
        setAPIKey: (String) -> Void,
        setAPIKeyValidity: (Bool) -> Void,
        postProviderKeyChanged: () -> Void,
        complete: (RomaAPIKeyVerificationResult) -> Void
    ) {
        applySuccessPersistence(saveKey: saveKey)
        serviceStateApplicationPlan.apply(
            setAPIKey: setAPIKey,
            setAPIKeyValidity: setAPIKeyValidity,
            postProviderKeyChanged: postProviderKeyChanged,
            complete: complete
        )
    }
}

extension RomaAIEnhancementAPIKeyVerificationServiceStatePlan {
    func apply(
        setAPIKey: (String) -> Void,
        setAPIKeyValidity: (Bool) -> Void,
        postProviderKeyChanged: () -> Void,
        complete: (RomaAPIKeyVerificationResult) -> Void
    ) {
        if let apiKeyToApply {
            setAPIKey(apiKeyToApply)
        }
        setAPIKeyValidity(isAPIKeyValid)
        if shouldPostProviderKeyChanged {
            postProviderKeyChanged()
        }
        complete(completionResult)
    }
}

fileprivate enum RomaAIEnhancementAPIKeyVerificationDispatch: Equatable, Sendable {
    case immediate(RomaAPIKeyVerificationResult)
    case sharedProvider(RomaProviderKind)
    case anthropicMessages
    case openAICompatibleModels(requestURL: URL, model: String)
    case openRouterModels(model: String)
}

public struct RomaAIEnhancementAPIKeyVerificationDispatchPlan: Equatable, Sendable {
    private let provider: RomaAIEnhancementProviderKind
    private let action: RomaAIEnhancementAPIKeyVerificationDispatch

    private init(
        provider: RomaAIEnhancementProviderKind,
        action: RomaAIEnhancementAPIKeyVerificationDispatch
    ) {
        self.provider = provider
        self.action = action
    }

    public static func plan(
        provider: RomaAIEnhancementProviderKind,
        currentModel: String,
        requestURL: URL?
    ) -> RomaAIEnhancementAPIKeyVerificationDispatchPlan {
        switch provider {
        case .ollama, .localCLI:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .immediate(RomaAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: provider.unsupportedAPIKeyVerificationMessage
                ))
            )
        case .assemblyAI:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.assemblyAI)
            )
        case .deepgram:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.deepgram)
            )
        case .elevenLabs:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.elevenLabs)
            )
        case .gemini:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.gemini)
            )
        case .mistral:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.mistral)
            )
        case .soniox:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.soniox)
            )
        case .speechmatics:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.speechmatics)
            )
        case .anthropic:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .anthropicMessages
            )
        case .cerebras, .custom, .groq, .openAI:
            guard let requestURL else {
                return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                    provider: provider,
                    action: .immediate(RomaAPIKeyVerificationResult(
                        isValid: false,
                        errorMessage: RomaAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
                    ))
                )
            }

            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .openAICompatibleModels(requestURL: requestURL, model: currentModel)
            )
        case .openRouter:
            return RomaAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .openRouterModels(model: currentModel)
            )
        }
    }
}

public extension RomaAIEnhancementAPIKeyVerificationDispatchPlan {
    func verifyResolvedAPIKey(
        _ resolvedKey: String,
        verifySharedProvider: (String, RomaProviderKind) async -> RomaAPIKeyVerificationResult,
        verifyAnthropicMessages: (String) async -> RomaAPIKeyVerificationResult,
        verifyOpenAICompatibleModels: (URL, String, String) async -> RomaAPIKeyVerificationResult,
        verifyOpenRouterModels: (String, String) async -> RomaAPIKeyVerificationResult
    ) async -> RomaAPIKeyVerificationResult {
        switch action {
        case .immediate(let immediateResult):
            return immediateResult
        case .sharedProvider(let provider):
            return await verifySharedProvider(resolvedKey, provider)
        case .anthropicMessages:
            return await verifyAnthropicMessages(resolvedKey)
        case .openAICompatibleModels(let requestURL, let model):
            return await verifyOpenAICompatibleModels(requestURL, resolvedKey, model)
        case .openRouterModels(let model):
            return await verifyOpenRouterModels(resolvedKey, model)
        }
    }
}

public struct RomaAIEnhancementAPIKeyClearPlan: Equatable, Sendable {
    private let provider: RomaAIEnhancementProviderKind
    private let providerKeyStorageNameToDelete: String
    private let credentialStateAfterClear: RomaAIEnhancementCredentialState

    init(
        provider: RomaAIEnhancementProviderKind,
        providerKeyStorageNameToDelete: String,
        credentialStateAfterClear: RomaAIEnhancementCredentialState
    ) {
        self.provider = provider
        self.providerKeyStorageNameToDelete = providerKeyStorageNameToDelete
        self.credentialStateAfterClear = credentialStateAfterClear
    }

    public static func clearing(
        provider: RomaAIEnhancementProviderKind
    ) -> RomaAIEnhancementAPIKeyClearPlan? {
        guard let providerKeyStorageNameToDelete = provider.userAPIKeyStorageName else { return nil }

        return RomaAIEnhancementAPIKeyClearPlan(
            provider: provider,
            providerKeyStorageNameToDelete: providerKeyStorageNameToDelete,
            credentialStateAfterClear: RomaAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )
    }
}

struct RomaAIEnhancementAPIKeyClearPersistencePlan: Equatable, Sendable {
    let providerKeyStorageNameToDelete: String

    init(providerKeyStorageNameToDelete: String) {
        self.providerKeyStorageNameToDelete = providerKeyStorageNameToDelete
    }
}

struct RomaAIEnhancementAPIKeyClearServiceStatePlan: Equatable, Sendable {
    private let credentialStateAfterClear: RomaAIEnhancementCredentialState
    private let shouldPostProviderKeyChanged: Bool

    init(
        credentialStateAfterClear: RomaAIEnhancementCredentialState,
        shouldPostProviderKeyChanged: Bool
    ) {
        self.credentialStateAfterClear = credentialStateAfterClear
        self.shouldPostProviderKeyChanged = shouldPostProviderKeyChanged
    }
}

extension RomaAIEnhancementAPIKeyClearPlan {
    var persistencePlan: RomaAIEnhancementAPIKeyClearPersistencePlan {
        RomaAIEnhancementAPIKeyClearPersistencePlan(
            providerKeyStorageNameToDelete: providerKeyStorageNameToDelete
        )
    }

    var serviceStateApplicationPlan: RomaAIEnhancementAPIKeyClearServiceStatePlan {
        RomaAIEnhancementAPIKeyClearServiceStatePlan(
            credentialStateAfterClear: credentialStateAfterClear,
            shouldPostProviderKeyChanged: true
        )
    }

    func applyClearPersistence(
        deleteKey: (String) -> Void
    ) {
        deleteKey(persistencePlan.providerKeyStorageNameToDelete)
    }
}

public extension RomaAIEnhancementAPIKeyClearPlan {
    func applyRuntimeState(
        deleteKey: (String) -> Void,
        setCredentialState: (RomaAIEnhancementCredentialState) -> Void,
        postProviderKeyChanged: () -> Void
    ) {
        applyClearPersistence(deleteKey: deleteKey)
        serviceStateApplicationPlan.apply(
            setCredentialState: setCredentialState,
            postProviderKeyChanged: postProviderKeyChanged
        )
    }
}

extension RomaAIEnhancementAPIKeyClearServiceStatePlan {
    func apply(
        setCredentialState: (RomaAIEnhancementCredentialState) -> Void,
        postProviderKeyChanged: () -> Void
    ) {
        setCredentialState(credentialStateAfterClear)
        if shouldPostProviderKeyChanged {
            postProviderKeyChanged()
        }
    }
}

public struct RomaAIEnhancementAPIKeyFormState: Equatable, Sendable {
    public var enteredKey: String
    public var verificationProgress: RomaProviderAPIKeyVerificationProgress

    public init(
        enteredKey: String = "",
        verificationProgress: RomaProviderAPIKeyVerificationProgress = .idle
    ) {
        self.enteredKey = enteredKey
        self.verificationProgress = verificationProgress
    }

    public var isVerifying: Bool {
        verificationProgress.isVerifying
    }

    public func draft(
        for provider: RomaAIEnhancementProviderKind,
        storedRuntimeKey: String? = nil
    ) -> RomaAIEnhancementAPIKeyDraft {
        RomaAIEnhancementAPIKeyDraft(
            provider: provider,
            enteredKey: enteredKey,
            storedRuntimeKey: storedRuntimeKey
        )
    }

    public func verifying() -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: .verifying
        )
    }

    public func completedVerification() -> Self {
        Self()
    }

    public func verificationFailureAlertMessage(for result: RomaAPIKeyVerificationResult) -> String? {
        RomaProviderAPIKeyVerificationProgress.failure(message: result.errorMessage)
            .macOSInlineFeedback?
            .text
    }
}

public struct RomaAIEnhancementCredentialState: Equatable, Sendable {
    public let apiKey: String
    public let isAPIKeyValid: Bool

    public init(apiKey: String, isAPIKeyValid: Bool) {
        self.apiKey = apiKey
        self.isAPIKeyValid = isAPIKeyValid
    }
}

public struct RomaAIEnhancementCredentialStateResolutionPlan: Equatable, Sendable {
    public let provider: RomaAIEnhancementProviderKind
    private let providerKeyStorageNameToLoad: String?

    public init(
        provider: RomaAIEnhancementProviderKind,
        providerKeyStorageNameToLoad: String?
    ) {
        self.provider = provider
        self.providerKeyStorageNameToLoad = providerKeyStorageNameToLoad
    }

    public static func resolving(
        provider: RomaAIEnhancementProviderKind
    ) -> RomaAIEnhancementCredentialStateResolutionPlan {
        RomaAIEnhancementCredentialStateResolutionPlan(
            provider: provider,
            providerKeyStorageNameToLoad: provider.userAPIKeyStorageName
        )
    }

    public func credentialState(
        savedAPIKey: String?,
        isLocalCLIConfigured: Bool
    ) -> RomaAIEnhancementCredentialState {
        provider.textEnhancementCredentialState(
            savedAPIKey: savedAPIKey,
            isLocalCLIConfigured: isLocalCLIConfigured
        )
    }

    public func applyRuntimeState(
        loadSavedAPIKey: (String) -> String?,
        isLocalCLIConfigured: Bool,
        setCredentialState: (RomaAIEnhancementCredentialState) -> Void
    ) {
        let savedAPIKey = providerKeyStorageNameToLoad.flatMap(loadSavedAPIKey)
        setCredentialState(credentialState(
            savedAPIKey: savedAPIKey,
            isLocalCLIConfigured: isLocalCLIConfigured
        ))
    }
}

public enum RomaAIEnhancementProviderKind: String, CaseIterable, Sendable {
    public static let missingVerificationCandidateMessage = "Environment variable is missing or empty"
    public static let invalidOrMissingBaseURLConfigurationMessage = "Invalid or missing base URL configuration"
    public static let defaultOllamaTextEnhancementModel = "mistral"
    public static let legacyOllamaServiceSelectedModelFallback = "llama2"
    public static let ollamaTextEnhancementRequestTemperature: Double = 0.3
    public static let localCLITextEnhancementModel = "local-cli"

    case cerebras = "Cerebras"
    case groq = "Groq"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case soniox = "Soniox"
    case speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI"
    case ollama = "Ollama"
    case localCLI = "Local CLI"
    case custom = "Custom"

    public init?(storedValue: String) {
        guard let provider = Self.provider(forStoredValue: storedValue) else {
            return nil
        }
        self = provider
    }

    private static func provider(forStoredValue value: String) -> Self? {
        allCases.first { provider in
            provider.rawValue == value || provider.legacyStoredValues.contains(value)
        }
    }

    private var legacyStoredValues: [String] {
        switch self {
        case .groq:
            return ["GROQ"]
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .localCLI, .mistral, .ollama, .openAI, .openRouter, .soniox, .speechmatics:
            return []
        }
    }

    public var aiModelProvider: RomaAIModelProvider? {
        switch self {
        case .anthropic:
            return .anthropic
        case .assemblyAI:
            return .assemblyAI
        case .cerebras:
            return .cerebras
        case .deepgram:
            return .deepgram
        case .elevenLabs:
            return .elevenLabs
        case .groq:
            return .groq
        case .gemini:
            return .gemini
        case .mistral:
            return .mistral
        case .openAI:
            return .openAI
        case .openRouter:
            return .openRouter
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .ollama, .localCLI, .custom:
            return nil
        }
    }

    public var requiresUserAPIKey: Bool {
        switch self {
        case .ollama, .localCLI:
            return false
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .groq, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            return true
        }
    }

    public var userAPIKeyStorageName: String? {
        requiresUserAPIKey ? rawValue : nil
    }

    public func textEnhancementCredentialState(
        savedAPIKey: String?,
        isLocalCLIConfigured: Bool
    ) -> RomaAIEnhancementCredentialState {
        guard requiresUserAPIKey else {
            return RomaAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: self == .localCLI ? isLocalCLIConfigured : true
            )
        }

        guard let savedAPIKey else {
            return RomaAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        }

        return RomaAIEnhancementCredentialState(apiKey: savedAPIKey, isAPIKeyValid: true)
    }

    public var isSelectableForTextEnhancement: Bool {
        switch self {
        case .assemblyAI, .deepgram, .elevenLabs, .soniox, .speechmatics:
            return false
        case .anthropic, .cerebras, .custom, .gemini, .groq, .localCLI, .mistral, .ollama, .openAI, .openRouter:
            return true
        }
    }

    public static var selectableTextEnhancementProviders: [Self] {
        allCases.filter(\.isSelectableForTextEnhancement)
    }

    public static var textEnhancementProviderKeyStorageNamesToCheck: [String] {
        selectableTextEnhancementProviders.compactMap(\.userAPIKeyStorageName)
    }

    public static func connectedTextEnhancementProviders(
        providerKeyStorageNamesWithKeys: Set<String>,
        isOllamaConnected: Bool,
        isLocalCLIConfigured: Bool
    ) -> [Self] {
        selectableTextEnhancementProviders.filter { provider in
            provider.isConnectedForTextEnhancement(
                providerKeyStorageNamesWithKeys: providerKeyStorageNamesWithKeys,
                isOllamaConnected: isOllamaConnected,
                isLocalCLIConfigured: isLocalCLIConfigured
            )
        }
    }

    public func isConnectedForTextEnhancement(
        providerKeyStorageNamesWithKeys: Set<String>,
        isOllamaConnected: Bool,
        isLocalCLIConfigured: Bool
    ) -> Bool {
        switch self {
        case .ollama:
            return isOllamaConnected
        case .localCLI:
            return isLocalCLIConfigured
        case .anthropic, .cerebras, .custom, .gemini, .groq, .mistral, .openAI, .openRouter:
            guard let storageName = userAPIKeyStorageName else { return false }
            return providerKeyStorageNamesWithKeys.contains(storageName)
        case .assemblyAI, .deepgram, .elevenLabs, .soniox, .speechmatics:
            return false
        }
    }

    public var preservesUnavailableSelectedTextEnhancementModel: Bool {
        self == .ollama
    }

    public func defaultTextEnhancementModel(from defaults: UserDefaults = .standard) -> String {
        if let provider = aiModelProvider {
            return RomaAIModelCatalog.defaultModel(for: provider)
        }

        switch self {
        case .ollama:
            return RomaDynamicAIProviderPreference.ollamaSelectedModel(
                from: defaults,
                fallback: Self.defaultOllamaTextEnhancementModel
            )
        case .localCLI:
            return Self.localCLITextEnhancementModel
        case .custom:
            return RomaDynamicAIProviderPreference.customProviderModel(from: defaults)
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from RomaAIModelCatalog")
        }
    }

    public var staticTextEnhancementModels: [String] {
        if let provider = aiModelProvider {
            return RomaAIModelCatalog.availableModels(for: provider)
        }

        switch self {
        case .ollama, .localCLI, .custom:
            return []
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from RomaAIModelCatalog")
        }
    }

    public func textEnhancementAvailableModels(
        ollamaModels: [String],
        openRouterModels: [String]
    ) -> [String] {
        switch self {
        case .ollama:
            return ollamaModels
        case .openRouter:
            return openRouterModels
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .soniox, .speechmatics:
            return staticTextEnhancementModels
        case .localCLI, .custom:
            return []
        }
    }

    public func textEnhancementRequestURLString(from defaults: UserDefaults = .standard) -> String {
        if let corePostProcessingURL = aiModelProvider?.postProcessingRequestURL {
            return corePostProcessingURL.absoluteString
        }

        switch self {
        case .ollama:
            return RomaDynamicAIProviderPreference.ollamaBaseURL(from: defaults)
        case .localCLI:
            return ""
        case .custom:
            return RomaDynamicAIProviderPreference.customProviderBaseURL(from: defaults)
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from RomaAIModelProvider.postProcessingRequestURL")
        }
    }

    public func textEnhancementRequestURL(from defaults: UserDefaults = .standard) -> URL? {
        URL(string: textEnhancementRequestURLString(from: defaults))
    }

    public func selectedTextEnhancementModel(
        _ selectedModel: String?,
        availableModels: [String],
        defaultModel: String
    ) -> String {
        guard let selectedModel,
              !selectedModel.isEmpty else {
            return defaultModel
        }

        if preservesUnavailableSelectedTextEnhancementModel || availableModels.contains(selectedModel) {
            return selectedModel
        }

        return defaultModel
    }

    public func textEnhancementModelToSelectAfterRefresh(
        currentModel: String,
        refreshedModels: [String],
        defaultModel: String
    ) -> String? {
        guard let firstRefreshedModel = refreshedModels.first else {
            return nil
        }

        switch self {
        case .ollama:
            return refreshedModels.contains(currentModel) ? nil : firstRefreshedModel
        case .openRouter:
            return currentModel == defaultModel ? firstRefreshedModel : nil
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .groq, .gemini, .localCLI, .mistral, .openAI, .soniox, .speechmatics:
            return nil
        }
    }

    public var unsupportedAPIKeyVerificationMessage: String {
        "\(rawValue) does not support API key verification."
    }

    public var invalidTextEnhancementRequestURLMessage: String {
        "\(rawValue) has an invalid API endpoint URL. Please update it in AI settings."
    }

    public var apiKeyConsoleURL: URL? {
        aiModelProvider?.apiKeyConsoleURL
    }
}

public extension RomaAIModelProvider {
    var postProcessingRequestURL: URL? {
        switch self {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .assemblyAI:
            return RomaProviderEndpoint.assemblyAITranscriptsURL(from: RomaProviderEndpoint.assemblyAIAPIBaseURL)
        case .cerebras:
            return RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: RomaProviderEndpoint.cerebras.apiBaseURL)
        case .deepgram:
            return nil
        case .elevenLabs:
            return RomaProviderEndpoint.elevenLabsSpeechToTextURL(from: RomaProviderEndpoint.elevenLabsAPIBaseURL)
        case .gemini:
            return RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: RomaProviderEndpoint.gemini.apiBaseURL)
        case .groq:
            return RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: RomaProviderEndpoint.groq.apiBaseURL)
        case .mistral:
            return RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: RomaProviderEndpoint.mistralAPIBaseURL)
        case .openAI:
            return RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: RomaProviderEndpoint.openAI.apiBaseURL)
        case .openRouter:
            return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .soniox:
            return RomaProviderEndpoint.sonioxAPIBaseURL
        case .speechmatics:
            return RomaProviderEndpoint.speechmaticsAPIBaseURL
        }
    }

    var apiKeyConsoleURL: URL {
        switch self {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")!
        case .assemblyAI:
            return URL(string: "https://www.assemblyai.com/dashboard/api-keys")!
        case .cerebras:
            return RomaProviderEndpoint.cerebras.consoleURL
        case .deepgram:
            return RomaProviderEndpoint.deepgram.consoleURL
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/speech-synthesis")!
        case .gemini:
            return RomaProviderEndpoint.gemini.consoleURL
        case .groq:
            return RomaProviderEndpoint.groq.consoleURL
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys")!
        case .openAI:
            return RomaProviderEndpoint.openAI.consoleURL
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")!
        case .soniox:
            return URL(string: "https://console.soniox.com/")!
        case .speechmatics:
            return URL(string: "https://portal.speechmatics.com/manage-access/")!
        }
    }
}
