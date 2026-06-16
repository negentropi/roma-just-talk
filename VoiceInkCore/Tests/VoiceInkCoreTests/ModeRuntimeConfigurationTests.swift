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
        XCTAssertEqual(configuration.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .groq))
        XCTAssertEqual(configuration.prompt, "")
        XCTAssertFalse(configuration.isPostProcessingEnabled)
    }

    func testDefaultModeUsesSharedPostProcessingDefaultPolicy() {
        let mode = Mode(name: "Default")

        XCTAssertEqual(mode.postProcessingProvider, .groq)
        XCTAssertEqual(mode.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .groq))
    }

    func testDefaultLocalWhisperUsesSharedPostProcessingDefaultPolicy() {
        let mode = Mode.defaultLocalWhisper()

        XCTAssertEqual(mode.transcriptionProvider, .localWhisper)
        XCTAssertEqual(mode.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(mode.postProcessingProvider, .groq)
        XCTAssertEqual(mode.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .groq))
        XCTAssertFalse(mode.isPostProcessingEnabled)
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

    func testRepairedSelectedModeIdPreservesExistingSelection() {
        let firstMode = Mode.defaultLocalWhisper(name: "Local")
        let secondMode = Mode(name: "Cloud")

        XCTAssertEqual(
            [firstMode, secondMode].repairedSelectedModeId(secondMode.id),
            secondMode.id
        )
    }

    func testRepairedSelectedModeIdFallsBackToFirstModeForMissingSelection() {
        let firstMode = Mode.defaultLocalWhisper(name: "Local")
        let secondMode = Mode(name: "Cloud")

        XCTAssertEqual(
            [firstMode, secondMode].repairedSelectedModeId(UUID()),
            firstMode.id
        )
        XCTAssertEqual(
            [firstMode, secondMode].repairedSelectedModeId(nil),
            firstMode.id
        )
    }

    func testRepairedSelectedModeIdReturnsNilForEmptyModes() {
        XCTAssertNil([Mode]().repairedSelectedModeId(UUID()))
        XCTAssertNil([Mode]().repairedSelectedModeId(nil))
    }

    func testModeDraftValidationRequiresName() {
        XCTAssertFalse(Mode.isSaveableDraft(
            name: "",
            promptTemplateType: .summary,
            customPrompt: ""
        ))
        XCTAssertFalse(Mode.isSaveableDraft(
            name: "   \n",
            promptTemplateType: .summary,
            customPrompt: ""
        ))
    }

    func testModeDraftValidationRequiresCustomPromptOnlyForCustomTemplates() {
        XCTAssertFalse(Mode.isSaveableDraft(
            name: "Custom",
            promptTemplateType: .custom,
            customPrompt: "   "
        ))
        XCTAssertTrue(Mode.isSaveableDraft(
            name: "Custom",
            promptTemplateType: .custom,
            customPrompt: "Clean this transcript."
        ))
    }

    func testModeDraftValidationAllowsPredefinedTemplatesWithoutCustomPrompt() {
        XCTAssertTrue(Mode.isSaveableDraft(
            name: "Summary",
            promptTemplateType: .summary,
            customPrompt: ""
        ))
    }
}
#endif
