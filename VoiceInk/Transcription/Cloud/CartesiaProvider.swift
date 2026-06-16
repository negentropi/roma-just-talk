import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct CartesiaProvider: CloudProvider {
    let modelProvider: ModelProvider = .cartesia
    let isStreamingOnly: Bool = true

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .cartesia)
            .map { $0.makeCloudModel(provider: .cartesia) }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        CartesiaStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await CartesiaStreamingClient.verifyAPIKey(key)
    }
}
