import Foundation
import SwiftData
import VoiceInkCore

struct CartesiaProvider: CloudProvider {
    let modelProvider: ModelProvider = .cartesia
    let isStreamingOnly: Bool = true

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        CartesiaStreamingProvider(modelContext: modelContext)
    }
}
