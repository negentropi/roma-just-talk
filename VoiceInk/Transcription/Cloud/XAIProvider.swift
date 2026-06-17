import Foundation
import SwiftData
import VoiceInkCore

struct XAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .xai

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        XAIStreamingProvider()
    }

}
