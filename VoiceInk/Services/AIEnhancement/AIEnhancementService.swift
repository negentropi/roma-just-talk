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
            applyAIEnhancementPromptSettingsState(
                VoiceInkCustomPromptPolicy.settingsStateAfterEnhancementEnabledChange(
                    aiEnhancementPromptSettingsState,
                    prompts: customPrompts
                )
            )
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
    private let rateLimitPolicy = VoiceInkAIEnhancementRateLimitPolicy()
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
        let promptStoreState = VoiceInkCustomPromptPolicy.startupStoreState(
            loadedPrompts: VoiceInkCustomPromptStorage.loadPrompts(),
            selectedPromptId: VoiceInkCustomPromptStorage.loadSelectedPromptId(),
            isEnhancementEnabled: isEnhancementEnabled
        )
        self.customPrompts = promptStoreState.prompts
        self.selectedPromptId = promptStoreState.selectedPromptId

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        refreshPromptDetectionCache()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if let state = VoiceInkCustomPromptPolicy.settingsStateAfterAPIKeyValidityChange(
                self.aiEnhancementPromptSettingsState,
                isAPIKeyValid: self.aiService.isAPIKeyValid
            ) {
                self.isEnhancementEnabled = state.isEnhancementEnabled
                if self.selectedPromptId != state.selectedPromptId {
                    self.selectedPromptId = state.selectedPromptId
                }
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
        if let delay = rateLimitPolicy.delaySinceLastRequest(lastRequest: lastRequestTime, now: Date()) {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
        let requestPayload: VoiceInkAIEnhancementRequestPayload
        switch try VoiceInkAIEnhancementRequestPreparation.preparing(
            transcript: text,
            isConfigured: isConfigured
        ) {
        case .skipEmptyTranscript:
            return ""
        case .execute(let payload):
            requestPayload = payload
        }

        let formattedText = requestPayload.userMessage
        let systemMessage = await getSystemMessage()

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        let executionPlan = VoiceInkAIEnhancementRequestExecutionPlan.planning(
            provider: aiService.selectedProvider,
            modelName: aiService.currentModel
        )
        switch executionPlan.route {
        case .ollama:
            do {
                let result = try await aiService.enhanceWithOllama(
                    text: formattedText,
                    systemPrompt: systemMessage,
                    timeout: VoiceInkAIEnhancementRequestPreference.timeoutSeconds()
                )
                return VoiceInkAIEnhancementRequestPayload.enhancedText(from: result)
            } catch let error as VoiceInkAIEnhancementError {
                throw error
            } catch {
                throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
            }

        case .localCLI:
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return VoiceInkAIEnhancementRequestPayload.enhancedText(from: result)
            } catch {
                if let localError = error as? VoiceInkLocalCLIExecutionError {
                    throw VoiceInkAIEnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
                }
            }

        case .anthropicMessages, .openAICompatibleChatCompletions:
            try await waitForRateLimit()

            do {
                let result: String
                switch executionPlan.route {
                case .anthropicMessages:
                    result = try await AnthropicLLMClient.chatCompletion(
                        apiKey: aiService.apiKey,
                        model: executionPlan.modelName,
                        messages: [.user(formattedText)],
                        systemPrompt: systemMessage,
                        timeout: VoiceInkAIEnhancementRequestPreference.timeoutSeconds()
                    )
                case .openAICompatibleChatCompletions:
                    let requestPlan = try executionPlan.openAICompatibleRequestOrThrow()
                    result = try await OpenAILLMClient.chatCompletion(
                        baseURL: requestPlan.requestURL,
                        apiKey: aiService.apiKey,
                        model: executionPlan.modelName,
                        messages: [.user(formattedText)],
                        systemPrompt: systemMessage,
                        temperature: requestPlan.requestParameters.temperature,
                        reasoningEffort: requestPlan.requestParameters.reasoningEffort,
                        extraBody: requestPlan.requestParameters.extraBodyParameters,
                        timeout: VoiceInkAIEnhancementRequestPreference.timeoutSeconds()
                    )
                case .ollama, .localCLI:
                    preconditionFailure("Local AI routes should return before cloud request execution.")
                }
                return VoiceInkAIEnhancementRequestPayload.enhancedText(from: result)
            } catch let error as LLMKitError {
                throw VoiceInkAIEnhancementError.transportFailure(
                    error.voiceInkAIEnhancementTransportFailure
                )
            } catch let error as VoiceInkAIEnhancementError {
                throw error
            } catch {
                throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
            }
        }
    }

    private func makeRequestWithRetry(text: String, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retryState = VoiceInkAIEnhancementRetryState(
            maxAttempts: maxRetries,
            initialDelay: initialDelay,
            retryOnTimeout: VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout()
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
                if let retryPlan = retryState.recordNonEnhancementError(error) {
                    try await handleRetryDecision(
                        retryPlan.decision,
                        state: retryState,
                        transportNetworkFailure: retryPlan.isTransportNetworkFailure
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
        if let message = VoiceInkAIEnhancementRetryProgressPresentation.diagnosticMessage(
            for: decision,
            failedAttempts: state.failedAttempts,
            maxAttempts: state.maxAttempts
        ) {
            logger.warning("\(message, privacy: .public)")
        }

        switch decision {
        case .retryAfterDelay(let delay):
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        case .retryImmediately:
            break
        case .fail(let error):
            logRetryFailure(
                error,
                attempts: state.maxAttempts,
                retryOnTimeoutEnabled: state.retryOnTimeout,
                transportNetworkFailure: transportNetworkFailure
            )
            throw error
        }
    }

    private func logRetryFailure(
        _ error: VoiceInkAIEnhancementError,
        attempts: Int,
        retryOnTimeoutEnabled: Bool,
        transportNetworkFailure: Bool
    ) {
        if let message = VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
            for: error,
            attempts: attempts,
            retryOnTimeoutEnabled: retryOnTimeoutEnabled,
            transportNetworkFailure: transportNetworkFailure
        ) {
            logger.error("\(message, privacy: .public)")
        }
    }

    func enhance(_ text: String) async throws -> VoiceInkAIEnhancementResult {
        let startTime = Date()
        let promptName = activePrompt?.title

        let result = try await makeRequestWithRetry(text: text)
        let endTime = Date()
        return VoiceInkAIEnhancementResult.completed(
            text: result,
            startedAt: startTime,
            endedAt: endTime,
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
        applyAIEnhancementPromptSettingsState(
            result.applyingSettingsState(current: aiEnhancementPromptSettingsState)
        )
    }

    func restorePromptDetectionSettings(_ result: VoiceInkPromptDetectionResult) {
        applyAIEnhancementPromptSettingsState(
            result.restoringSettingsState(current: aiEnhancementPromptSettingsState)
        )
    }

    private func refreshPromptDetectionCache() {
        promptDetectionPrompts = VoiceInkCustomPromptPolicy.triggerDetectablePrompts(from: customPrompts)
    }

    private var aiEnhancementPromptSettingsState: VoiceInkAIEnhancementPromptSettingsState {
        VoiceInkAIEnhancementPromptSettingsState(
            isEnhancementEnabled: isEnhancementEnabled,
            selectedPromptId: selectedPromptId
        )
    }

    private func applyAIEnhancementPromptSettingsState(_ state: VoiceInkAIEnhancementPromptSettingsState?) {
        guard let state else { return }

        if isEnhancementEnabled != state.isEnhancementEnabled {
            isEnhancementEnabled = state.isEnhancementEnabled
        }

        if selectedPromptId != state.selectedPromptId {
            selectedPromptId = state.selectedPromptId
        }
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

private extension LLMKitError {
    var voiceInkAIEnhancementTransportFailure: VoiceInkAIEnhancementTransportFailure {
        switch self {
        case .missingAPIKey:
            return .missingAPIKey
        case .httpError(let statusCode, let message):
            return .httpStatus(statusCode: statusCode, message: message)
        case .noResultReturned:
            return .noResultReturned
        case .networkError:
            return .network
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .invalidRequest(
                description: localizedDescription
            )
        }
    }
}
