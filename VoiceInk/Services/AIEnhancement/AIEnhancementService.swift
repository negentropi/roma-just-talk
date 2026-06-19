import Foundation
import SwiftData
import AppKit
import os
import LLMkit
import VoiceInkCore

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "AIEnhancementService")

    @Published var isEnhancementEnabled: Bool {
        didSet {
            VoiceInkAIEnhancementPreference.saveIsEnabled(isEnhancementEnabled)
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = VoiceInkCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(
                    selectedPromptId,
                    prompts: customPrompts
                )
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(useClipboardContext)
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(useScreenCaptureContext)
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [VoiceInkCustomPrompt] {
        didSet {
            VoiceInkCustomPromptStorage.savePrompts(customPrompts)
            refreshPromptDetectionCache()
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            VoiceInkCustomPromptStorage.saveSelectedPromptId(selectedPromptId)
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: VoiceInkCustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [VoiceInkCustomPrompt] {
        return customPrompts
    }

    private(set) var promptDetectionPrompts: [VoiceInkCustomPrompt] = []

    var hasPromptTriggerWords: Bool {
        !promptDetectionPrompts.isEmpty
    }

    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private var baseTimeout: TimeInterval {
        VoiceInkAIEnhancementRequestPreference.timeoutSeconds()
    }
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        self.isEnhancementEnabled = VoiceInkAIEnhancementPreference.isEnabled()
        self.useClipboardContext = VoiceInkAIEnhancementContextPreference.useClipboardContext()
        self.useScreenCaptureContext = VoiceInkAIEnhancementContextPreference.useScreenCaptureContext()
        self.customPrompts = VoiceInkCustomPromptStorage.loadPrompts()
        self.selectedPromptId = VoiceInkCustomPromptStorage.loadSelectedPromptId()

        let repairedPromptId = VoiceInkCustomPromptPolicy.repairedSelectedPromptId(
            selectedPromptId,
            isEnhancementEnabled: isEnhancementEnabled,
            prompts: allPrompts
        )
        if selectedPromptId != repairedPromptId {
            self.selectedPromptId = repairedPromptId
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        customPrompts = VoiceInkCustomPromptPolicy.repairedPredefinedPrompts(in: customPrompts)
        refreshPromptDetectionCache()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService {
        aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage() async -> String {
        let promptText = VoiceInkCustomPromptPolicy.basePromptText(
            activePrompt: activePrompt,
            prompts: allPrompts
        )
        return VoiceInkAIEnhancementPromptBuilder.systemMessage(
            basePrompt: promptText,
            context: VoiceInkAIEnhancementPromptContext(
                selectedText: await selectedTextContext(),
                clipboardText: useClipboardContext ? lastCapturedClipboard : nil,
                currentWindowText: useScreenCaptureContext ? screenCaptureService.lastCapturedText : nil,
                customVocabulary: customVocabularyService.getCustomVocabulary(from: modelContext)
            )
        )
    }

    private func selectedTextContext() async -> String? {
        guard AXIsProcessTrusted() else {
            return nil
        }
        return await SelectedTextService.fetchSelectedText()
    }

    private func makeRequest(text: String) async throws -> String {
        guard isConfigured else {
            throw VoiceInkAIEnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = VoiceInkAIRequestPrompts.taggedTranscript(text)
        let systemMessage = await getSystemMessage()

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        let executionRoute = aiService.selectedProvider.textEnhancementExecutionRoute
        switch executionRoute {
        case .ollama:
            do {
                let result = try await aiService.enhanceWithOllama(
                    text: formattedText,
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
                return VoiceInkAIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalAIError {
                    switch localError {
                    case .timeout:
                        throw VoiceInkAIEnhancementError.timeout
                    default:
                        throw VoiceInkAIEnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                    }
                } else {
                    throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
                }
            }

        case .localCLI:
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return VoiceInkAIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw VoiceInkAIEnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
                }
            }

        case .anthropicMessages, .openAICompatibleChatCompletions:
            try await waitForRateLimit()

            do {
                let result: String
                switch executionRoute {
                case .anthropicMessages:
                    result = try await AnthropicLLMClient.chatCompletion(
                        apiKey: aiService.apiKey,
                        model: aiService.currentModel,
                        messages: [.user(formattedText)],
                        systemPrompt: systemMessage,
                        timeout: baseTimeout
                    )
                case .openAICompatibleChatCompletions:
                    guard let baseURL = aiService.selectedProvider.textEnhancementRequestURL() else {
                        throw VoiceInkAIEnhancementError.customError(aiService.selectedProvider.invalidTextEnhancementRequestURLMessage)
                    }
                    let requestParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
                        for: aiService.selectedProvider.aiModelProvider,
                        modelName: aiService.currentModel
                    )
                    result = try await OpenAILLMClient.chatCompletion(
                        baseURL: baseURL,
                        apiKey: aiService.apiKey,
                        model: aiService.currentModel,
                        messages: [.user(formattedText)],
                        systemPrompt: systemMessage,
                        temperature: requestParameters.temperature,
                        reasoningEffort: requestParameters.reasoningEffort,
                        extraBody: requestParameters.extraBodyParameters,
                        timeout: baseTimeout
                    )
                case .ollama, .localCLI:
                    preconditionFailure("Local AI routes should return before cloud request execution.")
                }
                return VoiceInkAIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch let error as LLMKitError {
                throw mapLLMKitError(error)
            } catch let error as VoiceInkAIEnhancementError {
                throw error
            } catch {
                throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
            }
        }
    }

    private func mapLLMKitError(_ error: LLMKitError) -> VoiceInkAIEnhancementError {
        switch error {
        case .missingAPIKey:
            return .notConfigured
        case .httpError(let statusCode, let message):
            return VoiceInkAIEnhancementError.httpError(statusCode: statusCode, message: message)
        case .noResultReturned:
            return .enhancementFailed
        case .networkError:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .customError(error.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var retryOnTimeout: Bool {
        VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout()
    }

    private func makeRequestWithRetry(text: String, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retryState = VoiceInkAIEnhancementRetryState(
            maxAttempts: maxRetries,
            initialDelay: initialDelay,
            retryOnTimeout: retryOnTimeout
        )

        while true {
            do {
                return try await makeRequest(text: text)
            } catch let error as VoiceInkAIEnhancementError {
                try await handleRetryDecision(
                    retryState.recordFailure(error),
                    state: retryState
                )
            } catch {
                if VoiceInkAIEnhancementError.transportNetworkError(for: error) == .networkError {
                    try await handleRetryDecision(
                        retryState.recordTransportNetworkFailure(),
                        state: retryState,
                        transportNetworkFailure: true
                    )
                } else {
                    throw error
                }
            }
        }
    }

    private func handleRetryDecision(
        _ decision: VoiceInkAIEnhancementRetryDecision,
        state: VoiceInkAIEnhancementRetryState,
        transportNetworkFailure: Bool = false
    ) async throws {
        switch decision {
        case .retryAfterDelay(let delay):
            logger.warning("Request failed, retrying in \(delay, privacy: .public)s... (Attempt \(state.failedAttempts, privacy: .public)/\(state.maxAttempts, privacy: .public))")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        case .retryImmediately:
            logger.warning("Request timed out, retrying immediately... (Attempt \(state.failedAttempts, privacy: .public)/\(state.maxAttempts, privacy: .public))")
        case .fail(let error):
            logRetryFailure(
                error,
                attempts: state.maxAttempts,
                transportNetworkFailure: transportNetworkFailure
            )
            throw error
        }
    }

    private func logRetryFailure(
        _ error: VoiceInkAIEnhancementError,
        attempts: Int,
        transportNetworkFailure: Bool
    ) {
        switch error {
        case .timeout where retryOnTimeout:
            logger.error("Request timed out after \(attempts, privacy: .public) retries.")
        case .timeout:
            logger.error("Request timed out, failing immediately (retry disabled).")
        case .networkError where transportNetworkFailure:
            logger.error("Request failed after \(attempts, privacy: .public) retries with network error.")
        case .networkError, .serverError, .rateLimitExceeded:
            logger.error("Request failed after \(attempts, privacy: .public) retries.")
        default:
            break
        }
    }

    func enhance(_ text: String) async throws -> VoiceInkAIEnhancementResult {
        let startTime = Date()
        let promptName = activePrompt?.title

        let result = try await makeRequestWithRetry(text: text)
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        return VoiceInkAIEnhancementResult(
            text: result,
            duration: duration,
            modelName: aiService.currentModel,
            promptName: promptName,
            requestSystemMessage: lastSystemMessageSent,
            requestUserMessage: lastUserMessageSent
        )
    }

    func captureScreenContext() async {
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func captureClipboardContext() {
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }
    
    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        screenCaptureService.lastCapturedText = nil
    }

    func addPrompt(_ prompt: VoiceInkCustomPrompt) {
        applyPromptStoreState(
            VoiceInkCustomPromptPolicy.addingPrompt(
                prompt,
                to: customPrompts,
                selectedPromptId: selectedPromptId
            )
        )
    }

    func updatePrompt(_ prompt: VoiceInkCustomPrompt) {
        applyPromptStoreState(
            VoiceInkCustomPromptPolicy.updatingPrompt(
                prompt,
                in: customPrompts,
                selectedPromptId: selectedPromptId
            )
        )
    }

    func deletePrompt(_ prompt: VoiceInkCustomPrompt) {
        applyPromptStoreState(
            VoiceInkCustomPromptPolicy.deletingPrompt(
                prompt,
                from: customPrompts,
                selectedPromptId: selectedPromptId
            )
        )
    }

    func setActivePrompt(_ prompt: VoiceInkCustomPrompt) {
        selectedPromptId = prompt.id
    }

    func analyzePromptTrigger(in text: String) -> VoiceInkPromptDetectionResult {
        VoiceInkPromptDetectionPolicy.analyzeText(
            text,
            prompts: promptDetectionPrompts,
            isEnhancementEnabled: isEnhancementEnabled,
            selectedPromptId: selectedPromptId
        )
    }

    func applyPromptDetectionResult(_ result: VoiceInkPromptDetectionResult) {
        guard result.shouldEnableAI else { return }

        if !isEnhancementEnabled {
            isEnhancementEnabled = true
        }
        if let promptId = result.selectedPromptId {
            selectedPromptId = promptId
        }
    }

    func restorePromptDetectionSettings(_ result: VoiceInkPromptDetectionResult) {
        guard result.shouldEnableAI else { return }

        let restoredEnhancementState = result.restoredEnhancementState(current: isEnhancementEnabled)
        if isEnhancementEnabled != restoredEnhancementState {
            isEnhancementEnabled = restoredEnhancementState
        }

        let restoredPromptId = result.restoredPromptId(current: selectedPromptId)
        if selectedPromptId != restoredPromptId {
            selectedPromptId = restoredPromptId
        }
    }

    private func refreshPromptDetectionCache() {
        promptDetectionPrompts = VoiceInkCustomPromptPolicy.triggerDetectablePrompts(from: customPrompts)
    }

    private func applyPromptStoreState(_ state: VoiceInkCustomPromptStoreState) {
        if customPrompts != state.prompts {
            customPrompts = state.prompts
        }
        if selectedPromptId != state.selectedPromptId {
            selectedPromptId = state.selectedPromptId
        }
    }
}
