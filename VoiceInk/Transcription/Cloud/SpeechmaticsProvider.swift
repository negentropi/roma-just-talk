import Foundation
import SwiftData
import VoiceInkCore

struct SpeechmaticsProvider: CloudProvider {
    let modelProvider: ModelProvider = .speechmatics

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SpeechmaticsStreamingProvider(modelContext: modelContext)
    }

}
