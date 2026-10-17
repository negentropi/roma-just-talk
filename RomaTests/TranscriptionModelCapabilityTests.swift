import Foundation
import Testing
import RomaCore
@testable import RomaJustTalk

private struct CapabilityTestModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description = "Capability test model"
    let provider: RomaMacOSTranscriptionModelProvider
    let isMultilingualModel = true
    let supportedLanguages: [String: String] = [:]
}

@Suite(.serialized)
struct TranscriptionModelCapabilityTests {
    @Test func recordedFileTranscriptionIsUnavailableOnlyForStreamingOnlyProviders() {
        #expect(CapabilityTestModel(name: "local", displayName: "Local", provider: .fluidAudio).supportsRecordedFileTranscription)
        #expect(CapabilityTestModel(name: "cloud-batch", displayName: "Cloud Batch", provider: .deepgram).supportsRecordedFileTranscription)
        #expect(!CapabilityTestModel(name: "streaming-only", displayName: "Streaming Only", provider: .cartesia).supportsRecordedFileTranscription)
    }

    @Test func localFluidAudioUsesShortFinalCommitTimeout() {
        #expect(RomaStreamingFinalCommitTimeout.nanoseconds(for: .localFluidAudio) == 1_000_000_000)
        #expect(RomaStreamingFinalCommitTimeout.nanoseconds(for: .cloud) == 10_000_000_000)
    }
}
