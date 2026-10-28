import Foundation
import SwiftUI
import LLMkit
import VoiceInkCore

class OllamaService: ObservableObject {
    struct RequestConfiguration {
        let baseURL: String
        let modelName: String

        static func fromPreferences() -> Self {
            Self(
                baseURL: VoiceInkDynamicAIProviderPreference.ollamaBaseURL(),
                modelName: VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
            )
        }
    }

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
        let configuration = RequestConfiguration.fromPreferences()
        self.baseURL = configuration.baseURL
        self.selectedModel = configuration.modelName
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
        try await Self.enhance(
            text,
            withSystemPrompt: systemPrompt,
            configuration: RequestConfiguration(baseURL: baseURL, modelName: selectedModel),
            timeout: timeout
        )
    }

    static func enhance(
        _ text: String,
        withSystemPrompt systemPrompt: String? = nil,
        configuration: RequestConfiguration,
        timeout: TimeInterval
    ) async throws -> String {
        guard let systemPrompt = systemPrompt else {
            throw VoiceInkOllamaEnhancementFailure.invalidRequest.enhancementError
        }

        guard let url = URL(string: configuration.baseURL) else {
            throw VoiceInkOllamaEnhancementFailure.invalidURL.enhancementError
        }

        do {
            return try await OllamaClient.generate(
                baseURL: url,
                model: configuration.modelName,
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
