import Foundation
import SwiftData
import VoiceInkCore

struct CartesiaProvider: CloudProvider {
    let modelProvider: ModelProvider = .cartesia

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        CartesiaStreamingProvider(modelContext: modelContext)
    }
}
