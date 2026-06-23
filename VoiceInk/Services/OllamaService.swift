import Foundation
import SwiftUI
import LLMkit
import VoiceInkCore

class OllamaService: ObservableObject {
    // MARK: - Published Properties
    @Published var baseURL: String {
        didSet {
            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL(baseURL)
        }
    }

    @Published var selectedModel: String {
        didSet {
            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel(selectedModel)
        }
    }

    @Published var availableModels: [OllamaModel] = []
    @Published var isConnected: Bool = false
    @Published var isLoadingModels: Bool = false

    init() {
        self.baseURL = VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
        self.selectedModel = VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
    }

    private var baseURLValue: URL? {
        URL(string: baseURL)
    }

    @MainActor
    func checkConnection() async {
        guard let url = baseURLValue else {
            isConnected = false
            return
        }
        isConnected = await OllamaClient.checkConnection(baseURL: url)
    }

    @MainActor
    func refreshModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }

        guard let url = baseURLValue else {
            print(VoiceInkOllamaServiceDiagnostics.invalidBaseURLMessage)
            availableModels = []
            return
        }

        do {
            let models = try await OllamaClient.fetchModels(baseURL: url)
            let plan = VoiceInkAIEnhancementModelRefreshPlan.refreshed(
                provider: .ollama,
                currentModel: selectedModel,
                refreshedModels: models.map { $0.name },
                defaultModel: VoiceInkAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            )
            availableModels = models

            if let refreshedModel = VoiceInkDynamicAIProviderPreference.applyOllamaModelRefreshPlan(plan) {
                selectedModel = refreshedModel
            }
        } catch {
            print(
                VoiceInkOllamaServiceDiagnostics.modelFetchFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
            availableModels = []
        }
    }

    func enhance(_ text: String, withSystemPrompt systemPrompt: String? = nil, timeout: TimeInterval) async throws -> String {
        guard let systemPrompt = systemPrompt else {
            throw VoiceInkOllamaEnhancementFailure.invalidRequest.enhancementError
        }

        guard let url = baseURLValue else {
            throw VoiceInkOllamaEnhancementFailure.invalidURL.enhancementError
        }

        do {
            return try await OllamaClient.generate(
                baseURL: url,
                model: selectedModel,
                prompt: text,
                systemPrompt: systemPrompt,
                temperature: VoiceInkAIEnhancementProviderKind.ollamaTextEnhancementRequestTemperature,
                think: false,
                timeout: timeout
            )
        } catch let error as LLMKitError {
            throw VoiceInkOllamaEnhancementFailure
                .transportFailure(error.voiceInkOllamaTransportFailure)
                .enhancementError
        }
    }
}

private extension LLMKitError {
    var voiceInkOllamaTransportFailure: VoiceInkOllamaTransportFailure {
        switch self {
        case .invalidURL:
            return .invalidURL
        case .httpError(let statusCode, _):
            return .httpStatus(statusCode)
        case .networkError:
            return .network
        case .noResultReturned, .decodingError:
            return .invalidResponse
        case .encodingError:
            return .invalidRequest
        case .missingAPIKey:
            return .missingCredential
        case .timeout:
            return .timeout
        }
    }
}
