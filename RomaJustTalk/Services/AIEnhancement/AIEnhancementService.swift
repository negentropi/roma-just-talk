import Foundation
import SwiftData
import AppKit
import os
import LLMkit
import RomaCore

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.aiEnhancementService
    )

    @Published var isEnhancementEnabled: Bool {
        didSet {
            RomaAIEnhancementPreference.saveIsEnabled(isEnhancementEnabled)
            applyAIEnhancementPromptSettingsState(
                RomaCustomPromptPolicy.settingsStateAfterEnhancementEnabledChange(
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
            RomaAIEnhancementContextPreference.saveUseClipboardContext(useClipboardContext)
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            RomaAIEnhancementContextPreference.saveUseScreenCaptureContext(useScreenCaptureContext)
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [RomaCustomPrompt] {
        didSet {
            RomaCustomPromptStorage.savePrompts(customPrompts)
            refreshPromptDetectionCache()
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            RomaCustomPromptStorage.saveSelectedPromptId(selectedPromptId)
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: RomaCustomPrompt? {
        RomaCustomPromptPolicy.activePrompt(selectedPromptId: selectedPromptId, prompts: allPrompts)
    }

    var allPrompts: [RomaCustomPrompt] {
        return customPrompts
    }

    private(set) var promptDetectionPrompts: [RomaCustomPrompt] = []

    var hasPromptTriggerWords: Bool {
        !promptDetectionPrompts.isEmpty
    }

    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private let rateLimitPolicy = RomaAIEnhancementRateLimitPolicy()
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        let storedIsEnhancementEnabled = RomaAIEnhancementPreference.isEnabled()
        self.isEnhancementEnabled = storedIsEnhancementEnabled
        self.useClipboardContext = RomaAIEnhancementContextPreference.useClipboardContext()
        self.useScreenCaptureContext = RomaAIEnhancementContextPreference.useScreenCaptureContext()
        let promptStoreState = RomaCustomPromptPolicy.startupStoreState(
            loadedPrompts: RomaCustomPromptStorage.loadPrompts(),
            selectedPromptId: RomaCustomPromptStorage.loadSelectedPromptId(),
            isEnhancementEnabled: storedIsEnhancementEnabled
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
            if let state = RomaCustomPromptPolicy.settingsStateAfterAPIKeyValidityChange(
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
        let promptText = RomaCustomPromptPolicy.basePromptText(
            activePrompt: activePrompt,
            prompts: allPrompts
        )
        return RomaAIEnhancementPromptBuilder.systemMessage(
            basePrompt: promptText,
            context: RomaAIEnhancementPromptContext(
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
        let requestPayload: RomaAIEnhancementRequestPayload
        switch try RomaAIEnhancementRequestPreparation.preparing(
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

        let executionPlan = RomaAIEnhancementRequestExecutionPlan.planning(
            provider: aiService.selectedProvider,
            modelName: aiService.currentModel
        )

        return try await executionPlan.applyRuntimeState(
            ollama: { _ in
                do {
                    let result = try await aiService.enhanceWithOllama(
                        text: formattedText,
                        systemPrompt: systemMessage,
                        timeout: RomaAIEnhancementRequestPreference.timeoutSeconds()
                    )
                    return RomaAIEnhancementRequestPayload.enhancedText(from: result)
                } catch let error as RomaAIEnhancementError {
                    throw error
                } catch {
                    throw RomaAIEnhancementError.customError(error.localizedDescription)
                }
            },
            localCLI: { _ in
                do {
                    let result = try await aiService.enhanceWithLocalCLI(
                        systemPrompt: systemMessage,
                        userPrompt: formattedText
                    )
                    return RomaAIEnhancementRequestPayload.enhancedText(from: result)
                } catch {
                    throw RomaAIEnhancementError.localCLIExecutionFailure(error)
                }
            },
            anthropicMessages: { modelName in
                try await executeCloudAIRequest {
                    try await AnthropicLLMClient.chatCompletion(
                        apiKey: aiService.apiKey,
                        model: modelName,
                        messages: [.user(formattedText)],
                        systemPrompt: systemMessage,
                        timeout: RomaAIEnhancementRequestPreference.timeoutSeconds()
                    )
                }
            },
            openAICompatibleChatCompletions: { modelName, requestURL, requestParameters in
                try await executeCloudAIRequest {
                    try await OpenAILLMClient.chatCompletion(
                        baseURL: requestURL,
                        apiKey: aiService.apiKey,
                        model: modelName,
                        messages: [.user(formattedText)],
                        systemPrompt: systemMessage,
                        temperature: requestParameters.temperature,
                        reasoningEffort: requestParameters.reasoningEffort,
                        extraBody: requestParameters.extraBodyParameters,
                        timeout: RomaAIEnhancementRequestPreference.timeoutSeconds()
                    )
                }
            }
        )
    }

    private func executeCloudAIRequest(_ request: () async throws -> String) async throws -> String {
        try await waitForRateLimit()

        do {
            let result = try await request()
            return RomaAIEnhancementRequestPayload.enhancedText(from: result)
        } catch let error as LLMKitError {
            throw RomaAIEnhancementError.transportFailure(
                error.romaAIEnhancementTransportFailure
            )
        } catch let error as RomaAIEnhancementError {
            throw error
        } catch {
            throw RomaAIEnhancementError.customError(error.localizedDescription)
        }
    }

    private func makeRequestWithRetry(text: String) async throws -> String {
        var retryState = RomaAIEnhancementRetryState(
            retryOnTimeout: RomaAIEnhancementRequestPreference.shouldRetryOnTimeout()
        )

        while true {
            do {
                return try await makeRequest(text: text)
            } catch let error as RomaAIEnhancementError {
                try await handleRetryDecision(
                    retryState.recordFailure(error),
                    state: retryState
                )
            } catch {
                if let retryPlan = retryState.recordNonEnhancementError(error) {
                    try await retryPlan.applyRuntimeState { decision, transportNetworkFailure in
                        try await handleRetryDecision(
                            decision,
                            state: retryState,
                            transportNetworkFailure: transportNetworkFailure
                        )
                    }
                } else {
                    throw error
                }
            }
        }
    }

    private func handleRetryDecision(
        _ decision: RomaAIEnhancementRetryDecision,
        state: RomaAIEnhancementRetryState,
        transportNetworkFailure: Bool = false
    ) async throws {
        if let message = RomaAIEnhancementRetryProgressPresentation.diagnosticMessage(
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
        _ error: RomaAIEnhancementError,
        attempts: Int,
        retryOnTimeoutEnabled: Bool,
        transportNetworkFailure: Bool
    ) {
        if let message = RomaAIEnhancementRetryFailurePresentation.diagnosticMessage(
            for: error,
            attempts: attempts,
            retryOnTimeoutEnabled: retryOnTimeoutEnabled,
            transportNetworkFailure: transportNetworkFailure
        ) {
            logger.error("\(message, privacy: .public)")
        }
    }

    func enhance(_ text: String) async throws -> RomaAIEnhancementResult {
        let startTime = Date()
        let promptName = activePrompt?.title

        let result = try await makeRequestWithRetry(text: text)
        let endTime = Date()
        return RomaAIEnhancementResult.completed(
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

    func addPrompt(_ prompt: RomaCustomPrompt) {
        applyPromptStoreState(
            RomaCustomPromptPolicy.addingPrompt(
                prompt,
                to: customPrompts,
                selectedPromptId: selectedPromptId
            )
        )
    }

    func updatePrompt(_ prompt: RomaCustomPrompt) {
        applyPromptStoreState(
            RomaCustomPromptPolicy.updatingPrompt(
                prompt,
                in: customPrompts,
                selectedPromptId: selectedPromptId
            )
        )
    }

    func deletePrompt(_ prompt: RomaCustomPrompt) {
        applyPromptStoreState(
            RomaCustomPromptPolicy.deletingPrompt(
                prompt,
                from: customPrompts,
                selectedPromptId: selectedPromptId
            )
        )
    }

    func setActivePrompt(_ prompt: RomaCustomPrompt) {
        selectedPromptId = prompt.id
    }

    func selectPromptFromShortcut(index: Int) {
        applyAIEnhancementPromptSettingsState(
            RomaCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: index,
                current: aiEnhancementPromptSettingsState,
                prompts: allPrompts
            )
        )
    }

    func analyzePromptTrigger(in text: String) -> RomaPromptDetectionResult {
        RomaPromptDetectionPolicy.analyzeText(
            text,
            prompts: promptDetectionPrompts,
            isEnhancementEnabled: isEnhancementEnabled,
            selectedPromptId: selectedPromptId
        )
    }

    func applyPromptDetectionResult(_ result: RomaPromptDetectionResult) {
        applyAIEnhancementPromptSettingsState(
            result.applyingSettingsState(current: aiEnhancementPromptSettingsState)
        )
    }

    func restorePromptDetectionSettings(_ result: RomaPromptDetectionResult) {
        applyAIEnhancementPromptSettingsState(
            result.restoringSettingsState(current: aiEnhancementPromptSettingsState)
        )
    }

    private func refreshPromptDetectionCache() {
        promptDetectionPrompts = RomaCustomPromptPolicy.triggerDetectablePrompts(from: customPrompts)
    }

    private var aiEnhancementPromptSettingsState: RomaAIEnhancementPromptSettingsState {
        RomaAIEnhancementPromptSettingsState(
            isEnhancementEnabled: isEnhancementEnabled,
            selectedPromptId: selectedPromptId
        )
    }

    private func applyAIEnhancementPromptSettingsState(_ state: RomaAIEnhancementPromptSettingsState?) {
        guard let state else { return }

        if isEnhancementEnabled != state.isEnhancementEnabled {
            isEnhancementEnabled = state.isEnhancementEnabled
        }

        if selectedPromptId != state.selectedPromptId {
            selectedPromptId = state.selectedPromptId
        }
    }

    private func applyPromptStoreState(_ state: RomaCustomPromptStoreState) {
        if customPrompts != state.prompts {
            customPrompts = state.prompts
        }
        if selectedPromptId != state.selectedPromptId {
            selectedPromptId = state.selectedPromptId
        }
    }
}

private extension LLMKitError {
    var romaAIEnhancementTransportFailure: RomaAIEnhancementTransportFailure {
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
