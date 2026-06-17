import Foundation
@testable import VoiceInkCore

final class ModeRuntimeConfigurationTests: XCTestCase {
    func testEmptyModeCollectionUsesDefaultLocalWhisperFallbackConfiguration() {
        let configuration = [Mode]().runtimeConfiguration(selectedModeId: nil)

        XCTAssertEqual(configuration, .fallback)
        XCTAssertEqual(configuration.transcriptionProvider, .localWhisper)
        XCTAssertEqual(configuration.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(configuration.postProcessingProvider, .groq)
        XCTAssertEqual(configuration.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .groq))
        XCTAssertEqual(configuration.prompt, Mode.defaultLocalWhisper().effectivePrompt)
        XCTAssertFalse(configuration.isPostProcessingEnabled)
    }

    func testFallbackConfigurationMatchesDefaultLocalWhisperMode() {
        XCTAssertEqual(VoiceInkModeRuntimeConfiguration.fallback, Mode.defaultLocalWhisper().runtimeConfiguration)
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

    func testDefaultModesAndSelectionSelectsSeededLocalMode() {
        let defaultSelection = Mode.defaultModesAndSelection()

        XCTAssertEqual(defaultSelection.modes.count, 1)
        XCTAssertEqual(defaultSelection.modes.first?.id, defaultSelection.selectedModeId)
        XCTAssertEqual(defaultSelection.modes.first?.transcriptionProvider, .localWhisper)
        XCTAssertEqual(defaultSelection.modes.first?.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
    }

    func testUnsupportedTranscriptionProviderDoesNotReceiveFakeFallbackModel() {
        let mode = Mode(name: "Unsupported", transcriptionProvider: .cerebras)

        XCTAssertEqual(mode.transcriptionProvider, .cerebras)
        XCTAssertEqual(mode.transcriptionModel, "")
    }

    func testSelectingTranscriptionProviderRepairsModelThroughSharedPolicy() {
        var mode = Mode(
            name: "Draft",
            transcriptionProvider: .groq,
            transcriptionModel: "whisper-large-v3"
        )

        mode.selectTranscriptionProvider(.localWhisper)

        XCTAssertEqual(mode.transcriptionProvider, .localWhisper)
        XCTAssertEqual(mode.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
    }

    func testSelectingPostProcessingProviderRepairsModelThroughSharedPolicy() {
        var mode = Mode(
            name: "Draft",
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini,
            postProcessingModel: "old-gemini-model"
        )

        mode.selectPostProcessingProvider(.groq)

        XCTAssertEqual(mode.postProcessingProvider, .groq)
        XCTAssertEqual(mode.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .groq))
    }

    func testModeRepairReplacesUnavailableProvidersWithFirstAvailableProvider() {
        var mode = Mode(
            name: "Legacy",
            transcriptionProvider: .voiceInk,
            transcriptionModel: "whisper-large-v3",
            isPostProcessingEnabled: true,
            postProcessingProvider: .voiceInk,
            postProcessingModel: "openai/gpt-oss-120b"
        )

        mode.repairProviderSelection(
            availableTranscriptionProviders: [.localWhisper],
            availablePostProcessingProviders: [.groq]
        )

        XCTAssertEqual(mode.transcriptionProvider, .localWhisper)
        XCTAssertEqual(mode.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(mode.postProcessingProvider, .groq)
        XCTAssertEqual(mode.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .groq))
    }

    func testModeRepairLeavesUnavailablePostProcessingProviderWhenDisabled() {
        var mode = Mode(
            name: "Legacy",
            transcriptionProvider: .groq,
            transcriptionModel: VoiceInkProviderKind.groq.defaultModel(for: .transcription),
            isPostProcessingEnabled: false,
            postProcessingProvider: .voiceInk,
            postProcessingModel: ""
        )

        mode.repairProviderSelection(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.gemini]
        )

        XCTAssertEqual(mode.postProcessingProvider, .voiceInk)
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

    func testTranscriptionLanguagesUseWhisperFallbackWhenNoModeExists() {
        XCTAssertEqual(
            [Mode]().transcriptionLanguages(selectedModeId: nil),
            VoiceInkLanguageCatalog.whisperLanguages()
        )
    }

    func testTranscriptionLanguagesUseActiveModeProvider() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "Speechmatics", transcriptionProvider: .speechmatics)

        XCTAssertEqual(
            [localMode, cloudMode].transcriptionLanguages(selectedModeId: cloudMode.id),
            VoiceInkLanguageCatalog.languages(for: VoiceInkProviderKind.speechmatics)
        )
    }

    func testSelectedTranscriptionLanguageRepairUsesActiveModeLanguages() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "xAI", transcriptionProvider: .xai)

        XCTAssertEqual(
            [localMode, cloudMode].repairedSelectedTranscriptionLanguage(
                "zh",
                selectedModeId: cloudMode.id
            ),
            VoiceInkLanguageCatalog.autoDetectCode
        )
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

    func testModeDraftValidationRequiresAvailableProviderSelection() {
        XCTAssertFalse(Mode.isSaveableDraft(
            name: "Unavailable",
            promptTemplateType: .summary,
            customPrompt: "",
            transcriptionProviderAvailable: false
        ))
        XCTAssertFalse(Mode.isSaveableDraft(
            name: "Unavailable post-processing",
            promptTemplateType: .summary,
            customPrompt: "",
            postProcessingProviderAvailable: false,
            isPostProcessingEnabled: true
        ))
        XCTAssertTrue(Mode.isSaveableDraft(
            name: "Disabled post-processing",
            promptTemplateType: .summary,
            customPrompt: "",
            postProcessingProviderAvailable: false,
            isPostProcessingEnabled: false
        ))
    }

    func testModeDraftValidationUsesModeProviderSelections() {
        let mode = Mode(
            name: "Cloud",
            transcriptionProvider: .deepgram,
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini
        )

        XCTAssertTrue(mode.isSaveableDraft(
            promptTemplateType: .summary,
            customPrompt: "",
            availableTranscriptionProviders: [.deepgram],
            availablePostProcessingProviders: [.gemini]
        ))
        XCTAssertFalse(mode.isSaveableDraft(
            promptTemplateType: .summary,
            customPrompt: "",
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.gemini]
        ))
        XCTAssertFalse(mode.isSaveableDraft(
            promptTemplateType: .summary,
            customPrompt: "",
            availableTranscriptionProviders: [.deepgram],
            availablePostProcessingProviders: [.groq]
        ))
    }
}
