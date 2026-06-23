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

    func testModeListPolicyAppendsModeWithoutReorderingExistingModes() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "Cloud")

        let updatedModes = VoiceInkModeListPolicy.appending(cloudMode, to: [localMode])

        XCTAssertEqual(updatedModes.map(\.id), [localMode.id, cloudMode.id])
    }

    func testModeListPolicyReplacesExistingModeById() throws {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "Cloud")
        let updatedMode = Mode(name: "Updated")

        let updatedModes = try XCTUnwrap(VoiceInkModeListPolicy.replacing(
            modeId: cloudMode.id,
            with: updatedMode,
            in: [localMode, cloudMode]
        ))

        XCTAssertEqual(updatedModes.map(\.id), [localMode.id, updatedMode.id])
        XCTAssertEqual(updatedModes.map(\.name), ["Local", "Updated"])
    }

    func testModeListPolicyLeavesMissingReplacementAsNoOp() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let updatedMode = Mode(name: "Updated")

        XCTAssertNil(VoiceInkModeListPolicy.replacing(
            modeId: UUID(),
            with: updatedMode,
            in: [localMode]
        ))
    }

    func testModeListPolicyRemovesModesByOffsets() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "Cloud")
        let backupMode = Mode(name: "Backup")

        let updatedModes = VoiceInkModeListPolicy.removing(
            at: IndexSet(integer: 1),
            from: [localMode, cloudMode, backupMode]
        )

        XCTAssertEqual(updatedModes.map(\.id), [localMode.id, backupMode.id])
    }

    func testModeListPolicySeedsDefaultModeWhenListIsEmpty() {
        let plan = VoiceInkModeListPolicy.defaultModeRepairPlan(modes: [], selectedModeId: nil)

        XCTAssertTrue(plan.shouldReplaceModes)
        XCTAssertEqual(plan.modes.count, 1)
        XCTAssertEqual(plan.modes.first?.id, plan.selectedModeId)
        XCTAssertEqual(plan.modes.first?.transcriptionProvider, .localWhisper)
    }

    func testModeListPolicyRepairsSelectionWithoutReplacingExistingModes() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "Cloud")

        let plan = VoiceInkModeListPolicy.defaultModeRepairPlan(
            modes: [localMode, cloudMode],
            selectedModeId: UUID()
        )

        XCTAssertFalse(plan.shouldReplaceModes)
        XCTAssertEqual(plan.modes.map(\.id), [localMode.id, cloudMode.id])
        XCTAssertEqual(plan.selectedModeId, localMode.id)
    }

    func testModeSettingsPolicyRepairsSelectionBeforeLanguageCompatibility() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "xAI", transcriptionProvider: .xai)
        let staleModeId = UUID()

        let plan = VoiceInkModeSettingsPolicy.repairPlan(
            modes: [localMode, cloudMode],
            selectedModeId: staleModeId,
            selectedTranscriptionLanguage: "zh"
        )

        XCTAssertFalse(plan.shouldReplaceModes)
        XCTAssertEqual(plan.modes.map(\.id), [localMode.id, cloudMode.id])
        XCTAssertEqual(plan.selectedModeId, localMode.id)
        XCTAssertEqual(plan.selectedTranscriptionLanguage, "zh")
        XCTAssertTrue(plan.shouldApplySelectedModeId(from: staleModeId))
        XCTAssertFalse(plan.shouldApplySelectedTranscriptionLanguage(from: "zh"))
    }

    func testModeSettingsPolicyRepairsLanguageForActiveMode() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "xAI", transcriptionProvider: .xai)

        let plan = VoiceInkModeSettingsPolicy.repairPlan(
            modes: [localMode, cloudMode],
            selectedModeId: cloudMode.id,
            selectedTranscriptionLanguage: "zh"
        )

        XCTAssertFalse(plan.shouldReplaceModes)
        XCTAssertEqual(plan.selectedModeId, cloudMode.id)
        XCTAssertEqual(plan.selectedTranscriptionLanguage, VoiceInkLanguageCatalog.autoDetectCode)
        XCTAssertFalse(plan.shouldApplySelectedModeId(from: cloudMode.id))
        XCTAssertTrue(plan.shouldApplySelectedTranscriptionLanguage(from: "zh"))
    }

    func testModeSettingsPolicySeedsDefaultModeAndRepairsLanguage() {
        let plan = VoiceInkModeSettingsPolicy.defaultModeRepairPlan(
            modes: [],
            selectedModeId: nil,
            selectedTranscriptionLanguage: "not-a-language"
        )

        XCTAssertTrue(plan.shouldReplaceModes)
        XCTAssertEqual(plan.modes.count, 1)
        XCTAssertEqual(plan.modes.first?.id, plan.selectedModeId)
        XCTAssertEqual(plan.modes.first?.transcriptionProvider, .localWhisper)
        XCTAssertEqual(plan.selectedTranscriptionLanguage, VoiceInkLanguageCatalog.autoDetectCode)
        XCTAssertTrue(plan.shouldApplySelectedModeId(from: nil))
        XCTAssertTrue(plan.shouldApplySelectedTranscriptionLanguage(from: "not-a-language"))
    }

    func testModeSettingsRepairPlanBuildsNoActionsWhenCurrentStateMatches() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let plan = VoiceInkModeSettingsPolicy.repairPlan(
            modes: [localMode],
            selectedModeId: localMode.id,
            selectedTranscriptionLanguage: VoiceInkLanguageCatalog.autoDetectCode
        )

        XCTAssertTrue(plan.applicationActions(
            currentSelectedModeId: localMode.id,
            currentSelectedTranscriptionLanguage: VoiceInkLanguageCatalog.autoDetectCode
        ).isEmpty)
    }

    func testModeSettingsRepairPlanBuildsSelectionAndLanguageActions() {
        let localMode = Mode.defaultLocalWhisper(name: "Local")
        let cloudMode = Mode(name: "xAI", transcriptionProvider: .xai)
        let staleModeId = UUID()
        let plan = VoiceInkModeSettingsPolicy.repairPlan(
            modes: [localMode, cloudMode],
            selectedModeId: staleModeId,
            selectedTranscriptionLanguage: "zh"
        )

        let actions = plan.applicationActions(
            currentSelectedModeId: staleModeId,
            currentSelectedTranscriptionLanguage: "not-a-language"
        )

        XCTAssertEqual(actions.count, 2)
        guard case .selectMode(let selectedModeId) = actions[0] else {
            return XCTFail("Expected selected-mode repair action")
        }
        XCTAssertEqual(selectedModeId, localMode.id)
        guard case .selectTranscriptionLanguage(let selectedLanguage) = actions[1] else {
            return XCTFail("Expected selected-language repair action")
        }
        XCTAssertEqual(selectedLanguage, "zh")
    }

    func testModeSettingsRepairPlanBuildsDefaultModeSeedActionsInOrder() {
        let plan = VoiceInkModeSettingsPolicy.defaultModeRepairPlan(
            modes: [],
            selectedModeId: nil,
            selectedTranscriptionLanguage: "not-a-language"
        )

        let actions = plan.applicationActions(
            currentSelectedModeId: nil,
            currentSelectedTranscriptionLanguage: "not-a-language"
        )

        XCTAssertEqual(actions.count, 3)
        guard case .replaceModes(let repairedModes) = actions[0] else {
            return XCTFail("Expected repaired mode-list action")
        }
        XCTAssertEqual(repairedModes.map(\.id), plan.modes.map(\.id))
        guard case .selectMode(let selectedModeId) = actions[1] else {
            return XCTFail("Expected selected-mode repair action")
        }
        XCTAssertEqual(selectedModeId, plan.selectedModeId)
        guard case .selectTranscriptionLanguage(let selectedLanguage) = actions[2] else {
            return XCTFail("Expected selected-language repair action")
        }
        XCTAssertEqual(selectedLanguage, VoiceInkLanguageCatalog.autoDetectCode)
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

    func testRuntimeConfigurationRepairsStaleModelSelections() {
        let mode = Mode(
            name: "Cloud",
            transcriptionProvider: .deepgram,
            transcriptionModel: "stale-transcription-model",
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini,
            postProcessingModel: "stale-post-processing-model"
        )

        let configuration = mode.runtimeConfiguration

        XCTAssertEqual(configuration.transcriptionModel, VoiceInkProviderKind.deepgram.defaultModel(for: .transcription))
        XCTAssertEqual(configuration.postProcessingModel, VoiceInkProviderKind.gemini.defaultModel(for: .postProcessing))
    }

    func testModeRepairUpdatesStaleModelSelections() {
        var mode = Mode(
            name: "Cloud",
            transcriptionProvider: .deepgram,
            transcriptionModel: "stale-transcription-model",
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini,
            postProcessingModel: "stale-post-processing-model"
        )

        mode.repairModelSelection()

        XCTAssertEqual(mode.transcriptionModel, VoiceInkProviderKind.deepgram.defaultModel(for: .transcription))
        XCTAssertEqual(mode.postProcessingModel, VoiceInkProviderKind.gemini.defaultModel(for: .postProcessing))
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

    func testModeSelectionPresentationHidesEmptyModeLists() {
        XCTAssertEqual([Mode]().modeSelectionPresentation, .hidden)
    }

    func testModeSelectionPresentationShowsSingleModeName() {
        let mode = Mode.defaultLocalWhisper(name: "Local")

        XCTAssertEqual([mode].modeSelectionPresentation, .singleModeName("Local"))
    }

    func testModeSelectionPresentationUsesPickerForMultipleModes() {
        let local = Mode.defaultLocalWhisper(name: "Local")
        let cloud = Mode(name: "Cloud")

        XCTAssertEqual([local, cloud].modeSelectionPresentation, .picker)
    }

    func testModeSelectionPresentationPreservesIOSControlTitle() {
        XCTAssertEqual(VoiceInkModeSelectionPresentation.controlTitle, "Mode")
    }

    func testModeSummaryPresentationUsesEffectiveModelNames() {
        let mode = Mode(
            name: "Cloud",
            transcriptionProvider: .deepgram,
            transcriptionModel: "stale-transcription-model",
            isPostProcessingEnabled: true,
            postProcessingProvider: .gemini,
            postProcessingModel: "stale-post-processing-model"
        )

        XCTAssertEqual(mode.summaryPresentation.title, "Cloud")
        XCTAssertEqual(
            mode.summaryPresentation.transcriptionText,
            "Transcription: \(VoiceInkProviderKind.deepgram.defaultModel(for: .transcription) ?? "")"
        )
        XCTAssertEqual(
            mode.summaryPresentation.postProcessingText,
            "Post-processing: \(VoiceInkProviderKind.gemini.defaultModel(for: .postProcessing) ?? "")"
        )
    }

    func testModeSummaryPresentationHidesDisabledPostProcessing() {
        let mode = Mode.defaultLocalWhisper(name: "Local")

        XCTAssertEqual(mode.summaryPresentation.title, "Local")
        XCTAssertEqual(
            mode.summaryPresentation.transcriptionText,
            "Transcription: \(VoiceInkTranscriptionModelCatalog.localBaseModel)"
        )
        XCTAssertNil(mode.summaryPresentation.postProcessingText)
    }

    func testModeFormPresentationBuildsNewModeCopy() {
        let mode = Mode.defaultLocalWhisper(name: "Local")
        let presentation = mode.formPresentation(isEditing: false)

        XCTAssertEqual(presentation.navigationTitle, "New Mode")
        XCTAssertEqual(presentation.modeDetailsSectionTitle, "Mode Details")
        XCTAssertEqual(presentation.modeNamePlaceholder, "Mode Name")
        XCTAssertEqual(presentation.transcriptionSectionTitle, "Transcription")
        XCTAssertEqual(presentation.postProcessingSectionTitle, "Post-processing")
        XCTAssertNil(presentation.postProcessingFooterText)
        XCTAssertEqual(presentation.enablePostProcessingTitle, "Enable Post-processing")
        XCTAssertEqual(presentation.providerPickerTitle, "Provider")
        XCTAssertEqual(presentation.promptTemplatePickerTitle, "Prompt Template")
        XCTAssertEqual(presentation.customPromptPlaceholder, "Custom Prompt")
        XCTAssertEqual(presentation.modelFieldTitle, "Model")
        XCTAssertEqual(presentation.saveButtonTitle, "Save")
    }

    func testModeFormPresentationBuildsEditPostProcessingCopy() {
        let mode = Mode(name: "Clean", isPostProcessingEnabled: true)
        let presentation = mode.formPresentation(isEditing: true)

        XCTAssertEqual(presentation.navigationTitle, "Edit Mode")
        XCTAssertEqual(
            presentation.postProcessingFooterText,
            "Configure how the raw transcription should be processed and refined."
        )
    }

    func testModeDraftValidationRequiresName() {
        XCTAssertFalse(Mode(name: "").isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.groq]
        ))
        XCTAssertFalse(Mode(name: "   \n").isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.groq]
        ))
    }

    func testModeDraftValidationRequiresCustomPromptOnlyForCustomTemplates() {
        var mode = Mode(name: "Custom")
        mode.promptTemplate.type = .custom
        mode.promptTemplate.customPrompt = "   "

        XCTAssertFalse(mode.isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.groq]
        ))

        mode.promptTemplate.customPrompt = "Clean this transcript."

        XCTAssertTrue(mode.isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.groq]
        ))
    }

    func testModeDraftValidationAllowsPredefinedTemplatesWithoutCustomPrompt() {
        XCTAssertTrue(Mode(name: "Summary").isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.groq]
        ))
    }

    func testModeDraftValidationRequiresAvailableProviderSelection() {
        XCTAssertFalse(Mode(name: "Unavailable").isSaveableDraft(
            availableTranscriptionProviders: [.localWhisper],
            availablePostProcessingProviders: [.groq]
        ))
        XCTAssertFalse(Mode(name: "Unavailable post-processing", isPostProcessingEnabled: true).isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.gemini]
        ))
        XCTAssertTrue(Mode(name: "Disabled post-processing", isPostProcessingEnabled: false).isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.gemini]
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
            availableTranscriptionProviders: [.deepgram],
            availablePostProcessingProviders: [.gemini]
        ))
        XCTAssertFalse(mode.isSaveableDraft(
            availableTranscriptionProviders: [.groq],
            availablePostProcessingProviders: [.gemini]
        ))
        XCTAssertFalse(mode.isSaveableDraft(
            availableTranscriptionProviders: [.deepgram],
            availablePostProcessingProviders: [.groq]
        ))
    }

    func testModeFormProviderAvailabilityOwnsDraftSaveabilityAndRepair() {
        let availability = VoiceInkModeFormProviderAvailability(
            transcriptionProviders: [.localWhisper],
            postProcessingProviders: [.gemini]
        )
        var mode = Mode(
            name: "Legacy",
            transcriptionProvider: .voiceInk,
            transcriptionModel: "stale-transcription-model",
            isPostProcessingEnabled: true,
            postProcessingProvider: .voiceInk,
            postProcessingModel: "stale-post-processing-model"
        )

        XCTAssertFalse(availability.canSave(mode))

        mode.repairProviderSelection(providerAvailability: availability)

        XCTAssertEqual(mode.transcriptionProvider, .localWhisper)
        XCTAssertEqual(mode.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(mode.postProcessingProvider, .gemini)
        XCTAssertEqual(mode.postProcessingModel, VoiceInkAIModelCatalog.defaultModel(for: .gemini))
        XCTAssertTrue(availability.canSave(mode))
    }

    func testModeFormProviderAvailabilityOwnsFormStatePresentation() {
        let availability = VoiceInkModeFormProviderAvailability(
            transcriptionProviders: [.localWhisper],
            postProcessingProviders: [.groq]
        )
        let rawMode = Mode(
            name: "Raw",
            transcriptionProvider: .localWhisper,
            isPostProcessingEnabled: false
        )
        var customMode = Mode(
            name: "Custom",
            transcriptionProvider: .localWhisper,
            isPostProcessingEnabled: true,
            postProcessingProvider: .groq
        )
        customMode.promptTemplate.type = .custom
        customMode.promptTemplate.customPrompt = "Clean this transcript."

        var blankCustomMode = customMode
        blankCustomMode.promptTemplate.customPrompt = "   "

        XCTAssertEqual(
            availability.formStatePresentation(for: rawMode),
            VoiceInkModeFormStatePresentation(
                shouldShowPostProcessingControls: false,
                shouldShowCustomPromptField: false,
                isSaveButtonDisabled: false
            )
        )
        XCTAssertEqual(
            availability.formStatePresentation(for: customMode),
            VoiceInkModeFormStatePresentation(
                shouldShowPostProcessingControls: true,
                shouldShowCustomPromptField: true,
                isSaveButtonDisabled: false
            )
        )
        XCTAssertEqual(
            availability.formStatePresentation(for: blankCustomMode),
            VoiceInkModeFormStatePresentation(
                shouldShowPostProcessingControls: true,
                shouldShowCustomPromptField: true,
                isSaveButtonDisabled: true
            )
        )
    }

    func testModeFormProviderAvailabilityCanReturnRepairedModeWithoutMutatingOriginal() {
        let availability = VoiceInkModeFormProviderAvailability(
            transcriptionProviders: [.deepgram],
            postProcessingProviders: [.groq]
        )
        let originalMode = Mode(
            name: "Legacy",
            transcriptionProvider: .localWhisper,
            isPostProcessingEnabled: false
        )

        let repairedMode = availability.repairedMode(originalMode)

        XCTAssertEqual(originalMode.transcriptionProvider, .localWhisper)
        XCTAssertEqual(repairedMode.transcriptionProvider, .deepgram)
    }
}
