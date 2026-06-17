import Foundation
import SwiftData
import VoiceInkCore

struct DeepgramProvider: CloudProvider {
    let modelProvider: ModelProvider = .deepgram

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        DeepgramStreamingProvider(modelContext: modelContext)
    }

}
