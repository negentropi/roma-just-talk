import Foundation
import SwiftData
import VoiceInkCore

struct CartesiaProvider: CloudProvider {
    let modelProvider: ModelProvider = .cartesia
    let isStreamingOnly: Bool = true
    private let cartesiaClient = VoiceInkCartesiaClient()

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .cartesia)
            .map { $0.makeCloudModel(provider: .cartesia) }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        CartesiaStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        let result = await cartesiaClient.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: key
        )
        return (result.isValid, result.errorMessage)
    }
}
