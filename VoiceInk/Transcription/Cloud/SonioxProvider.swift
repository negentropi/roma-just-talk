import Foundation
import SwiftData
import VoiceInkCore

struct SonioxProvider: CloudProvider {
    let modelProvider: ModelProvider = .soniox

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SonioxStreamingProvider(modelContext: modelContext)
    }

}
