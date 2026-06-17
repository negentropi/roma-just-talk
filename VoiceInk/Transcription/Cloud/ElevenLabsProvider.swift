import Foundation
import SwiftData
import VoiceInkCore

struct ElevenLabsProvider: CloudProvider {
    let modelProvider: ModelProvider = .elevenLabs

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        ElevenLabsStreamingProvider()
    }

}
