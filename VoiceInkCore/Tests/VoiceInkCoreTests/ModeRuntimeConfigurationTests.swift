#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class ModeRuntimeConfigurationTests: XCTestCase {
    func testEmptyModeCollectionUsesExistingFallbackConfiguration() {
        let configuration = [Mode]().runtimeConfiguration(selectedModeId: nil)

        XCTAssertEqual(configuration, .fallback)
        XCTAssertEqual(configuration.transcriptionProvider, .groq)
        XCTAssertEqual(configuration.transcriptionModel, VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel)
        XCTAssertEqual(configuration.postProcessingProvider, .groq)
        XCTAssertEqual(configuration.postProcessingModel, VoiceInkAIModelCatalog.firstAvailableModel(for: .groq))
        XCTAssertEqual(configuration.prompt, "")
        XCTAssertFalse(configuration.isPostProcessingEnabled)
    }

    func testRuntimeConfigurationUsesSelectedModeWhenAvailable() {
        let firstMode = Mode.defaultLocalWhisper(name: "Local")
        let selectedMode = Mode(
            name: "Cloud",
            transcriptionProvider: .deepgram,
            transcriptionModel: "nova-3-medical",
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini,
            postProcessingModel: "gemini-2.5-flash",
            promptTemplate: VoiceInkPostProcessingPromptTemplate(
                type: .custom,
                customPrompt: "Clean this transcript."
            )
        )

        let configuration = [firstMode, selectedMode].runtimeConfiguration(selectedModeId: selectedMode.id)

        XCTAssertEqual(configuration.transcriptionProvider, .deepgram)
        XCTAssertEqual(configuration.transcriptionModel, "nova-3-medical")
        XCTAssertEqual(configuration.postProcessingProvider, .gemini)
        XCTAssertEqual(configuration.postProcessingModel, "gemini-2.5-flash")
        XCTAssertEqual(configuration.prompt, "Clean this transcript.")
        XCTAssertTrue(configuration.isPostProcessingEnabled)
    }

    func testRuntimeConfigurationFallsBackToFirstModeWhenSelectionIsMissing() {
        let firstMode = Mode.defaultLocalWhisper(name: "Local")
        let secondMode = Mode(name: "Cloud")

        let configuration = [firstMode, secondMode].runtimeConfiguration(selectedModeId: UUID())

        XCTAssertEqual(configuration, firstMode.runtimeConfiguration)
    }
}
#endif
