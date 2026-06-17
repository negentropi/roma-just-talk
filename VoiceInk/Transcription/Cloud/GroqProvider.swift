import Foundation
import SwiftData
import VoiceInkCore

struct GroqProvider: CloudProvider {
    let modelProvider: ModelProvider = .groq

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

}
