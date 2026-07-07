import Foundation

public enum VoiceInkLocalCLIExecutionError: Error, LocalizedError, Equatable, Sendable {
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

public enum VoiceInkAIEnhancementError: Error, Equatable, Sendable {
    case notConfigured
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)

    public static func transportFailure(
        _ failure: VoiceInkAIEnhancementTransportFailure
    ) -> VoiceInkAIEnhancementError {
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

    public static func httpError(statusCode: Int, message: String) -> VoiceInkAIEnhancementError {
        if statusCode == 429 {
            return .rateLimitExceeded
        }
        if (500...599).contains(statusCode) {
            return .serverError
        }
        return .customError("HTTP \(statusCode): \(message)")
    }

    public static func transportNetworkError(for error: Error) -> VoiceInkAIEnhancementError? {
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

    public static func localCLIExecutionFailure(_ error: Error) -> VoiceInkAIEnhancementError {
        if let localCLIError = error as? VoiceInkLocalCLIExecutionError {
            return .customError(localCLIError.errorDescription ?? "An unknown Local CLI error occurred.")
        }

        return .customError(error.localizedDescription)
    }
}

public enum VoiceInkAIEnhancementTransportFailure: Equatable, Sendable {
    case missingAPIKey
    case httpStatus(statusCode: Int, message: String)
    case noResultReturned
    case network
    case timeout
    case invalidRequest(description: String?)
}

public enum VoiceInkOllamaEnhancementFailure: Error, Equatable, Sendable {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    case timeout

    public static func transportFailure(
        _ failure: VoiceInkOllamaTransportFailure
    ) -> VoiceInkOllamaEnhancementFailure {
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

    public static func httpFailure(statusCode: Int) -> VoiceInkOllamaEnhancementFailure {
        if statusCode == 404 {
            return .modelNotFound
        }
        if statusCode == 500 {
            return .serverError
        }
        return .invalidResponse
    }

    public var enhancementError: VoiceInkAIEnhancementError {
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

public enum VoiceInkOllamaTransportFailure: Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case network
    case invalidResponse
    case invalidRequest
    case missingCredential
    case timeout
}

public enum VoiceInkOllamaServiceDiagnostics {
    public static let invalidBaseURLMessage = "Invalid Ollama base URL"

    public static func modelFetchFailedMessage(errorDescription: String) -> String {
        "Error fetching models: \(errorDescription)"
    }
}

extension VoiceInkOllamaEnhancementFailure: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

extension VoiceInkAIEnhancementError: LocalizedError {
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

public enum VoiceInkAIEnhancementRetryDecision: Equatable, Sendable {
    case retryAfterDelay(TimeInterval)
    case retryImmediately
    case fail(VoiceInkAIEnhancementError)
}

public struct VoiceInkAIEnhancementRetryState: Equatable, Sendable {
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

    public mutating func recordFailure(_ error: VoiceInkAIEnhancementError) -> VoiceInkAIEnhancementRetryDecision {
        switch error {
        case .networkError, .serverError, .rateLimitExceeded:
            return recordBackoffFailure(error)
        case .timeout where retryOnTimeout:
            return recordImmediateFailure(error)
        case .timeout, .notConfigured, .enhancementFailed, .customError:
            return .fail(error)
        }
    }

    public mutating func recordTransportNetworkFailure() -> VoiceInkAIEnhancementRetryDecision {
        recordBackoffFailure(.networkError)
    }

    public mutating func recordNonEnhancementError(_ error: Error) -> VoiceInkAIEnhancementNonEnhancementErrorRetryPlan? {
        guard VoiceInkAIEnhancementError.transportNetworkError(for: error) == .networkError else {
            return nil
        }

        return VoiceInkAIEnhancementNonEnhancementErrorRetryPlan(
            decision: recordTransportNetworkFailure(),
            isTransportNetworkFailure: true
        )
    }

    private mutating func recordBackoffFailure(_ error: VoiceInkAIEnhancementError) -> VoiceInkAIEnhancementRetryDecision {
        failedAttempts += 1
        guard failedAttempts < maxAttempts else {
            return .fail(error)
        }

        let delay = nextDelay
        nextDelay *= 2
        return .retryAfterDelay(delay)
    }

    private mutating func recordImmediateFailure(_ error: VoiceInkAIEnhancementError) -> VoiceInkAIEnhancementRetryDecision {
        failedAttempts += 1
        guard failedAttempts < maxAttempts else {
            return .fail(error)
        }

        return .retryImmediately
    }
}

public struct VoiceInkAIEnhancementNonEnhancementErrorRetryPlan: Equatable, Sendable {
    private let decision: VoiceInkAIEnhancementRetryDecision
    private let isTransportNetworkFailure: Bool

    init(decision: VoiceInkAIEnhancementRetryDecision, isTransportNetworkFailure: Bool) {
        self.decision = decision
        self.isTransportNetworkFailure = isTransportNetworkFailure
    }

    public func applyRuntimeState(
        handleRetryDecision: (VoiceInkAIEnhancementRetryDecision, Bool) async throws -> Void
    ) async throws {
        try await handleRetryDecision(decision, isTransportNetworkFailure)
    }
}

public struct VoiceInkAIEnhancementRateLimitPolicy: Equatable, Sendable {
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

public enum VoiceInkAIEnhancementRetryProgressPresentation {
    public static func diagnosticMessage(
        for decision: VoiceInkAIEnhancementRetryDecision,
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

public enum VoiceInkAIEnhancementRetryFailurePresentation {
    public static func diagnosticMessage(
        for error: VoiceInkAIEnhancementError,
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

public enum VoiceInkAIEnhancementOutputFilter {
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

public struct VoiceInkAIEnhancementRequestPayload: Equatable, Sendable {
    public let userMessage: String

    public init?(transcript: String) {
        guard !transcript.isEmpty else {
            return nil
        }

        self.userMessage = VoiceInkAIRequestPrompts.taggedTranscript(transcript)
    }

    public static func enhancedText(from providerOutput: String) -> String {
        VoiceInkAIEnhancementOutputFilter.filter(providerOutput)
    }
}

public enum VoiceInkAIEnhancementRequestPreparation: Equatable, Sendable {
    case skipEmptyTranscript
    case execute(VoiceInkAIEnhancementRequestPayload)

    public static func preparing(
        transcript: String,
        isConfigured: Bool
    ) throws -> VoiceInkAIEnhancementRequestPreparation {
        guard isConfigured else {
            throw VoiceInkAIEnhancementError.notConfigured
        }

        guard let requestPayload = VoiceInkAIEnhancementRequestPayload(transcript: transcript) else {
            return .skipEmptyTranscript
        }

        return .execute(requestPayload)
    }
}

public struct VoiceInkAIEnhancementPromptContext: Equatable, Sendable {
    public let selectedText: String?
    public let clipboardText: String?
    public let currentWindowText: String?
    public let customVocabulary: String

    public init(
        selectedText: String? = nil,
        clipboardText: String? = nil,
        currentWindowText: String? = nil,
        customVocabulary: String = ""
    ) {
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.currentWindowText = currentWindowText
        self.customVocabulary = customVocabulary
    }
}

public enum VoiceInkSelectedTextDiagnostics {
    public static func fetchFailedMessage(errorDescription: String) -> String {
        "Failed to get selected text: \(errorDescription)"
    }
}

public enum VoiceInkAIEnhancementPromptBuilder {
    public static func systemMessage(
        basePrompt: String,
        context: VoiceInkAIEnhancementPromptContext = VoiceInkAIEnhancementPromptContext()
    ) -> String {
        basePrompt
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

public enum VoiceInkAIEnhancementVocabularyContext {
    public static func formatted(from terms: [String]) -> String {
        let normalizedTerms = VoiceInkCustomVocabularyTerms.normalized(terms, for: .postProcessingContext)
        guard !normalizedTerms.isEmpty else {
            return ""
        }

        return "Important Vocabulary: \(normalizedTerms.joined(separator: ", "))"
    }
}

public struct VoiceInkScreenCaptureWindowFacts: Equatable, Sendable {
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

public enum VoiceInkAIEnhancementScreenContext {
    public static let unknownWindowValue = "Unknown"
    public static let noTextDetectedMessage = "No text detected via OCR"

    public static func preferredWindowIndex(
        in windows: [VoiceInkScreenCaptureWindowFacts],
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
        window: VoiceInkScreenCaptureWindowFacts,
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
        _ window: VoiceInkScreenCaptureWindowFacts,
        currentProcessID: Int
    ) -> Bool {
        window.processID != currentProcessID
            && window.layer == 0
            && window.isOnScreen
    }
}

public enum VoiceInkAIEnhancementProviderKeyChangeRequest {
    public static let notificationName = Notification.Name("aiProviderKeyChanged")
}

public enum VoiceInkAIModelProvider: String, CaseIterable, Sendable {
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

public enum VoiceInkAIModelCatalog {
    public static func defaultModel(for provider: VoiceInkAIModelProvider) -> String {
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

    public static func firstAvailableModel(for provider: VoiceInkAIModelProvider) -> String {
        availableModels(for: provider).first ?? defaultModel(for: provider)
    }

    public static func availableModels(for provider: VoiceInkAIModelProvider) -> [String] {
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

public struct VoiceInkAIChatRequestParameters {
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

public enum VoiceInkAIReasoningConfig {
    public static func temperature(forModelName modelName: String, defaultTemperature: Double = 0.3) -> Double {
        modelName.lowercased().hasPrefix("gpt-5") ? 1.0 : defaultTemperature
    }

    public static func chatRequestParameters(
        for provider: VoiceInkAIModelProvider?,
        modelName: String,
        defaultTemperature: Double = 0.3
    ) -> VoiceInkAIChatRequestParameters {
        VoiceInkAIChatRequestParameters(
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
        for provider: VoiceInkAIModelProvider,
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
        for provider: VoiceInkAIModelProvider,
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

private enum VoiceInkAIEnhancementRequestExecutionAction: Sendable, Equatable {
    case ollama
    case localCLI
    case anthropicMessages
    case openAICompatibleChatCompletions
}

struct VoiceInkAIEnhancementOpenAICompatibleRequestPlan {
    let requestURL: URL
    let requestParameters: VoiceInkAIChatRequestParameters

    func applyRuntimeState<Result>(
        modelName: String,
        execute: (String, URL, VoiceInkAIChatRequestParameters) async throws -> Result
    ) async throws -> Result {
        try await execute(modelName, requestURL, requestParameters)
    }
}

public struct VoiceInkAIEnhancementRequestExecutionPlan {
    private let action: VoiceInkAIEnhancementRequestExecutionAction
    private let modelName: String
    private let openAICompatibleRequest: VoiceInkAIEnhancementOpenAICompatibleRequestPlan?
    private let requestPreparationError: VoiceInkAIEnhancementError?

    public static func planning(
        provider: VoiceInkAIEnhancementProviderKind,
        modelName: String,
        defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementRequestExecutionPlan {
        let action: VoiceInkAIEnhancementRequestExecutionAction
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
            return VoiceInkAIEnhancementRequestExecutionPlan(
                action: action,
                modelName: modelName,
                openAICompatibleRequest: nil,
                requestPreparationError: nil
            )
        }

        guard let requestURL = provider.textEnhancementRequestURL(from: defaults) else {
            return VoiceInkAIEnhancementRequestExecutionPlan(
                action: action,
                modelName: modelName,
                openAICompatibleRequest: nil,
                requestPreparationError: .customError(provider.invalidTextEnhancementRequestURLMessage)
            )
        }

        return VoiceInkAIEnhancementRequestExecutionPlan(
            action: action,
            modelName: modelName,
            openAICompatibleRequest: VoiceInkAIEnhancementOpenAICompatibleRequestPlan(
                requestURL: requestURL,
                requestParameters: VoiceInkAIReasoningConfig.chatRequestParameters(
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
        openAICompatibleChatCompletions: (String, URL, VoiceInkAIChatRequestParameters) async throws -> Result
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

    private func openAICompatibleRequestOrThrow() throws -> VoiceInkAIEnhancementOpenAICompatibleRequestPlan {
        if let openAICompatibleRequest {
            return openAICompatibleRequest
        }

        if let requestPreparationError {
            throw requestPreparationError
        }

        preconditionFailure("OpenAI-compatible request plan is only available for OpenAI-compatible routes.")
    }
}

public struct VoiceInkAIEnhancementProviderSelectionPlan: Sendable, Equatable {
    let selectedProviderToSave: VoiceInkAIEnhancementProviderKind
    private let shouldRefreshOllamaRuntimeModels: Bool

    init(
        selectedProviderToSave: VoiceInkAIEnhancementProviderKind,
        shouldRefreshOllamaRuntimeModels: Bool
    ) {
        self.selectedProviderToSave = selectedProviderToSave
        self.shouldRefreshOllamaRuntimeModels = shouldRefreshOllamaRuntimeModels
    }

    public static func selecting(
        _ provider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementProviderSelectionPlan {
        VoiceInkAIEnhancementProviderSelectionPlan(
            selectedProviderToSave: provider,
            shouldRefreshOllamaRuntimeModels: provider == .ollama
        )
    }
}

public extension VoiceInkAIEnhancementProviderSelectionPlan {
    func applyRuntimeState(
        applyPersistence: (VoiceInkAIEnhancementProviderSelectionPlan) -> Void,
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

public struct VoiceInkAIEnhancementModelRefreshPlan: Sendable, Equatable {
    let refreshedModelNames: [String]
    let selectedModelToSave: String?

    init(refreshedModelNames: [String], selectedModelToSave: String?) {
        self.refreshedModelNames = refreshedModelNames
        self.selectedModelToSave = selectedModelToSave
    }

    public static func refreshed(
        provider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        refreshedModels: [String],
        defaultModel: String
    ) -> VoiceInkAIEnhancementModelRefreshPlan {
        VoiceInkAIEnhancementModelRefreshPlan(
            refreshedModelNames: refreshedModels,
            selectedModelToSave: provider.textEnhancementModelToSelectAfterRefresh(
                currentModel: currentModel,
                refreshedModels: refreshedModels,
                defaultModel: defaultModel
            )
        )
    }

    public static let failed = VoiceInkAIEnhancementModelRefreshPlan(
        refreshedModelNames: [],
        selectedModelToSave: nil
    )
}

public extension VoiceInkAIEnhancementModelRefreshPlan {
    func applyOpenRouterRuntimeState(
        setOpenRouterModels: ([String]) -> Void,
        applyPersistence: (VoiceInkAIEnhancementModelRefreshPlan) -> String?,
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

public struct VoiceInkAIEnhancementModelSelectionPlan: Sendable, Equatable {
    let selectedModels: [VoiceInkAIEnhancementProviderKind: String]
    let provider: VoiceInkAIEnhancementProviderKind
    let selectedModelToSave: String
    let ollamaModelToApply: String?

    init(
        selectedModels: [VoiceInkAIEnhancementProviderKind: String],
        provider: VoiceInkAIEnhancementProviderKind,
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
        provider: VoiceInkAIEnhancementProviderKind,
        selectedModels: [VoiceInkAIEnhancementProviderKind: String]
    ) -> VoiceInkAIEnhancementModelSelectionPlan? {
        guard !model.isEmpty else { return nil }

        var updatedSelectedModels = selectedModels
        updatedSelectedModels[provider] = model

        return VoiceInkAIEnhancementModelSelectionPlan(
            selectedModels: updatedSelectedModels,
            provider: provider,
            selectedModelToSave: model,
            ollamaModelToApply: provider == .ollama ? model : nil
        )
    }
}

public extension VoiceInkAIEnhancementModelSelectionPlan {
    func applyRuntimeState(
        setSelectedModels: ([VoiceInkAIEnhancementProviderKind: String]) -> Void,
        applyPersistence: (VoiceInkAIEnhancementModelSelectionPlan) -> Void,
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

public enum VoiceInkAIEnhancementConnectionStatusTone: Sendable, Equatable {
    case connected
    case disconnected
}

public enum VoiceInkAIEnhancementConnectionStatusPresentation: Sendable, Equatable {
    case checking
    case status(text: String, tone: VoiceInkAIEnhancementConnectionStatusTone)
}

public struct VoiceInkAIEnhancementModelPickerPresentation: Sendable, Equatable {
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

public struct VoiceInkAIEnhancementAPIKeyControlPresentation: Sendable, Equatable {
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

public struct VoiceInkMacOSLocalCLISettingsPresentation: Equatable, Sendable {
    public let commandTitle: String
    public let loadTemplateButtonTitle: String
    public let timeoutPickerTitle: String
    public let environmentHelpText: String
    public let configurationRequiredHelpText: String

    public static let macOS = VoiceInkMacOSLocalCLISettingsPresentation(
        commandTitle: "Command",
        loadTemplateButtonTitle: "Load Template",
        timeoutPickerTitle: "Timeout",
        environmentHelpText: "Environment variables available: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT. VoiceInk also writes VOICEINK_FULL_PROMPT to stdin for every command.",
        configurationRequiredHelpText: "Load a template or enter a command to enable Local CLI enhancement."
    )
}

public enum VoiceInkLocalCLITemplate: String, CaseIterable, Identifiable, Sendable {
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
            return "pi -ne -ns -p --no-tools --system-prompt \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\""
        case .claude:
            return "claude -p \"$VOICEINK_FULL_PROMPT\""
        case .codex:
            return "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --output-last-message \"$TMPFILE\" \"$VOICEINK_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        case .copilot:
            return "copilot -p \"$VOICEINK_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        }
    }
}

public enum VoiceInkLocalCLIPreference {
    public static let commandTemplateKey = "localCLICommandTemplate"
    public static let selectedTemplateKey = "localCLISelectedTemplate"
    public static let timeoutSecondsKey = "localCLITimeoutSeconds"
    public static let macOSSettingsPresentation = VoiceInkMacOSLocalCLISettingsPresentation.macOS
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

    public static func selectedTemplate(from defaults: UserDefaults = .standard) -> VoiceInkLocalCLITemplate {
        guard let rawValue = defaults.string(forKey: selectedTemplateKey),
              let template = VoiceInkLocalCLITemplate(rawValue: rawValue)
        else {
            return .pi
        }

        return template
    }

    public static func saveSelectedTemplate(
        _ template: VoiceInkLocalCLITemplate,
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
    ) -> VoiceInkLocalCLIExecutionError {
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

public struct VoiceInkAIEnhancementProviderSettingsPresentation: Sendable, Equatable {
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

    public static let macOS = VoiceInkAIEnhancementProviderSettingsPresentation(
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

    public func connectionStatus(
        provider: VoiceInkAIEnhancementProviderKind,
        isAPIKeyValid: Bool,
        isCheckingOllama: Bool,
        hasOllamaModels: Bool
    ) -> VoiceInkAIEnhancementConnectionStatusPresentation? {
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
        provider: VoiceInkAIEnhancementProviderKind,
        availableModels: [String]
    ) -> VoiceInkAIEnhancementModelPickerPresentation {
        switch provider {
        case .openRouter:
            return VoiceInkAIEnhancementModelPickerPresentation(
                isModelPickerVisible: !availableModels.isEmpty,
                isRefreshButtonVisible: true,
                emptyStateText: availableModels.isEmpty ? noModelsLoadedText : nil
            )
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .soniox, .speechmatics:
            return VoiceInkAIEnhancementModelPickerPresentation(
                isModelPickerVisible: !availableModels.isEmpty,
                isRefreshButtonVisible: false,
                emptyStateText: nil
            )
        case .custom, .localCLI, .ollama:
            return VoiceInkAIEnhancementModelPickerPresentation(
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
        formState: VoiceInkAIEnhancementAPIKeyFormState,
        provider: VoiceInkAIEnhancementProviderKind,
        customProviderBaseURL: String,
        customProviderModelName: String
    ) -> VoiceInkAIEnhancementAPIKeyControlPresentation {
        let draft = formState.draft(for: provider)
        return VoiceInkAIEnhancementAPIKeyControlPresentation(
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

public struct VoiceInkAIEnhancementAPIKeyDraft: Equatable, Sendable {
    private let provider: VoiceInkAIEnhancementProviderKind
    private let providerKeyDraft: VoiceInkProviderAPIKeyDraft

    public init(
        provider: VoiceInkAIEnhancementProviderKind,
        enteredKey: String?,
        storedRuntimeKey: String? = nil
    ) {
        self.provider = provider
        self.providerKeyDraft = VoiceInkProviderAPIKeyDraft(
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
        return VoiceInkAPIKeyReference.resolvedValue(candidate, environment: environment)
    }

    public func verificationRequestPlan(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VoiceInkAIEnhancementAPIKeyVerificationRequestPlan {
        guard provider.requiresUserAPIKey else {
            return VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        }

        guard let resolvedKey = resolvedVerificationCandidate(environment: environment) else {
            return VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: VoiceInkAIEnhancementProviderKind.missingVerificationCandidateMessage
                )
            )
        }

        return VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
            resolvedKeyToVerify: resolvedKey,
            immediateResult: nil
        )
    }

    public func verificationApplicationPlan(
        for result: VoiceInkAPIKeyVerificationResult,
        resolvedRuntimeKey: String
    ) -> VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan {
        guard provider.requiresUserAPIKey else {
            return VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: nil
            )
        }

        guard result.isValid else {
            return VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: false,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: result.errorMessage
            )
        }

        return VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: resolvedRuntimeKey,
            keyToSave: keyToSaveAfterSuccessfulVerification,
            providerKeyStorageNameToSave: provider.userAPIKeyStorageName,
            errorMessage: nil
        )
    }
}

public struct VoiceInkAIEnhancementAPIKeyVerificationRequestPlan: Equatable, Sendable {
    private let resolvedKeyToVerify: String?
    private let immediateResult: VoiceInkAPIKeyVerificationResult?

    public init(
        resolvedKeyToVerify: String?,
        immediateResult: VoiceInkAPIKeyVerificationResult?
    ) {
        self.resolvedKeyToVerify = resolvedKeyToVerify
        self.immediateResult = immediateResult
    }

    public func applyRuntimeState(
        completeImmediateResult: (VoiceInkAPIKeyVerificationResult) -> Void,
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

public struct VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan: Equatable, Sendable {
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

struct VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan: Equatable, Sendable {
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

struct VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan: Equatable, Sendable {
    private let apiKeyToApply: String?
    private let isAPIKeyValid: Bool
    private let shouldPostProviderKeyChanged: Bool
    private let completionResult: VoiceInkAPIKeyVerificationResult

    init(
        apiKeyToApply: String?,
        isAPIKeyValid: Bool,
        shouldPostProviderKeyChanged: Bool,
        completionResult: VoiceInkAPIKeyVerificationResult
    ) {
        self.apiKeyToApply = apiKeyToApply
        self.isAPIKeyValid = isAPIKeyValid
        self.shouldPostProviderKeyChanged = shouldPostProviderKeyChanged
        self.completionResult = completionResult
    }
}

extension VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan {
    var successPersistencePlan: VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan? {
        guard let runtimeAPIKey else { return nil }
        return VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan(
            runtimeAPIKey: runtimeAPIKey,
            keyToSave: keyToSave,
            providerKeyStorageNameToSave: providerKeyStorageNameToSave
        )
    }

    var serviceStateApplicationPlan: VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan {
        let persistencePlan = successPersistencePlan
        return VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan(
            apiKeyToApply: persistencePlan?.runtimeAPIKey,
            isAPIKeyValid: isValid,
            shouldPostProviderKeyChanged: persistencePlan != nil,
            completionResult: VoiceInkAPIKeyVerificationResult(
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

public extension VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan {
    func applyRuntimeState(
        saveKey: (String, String) -> Void,
        setAPIKey: (String) -> Void,
        setAPIKeyValidity: (Bool) -> Void,
        postProviderKeyChanged: () -> Void,
        complete: (VoiceInkAPIKeyVerificationResult) -> Void
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

extension VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan {
    func apply(
        setAPIKey: (String) -> Void,
        setAPIKeyValidity: (Bool) -> Void,
        postProviderKeyChanged: () -> Void,
        complete: (VoiceInkAPIKeyVerificationResult) -> Void
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

fileprivate enum VoiceInkAIEnhancementAPIKeyVerificationDispatch: Equatable, Sendable {
    case immediate(VoiceInkAPIKeyVerificationResult)
    case sharedProvider(VoiceInkProviderKind)
    case anthropicMessages
    case openAICompatibleModels(requestURL: URL, model: String)
    case openRouterModels(model: String)
}

public struct VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan: Equatable, Sendable {
    private let provider: VoiceInkAIEnhancementProviderKind
    private let action: VoiceInkAIEnhancementAPIKeyVerificationDispatch

    private init(
        provider: VoiceInkAIEnhancementProviderKind,
        action: VoiceInkAIEnhancementAPIKeyVerificationDispatch
    ) {
        self.provider = provider
        self.action = action
    }

    public static func plan(
        provider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        requestURL: URL?
    ) -> VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan {
        switch provider {
        case .ollama, .localCLI:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .immediate(VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: provider.unsupportedAPIKeyVerificationMessage
                ))
            )
        case .assemblyAI:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.assemblyAI)
            )
        case .deepgram:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.deepgram)
            )
        case .elevenLabs:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.elevenLabs)
            )
        case .gemini:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.gemini)
            )
        case .mistral:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.mistral)
            )
        case .soniox:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.soniox)
            )
        case .speechmatics:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(.speechmatics)
            )
        case .anthropic:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .anthropicMessages
            )
        case .cerebras, .custom, .groq, .openAI:
            guard let requestURL else {
                return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                    provider: provider,
                    action: .immediate(VoiceInkAPIKeyVerificationResult(
                        isValid: false,
                        errorMessage: VoiceInkAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
                    ))
                )
            }

            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .openAICompatibleModels(requestURL: requestURL, model: currentModel)
            )
        case .openRouter:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .openRouterModels(model: currentModel)
            )
        }
    }
}

public extension VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan {
    func verifyResolvedAPIKey(
        _ resolvedKey: String,
        verifySharedProvider: (String, VoiceInkProviderKind) async -> VoiceInkAPIKeyVerificationResult,
        verifyAnthropicMessages: (String) async -> VoiceInkAPIKeyVerificationResult,
        verifyOpenAICompatibleModels: (URL, String, String) async -> VoiceInkAPIKeyVerificationResult,
        verifyOpenRouterModels: (String, String) async -> VoiceInkAPIKeyVerificationResult
    ) async -> VoiceInkAPIKeyVerificationResult {
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

public struct VoiceInkAIEnhancementAPIKeyClearPlan: Equatable, Sendable {
    private let provider: VoiceInkAIEnhancementProviderKind
    private let providerKeyStorageNameToDelete: String
    private let credentialStateAfterClear: VoiceInkAIEnhancementCredentialState

    init(
        provider: VoiceInkAIEnhancementProviderKind,
        providerKeyStorageNameToDelete: String,
        credentialStateAfterClear: VoiceInkAIEnhancementCredentialState
    ) {
        self.provider = provider
        self.providerKeyStorageNameToDelete = providerKeyStorageNameToDelete
        self.credentialStateAfterClear = credentialStateAfterClear
    }

    public static func clearing(
        provider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementAPIKeyClearPlan? {
        guard let providerKeyStorageNameToDelete = provider.userAPIKeyStorageName else { return nil }

        return VoiceInkAIEnhancementAPIKeyClearPlan(
            provider: provider,
            providerKeyStorageNameToDelete: providerKeyStorageNameToDelete,
            credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )
    }
}

struct VoiceInkAIEnhancementAPIKeyClearPersistencePlan: Equatable, Sendable {
    let providerKeyStorageNameToDelete: String

    init(providerKeyStorageNameToDelete: String) {
        self.providerKeyStorageNameToDelete = providerKeyStorageNameToDelete
    }
}

struct VoiceInkAIEnhancementAPIKeyClearServiceStatePlan: Equatable, Sendable {
    private let credentialStateAfterClear: VoiceInkAIEnhancementCredentialState
    private let shouldPostProviderKeyChanged: Bool

    init(
        credentialStateAfterClear: VoiceInkAIEnhancementCredentialState,
        shouldPostProviderKeyChanged: Bool
    ) {
        self.credentialStateAfterClear = credentialStateAfterClear
        self.shouldPostProviderKeyChanged = shouldPostProviderKeyChanged
    }
}

extension VoiceInkAIEnhancementAPIKeyClearPlan {
    var persistencePlan: VoiceInkAIEnhancementAPIKeyClearPersistencePlan {
        VoiceInkAIEnhancementAPIKeyClearPersistencePlan(
            providerKeyStorageNameToDelete: providerKeyStorageNameToDelete
        )
    }

    var serviceStateApplicationPlan: VoiceInkAIEnhancementAPIKeyClearServiceStatePlan {
        VoiceInkAIEnhancementAPIKeyClearServiceStatePlan(
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

public extension VoiceInkAIEnhancementAPIKeyClearPlan {
    func applyRuntimeState(
        deleteKey: (String) -> Void,
        setCredentialState: (VoiceInkAIEnhancementCredentialState) -> Void,
        postProviderKeyChanged: () -> Void
    ) {
        applyClearPersistence(deleteKey: deleteKey)
        serviceStateApplicationPlan.apply(
            setCredentialState: setCredentialState,
            postProviderKeyChanged: postProviderKeyChanged
        )
    }
}

extension VoiceInkAIEnhancementAPIKeyClearServiceStatePlan {
    func apply(
        setCredentialState: (VoiceInkAIEnhancementCredentialState) -> Void,
        postProviderKeyChanged: () -> Void
    ) {
        setCredentialState(credentialStateAfterClear)
        if shouldPostProviderKeyChanged {
            postProviderKeyChanged()
        }
    }
}

public struct VoiceInkAIEnhancementAPIKeyFormState: Equatable, Sendable {
    public var enteredKey: String
    public var verificationProgress: VoiceInkProviderAPIKeyVerificationProgress

    public init(
        enteredKey: String = "",
        verificationProgress: VoiceInkProviderAPIKeyVerificationProgress = .idle
    ) {
        self.enteredKey = enteredKey
        self.verificationProgress = verificationProgress
    }

    public var isVerifying: Bool {
        verificationProgress.isVerifying
    }

    public func draft(
        for provider: VoiceInkAIEnhancementProviderKind,
        storedRuntimeKey: String? = nil
    ) -> VoiceInkAIEnhancementAPIKeyDraft {
        VoiceInkAIEnhancementAPIKeyDraft(
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

    public func verificationFailureAlertMessage(for result: VoiceInkAPIKeyVerificationResult) -> String? {
        VoiceInkProviderAPIKeyVerificationProgress.failure(message: result.errorMessage)
            .macOSInlineFeedback?
            .text
    }
}

public struct VoiceInkAIEnhancementCredentialState: Equatable, Sendable {
    public let apiKey: String
    public let isAPIKeyValid: Bool

    public init(apiKey: String, isAPIKeyValid: Bool) {
        self.apiKey = apiKey
        self.isAPIKeyValid = isAPIKeyValid
    }
}

public struct VoiceInkAIEnhancementCredentialStateResolutionPlan: Equatable, Sendable {
    public let provider: VoiceInkAIEnhancementProviderKind
    private let providerKeyStorageNameToLoad: String?

    public init(
        provider: VoiceInkAIEnhancementProviderKind,
        providerKeyStorageNameToLoad: String?
    ) {
        self.provider = provider
        self.providerKeyStorageNameToLoad = providerKeyStorageNameToLoad
    }

    public static func resolving(
        provider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementCredentialStateResolutionPlan {
        VoiceInkAIEnhancementCredentialStateResolutionPlan(
            provider: provider,
            providerKeyStorageNameToLoad: provider.userAPIKeyStorageName
        )
    }

    public func credentialState(
        savedAPIKey: String?,
        isLocalCLIConfigured: Bool
    ) -> VoiceInkAIEnhancementCredentialState {
        provider.textEnhancementCredentialState(
            savedAPIKey: savedAPIKey,
            isLocalCLIConfigured: isLocalCLIConfigured
        )
    }

    public func applyRuntimeState(
        loadSavedAPIKey: (String) -> String?,
        isLocalCLIConfigured: Bool,
        setCredentialState: (VoiceInkAIEnhancementCredentialState) -> Void
    ) {
        let savedAPIKey = providerKeyStorageNameToLoad.flatMap(loadSavedAPIKey)
        setCredentialState(credentialState(
            savedAPIKey: savedAPIKey,
            isLocalCLIConfigured: isLocalCLIConfigured
        ))
    }
}

public enum VoiceInkAIEnhancementProviderKind: String, CaseIterable, Sendable {
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

    public var aiModelProvider: VoiceInkAIModelProvider? {
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
    ) -> VoiceInkAIEnhancementCredentialState {
        guard requiresUserAPIKey else {
            return VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: self == .localCLI ? isLocalCLIConfigured : true
            )
        }

        guard let savedAPIKey else {
            return VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        }

        return VoiceInkAIEnhancementCredentialState(apiKey: savedAPIKey, isAPIKeyValid: true)
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
            return VoiceInkAIModelCatalog.defaultModel(for: provider)
        }

        switch self {
        case .ollama:
            return VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(
                from: defaults,
                fallback: Self.defaultOllamaTextEnhancementModel
            )
        case .localCLI:
            return Self.localCLITextEnhancementModel
        case .custom:
            return VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults)
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
        }
    }

    public var staticTextEnhancementModels: [String] {
        if let provider = aiModelProvider {
            return VoiceInkAIModelCatalog.availableModels(for: provider)
        }

        switch self {
        case .ollama, .localCLI, .custom:
            return []
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
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
            return VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults)
        case .localCLI:
            return ""
        case .custom:
            return VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults)
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelProvider.postProcessingRequestURL")
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

public extension VoiceInkAIModelProvider {
    var postProcessingRequestURL: URL? {
        switch self {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .assemblyAI:
            return VoiceInkProviderEndpoint.assemblyAITranscriptsURL(from: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL)
        case .cerebras:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.cerebras.apiBaseURL)
        case .deepgram:
            return nil
        case .elevenLabs:
            return VoiceInkProviderEndpoint.elevenLabsSpeechToTextURL(from: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL)
        case .gemini:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.gemini.apiBaseURL)
        case .groq:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.groq.apiBaseURL)
        case .mistral:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.mistralAPIBaseURL)
        case .openAI:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.openAI.apiBaseURL)
        case .openRouter:
            return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .soniox:
            return VoiceInkProviderEndpoint.sonioxAPIBaseURL
        case .speechmatics:
            return VoiceInkProviderEndpoint.speechmaticsAPIBaseURL
        }
    }

    var apiKeyConsoleURL: URL {
        switch self {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")!
        case .assemblyAI:
            return URL(string: "https://www.assemblyai.com/dashboard/api-keys")!
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.consoleURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.consoleURL
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/speech-synthesis")!
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.consoleURL
        case .groq:
            return VoiceInkProviderEndpoint.groq.consoleURL
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys")!
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.consoleURL
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")!
        case .soniox:
            return URL(string: "https://console.soniox.com/")!
        case .speechmatics:
            return URL(string: "https://portal.speechmatics.com/manage-access/")!
        }
    }
}
