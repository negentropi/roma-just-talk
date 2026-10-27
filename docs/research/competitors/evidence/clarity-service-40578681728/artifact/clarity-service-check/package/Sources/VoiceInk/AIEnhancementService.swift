import Foundation
import SwiftData
import AppKit
import os
import LLMkit
import VoiceInkCore

@MainActor
struct AIEnhancementProviderSnapshot {
    let modelName: String
    let apiKey: String
    let executionPlan: VoiceInkAIEnhancementRequestExecutionPlan
    let timeoutSeconds: TimeInterval
    let retryOnTimeout: Bool
    fileprivate let ollama: OllamaService.RequestConfiguration?
    fileprivate let localCLI: LocalCLIService.RequestConfiguration?
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.aiEnhancementService
    )

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
        VoiceInkCustomPromptPolicy.activePrompt(selectedPromptId: selectedPromptId, prompts: allPrompts)
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

        let storedIsEnhancementEnabled = VoiceInkAIEnhancementPreference.isEnabled()
        self.isEnhancementEnabled = storedIsEnhancementEnabled
        self.useClipboardContext = VoiceInkAIEnhancementContextPreference.useClipboardContext()
        self.useScreenCaptureContext = VoiceInkAIEnhancementContextPreference.useScreenCaptureContext()
        let promptStoreState = VoiceInkCustomPromptPolicy.startupStoreState(
            loadedPrompts: VoiceInkCustomPromptStorage.loadPrompts(),
            selectedPromptId: VoiceInkCustomPromptStorage.loadSelectedPromptId(),
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

    func providerSnapshot() throws -> AIEnhancementProviderSnapshot {
        guard isConfigured else { throw VoiceInkAIEnhancementError.notConfigured }
        let provider = aiService.selectedProvider
        // Metadata and wire requests share the runtime picker model; the generic model cache can be stale.
        let ollama = provider == .ollama ? OllamaService.RequestConfiguration.fromPreferences() : nil
        let modelName = ollama?.modelName ?? aiService.currentModel
        return AIEnhancementProviderSnapshot(
            modelName: modelName,
            apiKey: aiService.apiKey,
            executionPlan: .planning(provider: provider, modelName: modelName),
            timeoutSeconds: VoiceInkAIEnhancementRequestPreference.timeoutSeconds(),
            retryOnTimeout: VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(),
            ollama: ollama,
            localCLI: provider == .localCLI ? LocalCLIService.RequestConfiguration.fromPreferences() : nil
        )
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

    private func makeRequest(
        text: String,
        writingRequest: VoiceInkWritingActionRequest? = nil,
        providerSnapshot: AIEnhancementProviderSnapshot? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        let requestPayload: VoiceInkAIEnhancementRequestPayload
        switch try VoiceInkAIEnhancementRequestPreparation.preparing(
            transcript: text,
            isConfigured: providerSnapshot != nil || isConfigured
        ) {
        case .skipEmptyTranscript:
            return ""
        case .execute(let payload):
            requestPayload = payload
        }

        let formattedText: String
        let systemMessage: String
        if let writingRequest {
            // Explicit actions use only the captured selection and spoken input.
            // Do not collect live selection, screen or clipboard context here.
            formattedText = writingRequest.userMessage
            systemMessage = writingRequest.systemMessage
        } else {
            formattedText = requestPayload.userMessage
            systemMessage = await getSystemMessage()
        }

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        let output = try await executeProviderRequest(
            systemMessage: systemMessage,
            userMessage: formattedText,
            using: providerSnapshot
        )
        let legacyOutput: String
        if providerSnapshot?.localCLI != nil {
            legacyOutput = VoiceInkLocalCLIPreference.cleanedOutput(output)
            guard !legacyOutput.isEmpty else {
                throw VoiceInkAIEnhancementError.localCLIExecutionFailure(VoiceInkLocalCLIExecutionError.emptyOutput)
            }
        } else {
            legacyOutput = output
        }
        return VoiceInkAIEnhancementRequestPayload.enhancedText(from: legacyOutput)
    }

    private func executeProviderRequest(
        systemMessage: String,
        userMessage: String,
        using providerSnapshot: AIEnhancementProviderSnapshot?
    ) async throws -> String {
        try Task.checkCancellation()
        let executionPlan = providerSnapshot?.executionPlan ?? VoiceInkAIEnhancementRequestExecutionPlan.planning(
            provider: aiService.selectedProvider,
            modelName: aiService.currentModel
        )
        let apiKey = providerSnapshot?.apiKey ?? aiService.apiKey
        let timeoutSeconds = providerSnapshot?.timeoutSeconds ?? VoiceInkAIEnhancementRequestPreference.timeoutSeconds()

        let output = try await executionPlan.applyRuntimeState(
            ollama: { _ in
                do {
                    let result: String
                    if let ollama = providerSnapshot?.ollama {
                        result = try await OllamaService.enhance(
                            userMessage,
                            withSystemPrompt: systemMessage,
                            configuration: ollama,
                            timeout: timeoutSeconds
                        )
                    } else {
                        result = try await aiService.enhanceWithOllama(text: userMessage, systemPrompt: systemMessage, timeout: timeoutSeconds)
                    }
                    try Task.checkCancellation()
                    return result
                } catch {
                    try rethrowCancellation(error)
                    if let error = error as? VoiceInkAIEnhancementError { throw error }
                    throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
                }
            },
            localCLI: { _ in
                do {
                    let result: String
                    if let localCLI = providerSnapshot?.localCLI {
                        result = try await LocalCLIService.execute(
                            systemPrompt: systemMessage,
                            userPrompt: userMessage,
                            configuration: localCLI
                        )
                    } else {
                        // Custom retains its live executor and legacy output policy.
                        result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: userMessage)
                    }
                    try Task.checkCancellation()
                    return result
                } catch {
                    try rethrowCancellation(error)
                    throw VoiceInkAIEnhancementError.localCLIExecutionFailure(error)
                }
            },
            anthropicMessages: { modelName in
                try await executeCloudAIRequest {
                    try await AnthropicLLMClient.chatCompletion(
                        apiKey: apiKey,
                        model: modelName,
                        messages: [.user(userMessage)],
                        systemPrompt: systemMessage,
                        timeout: timeoutSeconds
                    )
                }
            },
            openAICompatibleChatCompletions: { modelName, requestURL, requestParameters in
                try await executeCloudAIRequest {
                    try await OpenAILLMClient.chatCompletion(
                        baseURL: requestURL,
                        apiKey: apiKey,
                        model: modelName,
                        messages: [.user(userMessage)],
                        systemPrompt: systemMessage,
                        temperature: requestParameters.temperature,
                        reasoningEffort: requestParameters.reasoningEffort,
                        extraBody: requestParameters.extraBodyParameters,
                        timeout: timeoutSeconds
                    )
                }
            }
        )
        try Task.checkCancellation()
        return output
    }

    private func executeCloudAIRequest(_ request: () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        try await waitForRateLimit()
        try Task.checkCancellation()

        do {
            let result = try await request()
            try Task.checkCancellation()
            return result
        } catch {
            try rethrowCancellation(error)
            if let error = error as? LLMKitError {
                throw VoiceInkAIEnhancementError.transportFailure(error.voiceInkAIEnhancementTransportFailure)
            }
            if let error = error as? VoiceInkAIEnhancementError { throw error }
            throw VoiceInkAIEnhancementError.customError(error.localizedDescription)
        }
    }

    private func makeRequestWithRetry(
        retryOnTimeout: Bool,
        operation: () async throws -> String
    ) async throws -> String {
        var retryState = VoiceInkAIEnhancementRetryState(retryOnTimeout: retryOnTimeout)

        while true {
            try Task.checkCancellation()
            do {
                let result = try await operation()
                try Task.checkCancellation()
                return result
            } catch {
                try rethrowCancellation(error)
                if let error = error as? VoiceInkAIEnhancementError {
                    try await handleRetryDecision(retryState.recordFailure(error), state: retryState)
                } else if let retryPlan = retryState.recordNonEnhancementError(error) {
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

    private func rethrowCancellation(_ error: Error) throws {
        try Task.checkCancellation()
        if error is CancellationError { throw error }
    }

    private func handleRetryDecision(
        _ decision: VoiceInkAIEnhancementRetryDecision,
        state: VoiceInkAIEnhancementRetryState,
        transportNetworkFailure: Bool = false
    ) async throws {
        try Task.checkCancellation()
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

        let result = try await makeRequestWithRetry(
            retryOnTimeout: VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout()
        ) {
            try await makeRequest(text: text)
        }
        try Task.checkCancellation()
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

    func performWritingAction(
        _ request: VoiceInkWritingActionRequest,
        using providerSnapshot: AIEnhancementProviderSnapshot
    ) async throws -> VoiceInkAIEnhancementResult {
        let startTime = Date()
        let result = try await makeRequestWithRetry(retryOnTimeout: providerSnapshot.retryOnTimeout) {
            try await makeRequest(text: request.transcript, writingRequest: request, providerSnapshot: providerSnapshot)
        }
        try Task.checkCancellation()
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceInkWritingActionError.emptyOutput
        }
        return VoiceInkAIEnhancementResult.completed(
            text: result,
            startedAt: startTime,
            endedAt: Date(),
            modelName: providerSnapshot.modelName,
            promptName: request.promptName,
            requestSystemMessage: request.systemMessage,
            requestUserMessage: request.userMessage
        )
    }

    func performClarity(
        request: VoiceInkClarityRequest,
        using providerSnapshot: AIEnhancementProviderSnapshot
    ) async throws -> VoiceInkAIEnhancementResult {
        try Task.checkCancellation()
        let startTime = Date()
        let response = try await makeRequestWithRetry(retryOnTimeout: providerSnapshot.retryOnTimeout) {
            try await executeProviderRequest(
                systemMessage: request.systemMessage,
                userMessage: request.userMessage,
                using: providerSnapshot
            )
        }
        try Task.checkCancellation()
        let result: String
        do {
            result = try request.decodeResponse(response)
        } catch {
            try rethrowCancellation(error)
            throw error
        }
        try Task.checkCancellation()
        return VoiceInkAIEnhancementResult.completed(
            text: result,
            startedAt: startTime,
            endedAt: Date(),
            modelName: providerSnapshot.modelName,
            promptName: nil,
            requestSystemMessage: request.systemMessage,
            requestUserMessage: request.userMessage
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

    func selectPromptFromShortcut(index: Int) {
        applyAIEnhancementPromptSettingsState(
            VoiceInkCustomPromptPolicy.settingsStateAfterPromptShortcutSelection(
                index: index,
                current: aiEnhancementPromptSettingsState,
                prompts: allPrompts
            )
        )
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
