import Foundation
import SwiftData
import VoiceInkCore

struct MistralProvider: CloudProvider {
    let modelProvider: ModelProvider = .mistral

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        MistralStreamingProvider()
    }

}
