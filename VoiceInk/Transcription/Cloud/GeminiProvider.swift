import Foundation
import SwiftData
import VoiceInkCore

struct GeminiProvider: CloudProvider {
    let modelProvider: ModelProvider = .gemini

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

}
