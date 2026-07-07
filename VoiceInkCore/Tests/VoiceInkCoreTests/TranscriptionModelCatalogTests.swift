import Foundation
import VoiceInkCore

final class TranscriptionModelCatalogTests: XCTestCase {
    func testAvailabilityRequirementPredicatesIdentifyShellFactsNeeded() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityRequirement.configuredAPIKey.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.configuredAPIKey.requiresCurrentOSSupport)
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityRequirement.currentOSSupport.requiresCurrentOSSupport)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.currentOSSupport.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.downloadedLocalWhisperModel.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.downloadedLocalWhisperModel.requiresCurrentOSSupport)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.alwaysAvailable.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.unavailable.requiresCurrentOSSupport)
    }

    func testConfiguredAPIKeyRequirementUsesConfiguredKeyFact() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: true
        ).isUsable)

        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: false
        ).isUsable)
    }

    func testCurrentOSRequirementUsesCurrentOSFact() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: true
        ).isUsable)

        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: false
        ).isUsable)
    }

    func testLocalModelRequirementsUseDownloadedFacts() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: false
        ).isUsable)

        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: false
        ).isUsable)
    }

    func testAlwaysAvailableAndUnavailableRequirementsStayExplicit() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(requirement: .alwaysAvailable).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(requirement: .unavailable).isUsable)
    }

    func testNativeAppleTranscriptionPolicyPreservesMacOSErrorCopy() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .unsupportedOS),
            "SpeechAnalyzer requires macOS 26 or later."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .transcriptionFailed),
            "Transcription failed using SpeechAnalyzer."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .localeNotSupported),
            "The selected language is not supported by SpeechAnalyzer."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .invalidModel),
            "Invalid model type provided for Native Apple transcription."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .assetDownloadRequired(displayName: "English")),
            "Download required for English."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: .resultStreamTimedOut),
            "Apple Speech did not finish returning transcription results."
        )
    }

    func testNativeAppleFailureKindIsSharedThrowableLocalizedError() {
        let unsupportedError: Error = VoiceInkNativeAppleTranscriptionFailureKind.unsupportedOS
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: unsupportedError),
            "SpeechAnalyzer requires macOS 26 or later."
        )

        let assetError: Error = VoiceInkNativeAppleTranscriptionFailureKind.assetDownloadRequired(displayName: "English")
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: assetError),
            "Download required for English."
        )
    }

    func testNativeAppleTranscriptionPolicyPreservesSelectionAndTimeoutCopy() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.requiresMacOS26Title(modelDisplayName: "Apple Speech"),
            "Apple Speech requires macOS 26 or later"
        )
        XCTAssertEqual(VoiceInkNativeAppleTranscriptionPolicy.resultStreamTimeout(forAudioDuration: 0), 20.0)
        XCTAssertEqual(VoiceInkNativeAppleTranscriptionPolicy.resultStreamTimeout(forAudioDuration: 2.0), 20.0)
        XCTAssertEqual(VoiceInkNativeAppleTranscriptionPolicy.resultStreamTimeout(forAudioDuration: 5.0), 30.0)
    }

    func testNativeAppleTranscriptionDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.unsupportedOSDiagnosticMessage,
            "SpeechAnalyzer is not available on this macOS version"
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.unsupportedLocaleDiagnosticMessage(localeIdentifier: "en-US"),
            "Transcription failed: Locale 'en-US' is not supported by SpeechTranscriber."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.missingAssetDiagnosticMessage(localeIdentifier: "en-US"),
            "Transcription failed: Assets for 'en-US' are not downloaded."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.emptyAudioDiagnosticMessage(localeIdentifier: "en-US"),
            "Transcription failed: Apple Speech received no audio samples for 'en-US'."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.assetReservationReturnedFalseDiagnosticMessage(
                localeIdentifier: "en-US",
                statusDescription: "installed"
            ),
            "Apple Speech asset reservation returned false for 'en-US'. Continuing because the locale is already downloaded. Status: installed."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.assetReservationFailedDiagnosticMessage(
                localeIdentifier: "en-US",
                errorDescription: "Disk full",
                statusDescription: "installed"
            ),
            "Apple Speech asset reservation failed for 'en-US': Disk full. Continuing because the locale is already downloaded. Status: installed."
        )
        XCTAssertEqual(
            VoiceInkNativeAppleTranscriptionPolicy.resultWaitFailedDiagnosticMessage(errorDescription: "Timed out"),
            "Apple Speech result wait failed: Timed out."
        )
    }

    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["whisper"])
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["fluid"])
    }

    func testCloudRouteSkipsLocalRuntimeWork() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testModelSelectionResourcePlanOwnsLocalWhisperRuntimeUpdate() {
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
                .modelSelectionLocalWhisperRuntimeUpdate),
            []
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
    }

    func testDeletedCurrentModelPlanClearsSelectionAndMarksLocalWhisperUnloaded() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "ggml-base.en"
        )

        XCTAssertEqual(
            transcriptionModelDeletionEvents(for: plan),
            ["clearCurrentModel", "clearLoadedModel", "isModelLoaded:false"]
        )
    }

    func testDeletedNonCurrentModelPlanPreservesSelectionAndLocalWhisperRuntime() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "parakeet-tdt-0.6b-v2"
        )

        XCTAssertEqual(transcriptionModelDeletionEvents(for: plan), [])
    }

    private func localWhisperRuntimeUpdateEvents(for update: VoiceInkLocalWhisperRuntimeUpdate) -> [String] {
        var events: [String] = []

        update.applyRuntimeState(
            clearLoadedModel: { events.append("clearLoadedModel") },
            setIsModelLoaded: { events.append("isModelLoaded:\($0)") }
        )

        return events
    }

    private func transcriptionModelDeletionEvents(for plan: VoiceInkTranscriptionModelDeletionPlan) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            clearCurrentModel: { events.append("clearCurrentModel") },
            applyLocalWhisperRuntimeUpdate: {
                events.append(contentsOf: localWhisperRuntimeUpdateEvents(for: $0))
            }
        )

        return events
    }

    func testModelPrewarmSamplePolicyPreservesMacOSLookupOrder() {
        XCTAssertEqual(
            VoiceInkModelPrewarmSamplePolicy.lookupCandidates,
            [
                VoiceInkModelPrewarmSampleResource(
                    name: "sound7",
                    fileExtension: "wav",
                    subdirectory: "Resources/Sounds"
                ),
                VoiceInkModelPrewarmSampleResource(
                    name: "sound7",
                    fileExtension: "wav",
                    subdirectory: "Sounds"
                ),
                VoiceInkModelPrewarmSampleResource(
                    name: "sound7",
                    fileExtension: "wav",
                    subdirectory: nil
                )
            ]
        )

        let secondCandidateURL = URL(fileURLWithPath: "/tmp/sound7.wav")
        let resolvedURL = VoiceInkModelPrewarmSamplePolicy.firstAvailableURL { resource in
            resource.subdirectory == "Sounds" ? secondCandidateURL : nil
        }

        XCTAssertEqual(resolvedURL, secondCandidateURL)
    }

    func testModelPrewarmPlanPreservesMacOSSkipOrderAndDiagnostics() {
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: false,
                hasCurrentModel: false,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).skipReason,
            .disabledByUser
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).skipReason,
            .missingCurrentModel
        )
        XCTAssertNil(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).diagnosticMessage
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).diagnosticMessage,
            "Skipping prewarm - cloud models don't need it"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: true,
                hasSampleAudio: false
            ).diagnosticMessage,
            "❌ Prewarm audio file (sound7.wav) not found"
        )

        XCTAssertTrue(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: true,
                hasSampleAudio: true
            ).shouldRun
        )
    }

    func testWhisperModelWarmupPolicySchedulesOnlyCoreMLModelsNotAlreadyWarming() {
        XCTAssertTrue(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: false,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: true
            )
        )
    }

    func testModelPrewarmDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.initializedMessage,
            "ModelPrewarmService initialized - listening for wake and app launch"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.appLaunchScheduledMessage,
            "App launched, scheduling prewarm"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.macActivityScheduledMessage,
            "Mac activity detected (wake/unlock), scheduling prewarm"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: "Base"),
            "Prewarming Base"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.completedMessage(duration: 1.234),
            "Prewarm completed in 1.23s"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: "timeout"),
            "❌ Prewarm failed: timeout"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelWarmupDiagnostics.failedMessage(
                modelName: "base",
                errorDescription: "bad file"
            ),
            "❌ Warmup failed for base: bad file"
        )
    }

    func testModelManagementFiltersPreservePlatformTitles() {
        XCTAssertEqual(
            VoiceInkModelManagementFilter.allCases.map(\.title),
            ["Recommended", "Local", "Cloud", "Custom"]
        )
        XCTAssertEqual(VoiceInkModelManagementFilter.local.settingsSectionTitle, "Local Models")
        XCTAssertEqual(VoiceInkModelManagementFilter.local.manageSettingsTitle, "Manage Local Models")
        XCTAssertEqual(VoiceInkModelManagementFilter.cloud.settingsSectionTitle, "Cloud Models")
        XCTAssertEqual(VoiceInkModelManagementFilter.cloud.manageSettingsTitle, "Manage Cloud Models")
    }

    func testModelManagementFiltersApplySharedModelFacts() {
        let models = [
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "custom-api", category: .custom)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testModelManagementRecommendedOrderIsShared() {
        let models = [
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local),
            model(name: "parakeet-tdt-0.6b-v2", category: .local),
            model(name: "ggml-base.en", category: .local),
            model(name: "missing", category: .cloud)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
    }

    func testModelManagementFiltersOwnListFilteringAndRecommendedOrder() {
        let models = [
            model(name: "custom-api", category: .custom),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "parakeet-tdt-0.6b-v2", category: .local)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testModelManagementPresentationPreservesPlatformCopy() {
        XCTAssertEqual(VoiceInkModelManagementPresentation.settingsTitle, "Model Settings")
        XCTAssertEqual(VoiceInkModelManagementPresentation.defaultModelTitle, "Default Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.setAsDefaultButtonTitle, "Set as Default")
        XCTAssertEqual(VoiceInkModelManagementPresentation.downloadButtonTitle, "Download")
        XCTAssertEqual(VoiceInkModelManagementPresentation.editModelButtonTitle, "Edit Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.deleteModelButtonTitle, "Delete Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.deleteButtonTitle, "Delete")
        XCTAssertEqual(VoiceInkModelManagementPresentation.deleteCustomModelAlertTitle, "Delete Custom Model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.showInFinderButtonTitle, "Show in Finder")
        XCTAssertEqual(VoiceInkModelManagementPresentation.speedLabel, "Speed")
        XCTAssertEqual(VoiceInkModelManagementPresentation.accuracyLabel, "Accuracy")
        XCTAssertEqual(VoiceInkModelManagementPresentation.scoreText(8.5), "8.5")
        XCTAssertEqual(VoiceInkModelManagementPresentation.multilingualLanguageLabel, "Multilingual")
        XCTAssertEqual(VoiceInkModelManagementPresentation.englishOnlyLanguageLabel, "English-only")
        XCTAssertEqual(VoiceInkModelManagementPresentation.languageLabel(isMultilingual: true), "Multilingual")
        XCTAssertEqual(VoiceInkModelManagementPresentation.languageLabel(isMultilingual: false), "English-only")
        XCTAssertEqual(VoiceInkModelManagementPresentation.importedLocalModelDescription, "Imported local model")
        XCTAssertEqual(VoiceInkModelManagementPresentation.customProviderLabel, "Custom Provider")
        XCTAssertEqual(VoiceInkModelManagementPresentation.openAICompatibleLabel, "OpenAI Compatible")
        XCTAssertEqual(VoiceInkModelManagementPresentation.nativeAppleProviderLabel, "Native Apple")
        XCTAssertEqual(VoiceInkModelManagementPresentation.onDeviceLabel, "On-Device")
        XCTAssertEqual(VoiceInkModelManagementPresentation.macOS26RequiredLabel, "macOS 26+")
        XCTAssertEqual(VoiceInkModelManagementPresentation.noModelSelectedText, "No model selected")
        XCTAssertEqual(VoiceInkModelManagementPresentation.importLocalModelTitle, "Import Local Model…")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelHelpText,
            "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file."
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelLearnMoreURLString,
            "https://tryvoiceink.com/docs/custom-local-whisper-models"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelLearnMoreHelpText,
            "Read more about custom local models"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importLocalModelPanelTitle,
            "Select a Whisper ggml .bin model"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.customModelsLimitationText,
            "Only OpenAI-compatible transcription APIs are supported."
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.intelMacLocalModelsWarningText,
            "Local models don't work reliably on Intel Macs"
        )
        XCTAssertEqual(VoiceInkModelManagementPresentation.intelMacUseCloudButtonTitle, "Use Cloud")
        XCTAssertEqual(VoiceInkModelManagementPresentation.closeButtonHelp, "Close")
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.deleteCustomModelAlertMessage(displayName: "My Model"),
            "Are you sure you want to delete the custom model 'My Model'?"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.deleteModelAlertMessage(modelName: "ggml-base.en"),
            "Are you sure you want to delete the model 'ggml-base.en'?"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importedLocalModelAlreadyExistsTitle(modelFilename: "custom.bin"),
            "A model named custom.bin already exists"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importedLocalModelSuccessTitle(filename: "custom.bin"),
            "Imported custom.bin"
        )
        XCTAssertEqual(
            VoiceInkModelManagementPresentation.importedLocalModelFailureTitle(errorDescription: "Permission denied"),
            "Failed to import model: Permission denied"
        )
    }

    func testNativeAppleModelMetadataIsShared() {
        let model = VoiceInkTranscriptionModelCatalog.nativeAppleModel

        XCTAssertEqual(model.name, "apple-speech")
        XCTAssertEqual(model.displayName, "Apple Speech")
        XCTAssertEqual(model.description, "Uses the native Apple Speech framework for transcription. Requires macOS 26")
        XCTAssertTrue(model.isMultilingual)
        XCTAssertEqual(model.supportedLanguages["en-US"], "English (United States)")
        XCTAssertNil(model.supportedLanguages["en"])
    }

    func testFluidAudioModelMetadataIsShared() {
        let models = VoiceInkTranscriptionModelCatalog.fluidAudioModels

        XCTAssertEqual(models.map(\.name), ["parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3"])
        XCTAssertEqual(models.map(\.displayName), ["Parakeet V2", "Parakeet V3"])
        XCTAssertEqual(models.map(\.size), ["474 MB", "494 MB"])
        XCTAssertEqual(models.map(\.modelVersion), [.v2, .v3])
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
            "parakeet-tdt-0.6b-v2"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModel.name,
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )
        XCTAssertEqual(VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModel.modelVersion, .v2)
        XCTAssertEqual(models.map(\.supportsStreaming), [true, true])
        XCTAssertEqual(models.map(\.isMultilingual), [false, true])
        XCTAssertEqual(models.first?.supportedLanguages, ["en": "English"])
        XCTAssertEqual(models.last?.supportedLanguages["fr"], "French")
    }

    func testFluidAudioRuntimeVersionAndLanguageHintPolicyIsShared() {
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.fluidAudioModelVersion(forModelName: "parakeet-tdt-0.6b-v2"),
            .v2
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.fluidAudioModelVersion(forModelName: "parakeet-tdt-0.6b-v3"),
            .v3
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.fluidAudioModelVersion(forModelName: "future-parakeet"),
            .v3
        )

        XCTAssertNil(
            VoiceInkTranscriptionModelCatalog.fluidAudioLanguageHintCode(
                from: "fr",
                forModelName: "parakeet-tdt-0.6b-v2"
            )
        )
        XCTAssertNil(
            VoiceInkTranscriptionModelCatalog.fluidAudioLanguageHintCode(
                from: VoiceInkLanguageCatalog.autoDetectCode,
                forModelName: "parakeet-tdt-0.6b-v3"
            )
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.fluidAudioLanguageHintCode(
                from: "fr",
                forModelName: "parakeet-tdt-0.6b-v3"
            ),
            "fr"
        )
    }

    func testDownloadStatusPresentationPreservesFluidAudioDownloadCopy() {
        XCTAssertEqual(VoiceInkFluidAudioDownloadStatus.compactDownloadingStatusText, "Downloading...")

        let preparing = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: -0.2,
            phase: .preparingDownload
        )
        XCTAssertEqual(preparing.fractionCompleted, 0)
        XCTAssertEqual(preparing.message, "Preparing FluidAudio download...")
        XCTAssertEqual(preparing.percent, 0)
        XCTAssertEqual(preparing.percentText, "0%")

        let listing = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.1,
            phase: .listingFiles
        )
        XCTAssertEqual(listing.message, "Listing files from repository...")

        let checkingCache = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.2,
            phase: .checkingCachedModels
        )
        XCTAssertEqual(checkingCache.message, "Checking cached models...")

        let downloading = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.427,
            phase: .downloadingFiles(completedFiles: 3, totalFiles: 7)
        )
        XCTAssertEqual(downloading.message, "Downloading models: 3/7 files")
        XCTAssertEqual(downloading.percent, 42)
        XCTAssertEqual(downloading.percentText, "42%")

        let finalizing = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 1.4,
            phase: .finalizingModels
        )
        XCTAssertEqual(finalizing.fractionCompleted, 1)
        XCTAssertEqual(finalizing.message, "Finalizing models...")
        XCTAssertEqual(finalizing.percentText, "100%")

        let compiling = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.8,
            phase: .compiling(modelComponentName: "Parakeet.mlmodelc")
        )
        XCTAssertEqual(compiling.message, "Compiling Parakeet")
    }

    func testDeepgramLanguageCapabilityIsSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.deepgram.languageCodes?.first, "ar")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.deepgram.languageCodes?.last, "zh")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.deepgram.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.deepgram.includesAutoDetect)
    }

    func testMistralLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.mistral.languageCodes,
            ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
        )
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.mistral.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .mistral)
        XCTAssertEqual(models.map(\.name), ["voxtral-mini-latest"])
        XCTAssertEqual(models.first?.displayName, "Voxtral (Mistral)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testSonioxLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.soniox.languageCodes?.first, "af")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.soniox.languageCodes?.last, "cy")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.soniox.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.soniox.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .soniox)
        XCTAssertEqual(models.map(\.name), ["stt-async-v4"])
        XCTAssertEqual(models.first?.displayName, "Soniox V4")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testSpeechmaticsLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.speechmatics.languageCodes?.first, "ar")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.speechmatics.languageCodes?.last, "zh")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.speechmatics.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.speechmatics.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .speechmatics)
        XCTAssertEqual(models.map(\.name), ["speechmatics-enhanced"])
        XCTAssertEqual(models.first?.displayName, "Speechmatics")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testElevenLabsLanguageCapabilityAndModelsAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.elevenLabs.languageCodes?.first, "af")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.elevenLabs.languageCodes?.last, "zu")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.elevenLabs.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.elevenLabs.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .elevenLabs)
        XCTAssertEqual(models.map(\.name), ["scribe_v1", "scribe_v2"])
        XCTAssertEqual(models.map(\.displayName), ["Scribe v1 (ElevenLabs)", "Scribe V2 (ElevenLabs)"])
        XCTAssertEqual(models.map(\.supportsStreaming), [false, true])
    }

    func testStreamingConnectionModelNamesAreSharedProviderPolicy() {
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.deepgram.streamingConnectionModelName(for: "nova-3"),
            "nova-3"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.assemblyAI.streamingConnectionModelName(for: "universal-3-pro"),
            "universal-3-pro"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.cartesia.streamingConnectionModelName(for: "ink-whisper"),
            "ink-whisper"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.mistral.streamingConnectionModelName(for: "voxtral-mini-latest"),
            "voxtral-mini-transcribe-realtime-2602"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.elevenLabs.streamingConnectionModelName(for: "scribe_v2"),
            "scribe_v2_realtime"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.xai.streamingConnectionModelName(for: "grok-stt"),
            "grok-stt"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.soniox.streamingConnectionModelName(for: "stt-async-v4"),
            "stt-rt-v4"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.speechmatics.streamingConnectionModelName(for: "speechmatics-enhanced"),
            "enhanced"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.speechmatics.streamingConnectionModelName(for: "speechmatics-standard"),
            "standard"
        )
    }

    func testStreamingTimeoutMappingIsSharedProviderPolicy() {
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.assemblyAI.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.deepgram.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.elevenLabs.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.soniox.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.speechmatics.mapsStreamingTransportTimeoutToFinalTimeout)
    }

    func testXAILanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.xai.languageCodes?.first, "ar")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.xai.languageCodes?.last, "vi")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.xai.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.xai.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .xai)
        XCTAssertEqual(models.map(\.name), ["grok-stt"])
        XCTAssertEqual(models.first?.displayName, "Grok (xAI)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testCartesiaLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.cartesia.languageCodes?.first, "af")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.cartesia.languageCodes?.last, "zu")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.cartesia.languageCodes?.contains("en") == true)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.cartesia.includesAutoDetect)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.cartesia.supportsRecordedFileTranscription)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .cartesia)
        XCTAssertEqual(models.map(\.name), ["ink-whisper"])
        XCTAssertEqual(models.first?.displayName, "Ink Whisper (Cartesia)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testRecordedFileSupportIsSharedProviderCapability() {
        let streamingOnlyProviders = VoiceInkTranscriptionModelProvider.allCases.filter {
            !$0.supportsRecordedFileTranscription
        }
        let streamingOnlyModelProviders = VoiceInkTranscriptionModelProvider.allCases.filter(\.isStreamingOnly)

        XCTAssertEqual(streamingOnlyProviders, [.cartesia])
        XCTAssertEqual(streamingOnlyModelProviders, [.cartesia])
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.groq.supportsRecordedFileTranscription)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.groq.isStreamingOnly)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.local.supportsRecordedFileTranscription)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.local.isStreamingOnly)
    }

    func testProviderRoleOwnsModelCategoryRouteAvailabilityAndLanguageSource() {
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.transcriptionServiceRoute, .localWhisper)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.transcriptionModelAvailabilityRequirement, .downloadedLocalWhisperModel)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.transcriptionLanguageSource, .whisper)
        XCTAssertNil(VoiceInkTranscriptionModelProviderRole.localWhisper.coreTranscriptionModelProvider)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.transcriptionServiceRoute, .localFluidAudio)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.transcriptionModelAvailabilityRequirement, .downloadedLocalFluidAudioModel)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.transcriptionLanguageSource, .fluidAudio)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.transcriptionServiceRoute, .nativeApple)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.transcriptionModelAvailabilityRequirement, .currentOSSupport)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.transcriptionLanguageSource, .nativeApple)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.modelManagementCategory, .custom)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionServiceRoute, .cloud)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionModelAvailabilityRequirement, .alwaysAvailable)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionLanguageSource, .all)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).modelManagementCategory, .cloud)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).transcriptionServiceRoute, .cloud)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).transcriptionModelAvailabilityRequirement, .configuredAPIKey)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).transcriptionLanguageSource, .provider(.groq))
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).coreTranscriptionModelProvider, .groq)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(nil).transcriptionModelAvailabilityRequirement, .unavailable)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(nil).transcriptionLanguageSource, .all)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).apiKeyProviderName(defaultName: "Groq"), "Groq")
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.apiKeyProviderName(defaultName: "Custom"), "Custom")
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.localWhisper.supportsRecordedFileTranscription)
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.customCloud.supportsRecordedFileTranscription)
        XCTAssertFalse(VoiceInkTranscriptionModelProviderRole.cloud(.cartesia).supportsRecordedFileTranscription)
        XCTAssertFalse(VoiceInkTranscriptionModelProviderRole.localWhisper.isStreamingOnly)
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.cloud(.cartesia).isStreamingOnly)
        XCTAssertEqual(
            VoiceInkTranscriptionModelProviderRole.cloud(.speechmatics).streamingConnectionModelName(for: "speechmatics-standard"),
            "standard"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProviderRole.customCloud.streamingConnectionModelName(for: "custom-model"),
            "custom-model"
        )
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.cloud(.assemblyAI).mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(VoiceInkTranscriptionModelProviderRole.cloud(.deepgram).mapsStreamingTransportTimeoutToFinalTimeout)

        let customLanguages = ["zz": "Customish"]
        XCTAssertEqual(
            VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionLanguageOptions(
                defaultLanguages: customLanguages,
                isMultilingual: true,
                usesRealtimeProviderLanguages: true
            ),
            customLanguages
        )
        XCTAssertNil(VoiceInkTranscriptionModelProviderRole.cloud(.assemblyAI).transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: true
        )["en_uk"])
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.assemblyAI).transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: false
        )["en_uk"], "British English")
    }

    func testMacOSTranscriptionModelProviderPreservesRawValuesAndLegacyLocalDecode() throws {
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.allCases.map(\.rawValue),
            [
                "Whisper",
                "Parakeet",
                "Groq",
                "ElevenLabs",
                "Deepgram",
                "Mistral",
                "Gemini",
                "Soniox",
                "Speechmatics",
                "AssemblyAI",
                "xAI",
                "Cartesia",
                "Custom",
                "Native Apple"
            ]
        )

        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(VoiceInkMacOSTranscriptionModelProvider.self, from: Data(#""Local""#.utf8)),
            .whisper
        )
        XCTAssertEqual(
            try decoder.decode(VoiceInkMacOSTranscriptionModelProvider.self, from: Data(#""Parakeet""#.utf8)),
            .fluidAudio
        )

        do {
            _ = try decoder.decode(VoiceInkMacOSTranscriptionModelProvider.self, from: Data(#""Unknown""#.utf8))
            XCTFail("Unknown macOS transcription model provider raw value should throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMacOSTranscriptionModelProviderRoleMappingIsShared() {
        let expectedRoles: [(VoiceInkMacOSTranscriptionModelProvider, VoiceInkTranscriptionModelProviderRole)] = [
            (.whisper, .localWhisper),
            (.fluidAudio, .localFluidAudio),
            (.nativeApple, .nativeApple),
            (.custom, .customCloud),
            (.groq, .cloud(.groq)),
            (.deepgram, .cloud(.deepgram)),
            (.elevenLabs, .cloud(.elevenLabs)),
            (.mistral, .cloud(.mistral)),
            (.gemini, .cloud(.gemini)),
            (.soniox, .cloud(.soniox)),
            (.speechmatics, .cloud(.speechmatics)),
            (.assemblyAI, .cloud(.assemblyAI)),
            (.xai, .cloud(.xai)),
            (.cartesia, .cloud(.cartesia))
        ]

        for (provider, role) in expectedRoles {
            XCTAssertEqual(provider.coreTranscriptionModelProviderRole, role)
        }

        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.groq.coreTranscriptionModelProvider, .groq)
        XCTAssertNil(VoiceInkMacOSTranscriptionModelProvider.whisper.coreTranscriptionModelProvider)
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.groq.remoteTranscriptionProviderKind, .groq)
        XCTAssertNil(VoiceInkMacOSTranscriptionModelProvider.whisper.remoteTranscriptionProviderKind)
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.groq.apiErrorDomain, "GroqAPI")
        XCTAssertNil(VoiceInkMacOSTranscriptionModelProvider.whisper.apiErrorDomain)
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.cartesia.apiKeyProviderName, "Cartesia")
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.custom.apiKeyProviderName, "Custom")
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.deepgram.languageCodes?.first, "ar")
        XCTAssertTrue(VoiceInkMacOSTranscriptionModelProvider.deepgram.includesAutoDetect)
        XCTAssertFalse(VoiceInkMacOSTranscriptionModelProvider.groq.includesAutoDetect)
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.groq.cloudModelSpecs.map(\.name),
            VoiceInkTranscriptionModelCatalog.cloudModels(for: .groq).map(\.name)
        )
        XCTAssertTrue(VoiceInkMacOSTranscriptionModelProvider.whisper.cloudModelSpecs.isEmpty)
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.soniox.remoteTranscriptionOptions(
                prompt: "ignored",
                customVocabulary: [" Roma ", "Felix", "roma", ""]
            ).customVocabulary,
            ["Roma", "Felix"]
        )
        XCTAssertFalse(VoiceInkMacOSTranscriptionModelProvider.soniox.acceptsRemoteTranscriptionText(" \n\t "))
        XCTAssertTrue(VoiceInkMacOSTranscriptionModelProvider.mistral.acceptsRemoteTranscriptionText(""))
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.whisper.transcriptionLanguageSource, .whisper)
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.custom.transcriptionLanguageSource, .all)
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.fluidAudio.supportedLanguages(isMultilingual: false),
            VoiceInkLanguageCatalog.englishOnly
        )
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.custom.transcriptionLanguageOptions(
                defaultLanguages: ["custom": "Custom"],
                isMultilingual: false,
                usesRealtimeProviderLanguages: false
            ),
            ["custom": "Custom"]
        )
        XCTAssertNil(VoiceInkMacOSTranscriptionModelProvider.assemblyAI.transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: true
        )["en_uk"])
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.nativeApple.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.custom.transcriptionServiceRoute, .cloud)
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.nativeApple.transcriptionModelAvailabilityRequirement,
            .currentOSSupport
        )
        XCTAssertTrue(VoiceInkMacOSTranscriptionModelProvider.whisper.supportsRecordedFileTranscription)
        XCTAssertTrue(VoiceInkMacOSTranscriptionModelProvider.cartesia.isStreamingOnly)
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.elevenLabs.streamingConnectionModelName(for: "scribe_v1"),
            "scribe_v2_realtime"
        )
        XCTAssertTrue(VoiceInkMacOSTranscriptionModelProvider.assemblyAI.mapsStreamingTransportTimeoutToFinalTimeout)
    }

    func testMacOSTranscriptionModelFactsDeriveSharedModelPolicy() {
        let streamingFacts = VoiceInkMacOSTranscriptionModelFacts(
            name: "scribe_v1",
            provider: .elevenLabs,
            isMultilingual: true,
            supportedLanguages: ["fallback": "Fallback"],
            supportsStreaming: true
        )
        let streamingSnapshot = VoiceInkTranscriptionStreamingModelSnapshot(
            name: "scribe_v1",
            supportsStreaming: true
        )

        XCTAssertTrue(streamingFacts.supportsRecordedFileTranscription)
        XCTAssertEqual(streamingFacts.streamingPreferenceSnapshot, streamingSnapshot)
        XCTAssertEqual(
            streamingFacts.transcriptionSessionRouteFacts,
            VoiceInkTranscriptionSessionRouteFacts(
                serviceRoute: .cloud,
                streamingSnapshot: streamingSnapshot
            )
        )
        XCTAssertEqual(streamingFacts.streamingConnectionModelName, "scribe_v2_realtime")
        XCTAssertFalse(streamingFacts.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertEqual(
            streamingFacts.transcriptionRuntimeResourcePlan,
            VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        )
        XCTAssertEqual(
            streamingFacts.transcriptionModelAvailabilityFacts(hasConfiguredAPIKey: true),
            VoiceInkTranscriptionModelAvailabilityFacts(
                requirement: .configuredAPIKey,
                hasConfiguredAPIKey: true
            )
        )

        let customLanguages = ["custom": "Custom"]
        let customFacts = VoiceInkMacOSTranscriptionModelFacts(
            name: "custom-model",
            provider: .custom,
            isMultilingual: false,
            supportedLanguages: customLanguages,
            supportsStreaming: false
        )

        XCTAssertEqual(customFacts.transcriptionLanguageOptions, customLanguages)
        XCTAssertEqual(
            customFacts.transcriptionLanguageSelectionFacts,
            VoiceInkTranscriptionLanguageSelectionFacts(
                source: .all,
                isMultilingual: false,
                languageOptions: customLanguages
            )
        )
        XCTAssertEqual(
            customFacts.powerModeTranscriptionModelFacts,
            VoiceInkPowerModeTranscriptionModelFacts(
                name: "custom-model",
                languageSource: .all,
                isMultilingual: false,
                languageOptions: customLanguages
            )
        )
        XCTAssertEqual(
            customFacts.powerModeTranscriptionModelResourceFacts,
            VoiceInkPowerModeTranscriptionModelResourceFacts(name: "custom-model", languageSource: .all)
        )
        XCTAssertEqual(
            customFacts.modelManagementFacts(isAvailableOnCurrentOS: false),
            VoiceInkModelManagementModelFacts(
                name: "custom-model",
                category: .custom,
                isAvailableOnCurrentOS: false
            )
        )
    }

    func testProviderAPIErrorDomainsPreserveMacOSBatchMapping() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.groq.apiErrorDomain, "GroqAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.deepgram.apiErrorDomain, "DeepgramAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.gemini.apiErrorDomain, "GeminiAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.mistral.apiErrorDomain, "MistralAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.elevenLabs.apiErrorDomain, "ElevenLabsAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.soniox.apiErrorDomain, "SonioxAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.speechmatics.apiErrorDomain, "SpeechmaticsAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.assemblyAI.apiErrorDomain, "AssemblyAIAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.xai.apiErrorDomain, "XAIAPI")
        XCTAssertNil(VoiceInkTranscriptionModelProvider.cartesia.apiErrorDomain)
        XCTAssertNil(VoiceInkTranscriptionModelProvider.local.apiErrorDomain)
    }

    func testRequiredProviderAPIErrorDomainsMatchSharedMapping() {
        let providers: [VoiceInkTranscriptionModelProvider] = [
            .groq,
            .deepgram,
            .gemini,
            .mistral,
            .elevenLabs,
            .soniox,
            .speechmatics,
            .assemblyAI,
            .xai
        ]

        for provider in providers {
            XCTAssertEqual(provider.requiredAPIErrorDomain, provider.apiErrorDomain)
        }
    }

    func testAssemblyAILanguageCapabilityAndModelsAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.assemblyAI.languageCodes, ["en", "es", "de", "fr", "pt", "it"])
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.assemblyAI.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .assemblyAI)
        XCTAssertEqual(models.map(\.name), ["universal-3-pro", "universal-streaming"])
        XCTAssertEqual(models.map(\.displayName), ["Universal-3 Pro (AssemblyAI)", "Universal-2 (AssemblyAI)"])
        XCTAssertEqual(models.map(\.supportsStreaming), [true, true])
    }

    func testOpenAICompatibleProvidersUseAllLanguagesWithoutAutoDetectFlag() {
        XCTAssertNil(VoiceInkTranscriptionModelProvider.groq.languageCodes)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.groq.includesAutoDetect)
        XCTAssertNil(VoiceInkTranscriptionModelProvider.gemini.languageCodes)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.gemini.includesAutoDetect)
    }

    func testProviderKindExposesTranscriptionLanguageCapabilityMetadata() {
        let expected: [VoiceInkProviderKind: VoiceInkTranscriptionModelProvider] = [
            .deepgram: .deepgram,
            .mistral: .mistral,
            .elevenLabs: .elevenLabs,
            .soniox: .soniox,
            .speechmatics: .speechmatics,
            .assemblyAI: .assemblyAI,
            .xai: .xai
        ]

        for (provider, modelProvider) in expected {
            XCTAssertEqual(provider.transcriptionModelProvider?.languageCodes, modelProvider.languageCodes)
            XCTAssertEqual(provider.transcriptionModelProvider?.includesAutoDetect, modelProvider.includesAutoDetect)
        }
    }

    func testMovedWhisperModelManagementSymbolsExposePublicAPI() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let modelsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels", isDirectory: true)

        let progress = VoiceInkWhisperModelDownloadProgress.simple(
            modelName: model.modelName,
            isDownloading: true,
            progress: 0.42
        )
        XCTAssertTrue(progress.isActive)
        XCTAssertEqual(progress.compactStatusText, "Downloading...")
        XCTAssertEqual(progress.percentText, "42%")

        let state = VoiceInkWhisperModelDownloadState(isDownloaded: false, progress: progress)
        let row = state.rowPresentation(for: model)
        XCTAssertEqual(row.downloadButtonTitle, "Download Model (142 MB)")
        XCTAssertTrue(row.shouldShowCircularProgressAccessory)

        let managementRow = VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: state
        )
        XCTAssertNil(managementRow.confirmedDownloadRuntimeAction {})
        XCTAssertEqual(managementRow.downloadConfirmation.primaryButtonTitle, "Download")
        XCTAssertEqual(managementRow.deleteConfirmation.primaryButtonTitle, "Delete")

        let completionPlan = VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
            temporaryURL: nil,
            response: nil,
            error: nil
        )
        var failureID = ""
        completionPlan.applyRuntimeState(
            installTemporaryFile: { _ in XCTFail("missing file should not install") },
            presentFailure: { failureID = $0.id },
            ignoreCancellation: { XCTFail("missing file should not cancel") }
        )
        XCTAssertEqual(failureID, "serverErrorDuringDownload")

        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()
        XCTAssertTrue(trackingState.startDownload(for: model))
        trackingState.updateProgress(0.5, for: model)

        var sessionState = VoiceInkWhisperModelSimpleDownloadSessionState(
            downloadTrackingState: trackingState
        )
        XCTAssertNil(sessionState.startDownload(for: model))
        XCTAssertTrue(sessionState.isDownloading(model))

        let snapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        )
        XCTAssertFalse(snapshot.hasAvailableModel())
        XCTAssertNil(snapshot.modelPath(forRuntimeModelName: model.modelName))
        XCTAssertEqual(snapshot.managementRows().count, VoiceInkWhisperModelFiles.bootstrapModels.count)

        let deletionPlan = VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: false)
        var skippedMissingFile = false
        deletionPlan.applyRuntimeState(
            skipMissingFile: { skippedMissingFile = true },
            deleteDownloadedFiles: { XCTFail("missing file should not delete") },
            refreshAfterSuccessfulDelete: { XCTFail("missing file should not refresh") },
            handleDeleteFailure: { _ in XCTFail("missing file should not fail") }
        )
        XCTAssertTrue(skippedMissingFile)

        XCTAssertEqual(
            VoiceInkWhisperModelOperationConfirmationPresentation.download(for: model).title,
            "Download Model"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelOperationAlertPresentation.noFileReceived.message,
            "No file received"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.alreadyDownloadingMessage(modelName: model.modelName),
            "Model \(model.modelName) is already being downloaded."
        )
    }

    private func model(
        name: String,
        category: VoiceInkModelManagementModelCategory,
        isAvailableOnCurrentOS: Bool = true
    ) -> ModelManagementFilterFixture {
        ModelManagementFilterFixture(
            facts: VoiceInkModelManagementModelFacts(
                name: name,
                category: category,
                isAvailableOnCurrentOS: isAvailableOnCurrentOS
            )
        )
    }
}

private struct ModelManagementFilterFixture {
    let facts: VoiceInkModelManagementModelFacts
}
