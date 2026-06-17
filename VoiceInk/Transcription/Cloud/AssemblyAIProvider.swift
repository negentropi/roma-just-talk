import Foundation
import SwiftData
import VoiceInkCore

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(modelContext: modelContext)
    }

}
