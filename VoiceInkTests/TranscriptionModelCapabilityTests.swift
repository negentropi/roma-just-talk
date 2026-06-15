import Foundation
import Testing
@testable import VoiceInk

private struct CapabilityTestModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description = "Capability test model"
    let provider: ModelProvider
    let isMultilingualModel = true
    let supportedLanguages: [String: String] = [:]
}

struct TranscriptionModelCapabilityTests {
    @Test func recordedFileTranscriptionIsUnavailableOnlyForStreamingOnlyProviders() {
        #expect(CapabilityTestModel(name: "local", displayName: "Local", provider: .fluidAudio).supportsRecordedFileTranscription)
        #expect(CapabilityTestModel(name: "cloud-batch", displayName: "Cloud Batch", provider: .deepgram).supportsRecordedFileTranscription)
        #expect(!CapabilityTestModel(name: "streaming-only", displayName: "Streaming Only", provider: .cartesia).supportsRecordedFileTranscription)
    }
}
