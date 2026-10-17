import Foundation
import SwiftUI
import LLMkit
import RomaCore

class OllamaService: ObservableObject {
    // MARK: - Published Properties
    @Published var baseURL: String {
        didSet {
            RomaDynamicAIProviderPreference.saveOllamaBaseURL(baseURL)
        }
    }

    @Published var selectedModel: String {
        didSet {
            RomaDynamicAIProviderPreference.saveOllamaSelectedModel(selectedModel)
        }
    }

    @Published var availableModels: [OllamaModel] = []
    @Published var isConnected: Bool = false
    @Published var isLoadingModels: Bool = false

    init() {
        self.baseURL = RomaDynamicAIProviderPreference.ollamaBaseURL()
        self.selectedModel = RomaDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
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
            print(RomaOllamaServiceDiagnostics.invalidBaseURLMessage)
            availableModels = []
            return
        }

        do {
            let models = try await OllamaClient.fetchModels(baseURL: url)
            let plan = RomaAIEnhancementModelRefreshPlan.refreshed(
                provider: .ollama,
                currentModel: selectedModel,
                refreshedModels: models.map { $0.name },
                defaultModel: RomaAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            )
            availableModels = models

            if let refreshedModel = RomaDynamicAIProviderPreference.applyOllamaModelRefreshPlan(plan) {
                selectedModel = refreshedModel
            }
        } catch {
            print(
                RomaOllamaServiceDiagnostics.modelFetchFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
            availableModels = []
        }
    }

    func enhance(_ text: String, withSystemPrompt systemPrompt: String? = nil, timeout: TimeInterval) async throws -> String {
        guard let systemPrompt = systemPrompt else {
            throw RomaOllamaEnhancementFailure.invalidRequest.enhancementError
        }

        guard let url = baseURLValue else {
            throw RomaOllamaEnhancementFailure.invalidURL.enhancementError
        }

        do {
            return try await OllamaClient.generate(
                baseURL: url,
                model: selectedModel,
                prompt: text,
                systemPrompt: systemPrompt,
                temperature: RomaAIEnhancementProviderKind.ollamaTextEnhancementRequestTemperature,
                think: false,
                timeout: timeout
            )
        } catch let error as LLMKitError {
            throw RomaOllamaEnhancementFailure
                .transportFailure(error.romaOllamaTransportFailure)
                .enhancementError
        }
    }
}

private extension LLMKitError {
    var romaOllamaTransportFailure: RomaOllamaTransportFailure {
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
