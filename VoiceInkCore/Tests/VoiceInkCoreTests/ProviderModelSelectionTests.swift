#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class ProviderModelSelectionTests: XCTestCase {
    func testSelectedModelUsesFixedModelWhenProviderHasOne() {
        XCTAssertEqual(
            VoiceInkProviderKind.voiceInk.selectedModel("stale-model", for: .transcription),
            VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel
        )
    }

    func testSelectedModelPreservesAvailableCurrentModel() {
        XCTAssertEqual(
            VoiceInkProviderKind.deepgram.selectedModel("nova-3-medical", for: .transcription),
            "nova-3-medical"
        )
    }

    func testSelectedModelFallsBackToProviderDefaultWhenCurrentModelIsUnavailable() {
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.selectedModel("old-gemini-model", for: .postProcessing),
            VoiceInkAIModelCatalog.firstAvailableModel(for: .gemini)
        )
    }

    func testSelectedModelReturnsEmptyStringWhenUseHasNoModels() {
        XCTAssertEqual(
            VoiceInkProviderKind.cerebras.selectedModel("anything", for: .transcription),
            ""
        )
    }
}
#endif
