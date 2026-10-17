import Foundation
import RomaCore

final class TranscriptionModelCatalogTests: XCTestCase {
    func testAvailabilityRequirementPredicatesIdentifyShellFactsNeeded() {
        XCTAssertTrue(RomaTranscriptionModelAvailabilityRequirement.configuredAPIKey.requiresConfiguredAPIKey)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityRequirement.configuredAPIKey.requiresCurrentOSSupport)
        XCTAssertTrue(RomaTranscriptionModelAvailabilityRequirement.currentOSSupport.requiresCurrentOSSupport)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityRequirement.currentOSSupport.requiresConfiguredAPIKey)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityRequirement.downloadedLocalWhisperModel.requiresConfiguredAPIKey)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityRequirement.downloadedLocalWhisperModel.requiresCurrentOSSupport)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityRequirement.alwaysAvailable.requiresConfiguredAPIKey)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityRequirement.unavailable.requiresCurrentOSSupport)
    }

    func testConfiguredAPIKeyRequirementUsesConfiguredKeyFact() {
        XCTAssertTrue(RomaTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: true
        ).isUsable)

        XCTAssertFalse(RomaTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: false
        ).isUsable)
    }

    func testCurrentOSRequirementUsesCurrentOSFact() {
        XCTAssertTrue(RomaTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: true
        ).isUsable)

        XCTAssertFalse(RomaTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: false
        ).isUsable)
    }

    func testLocalModelRequirementsUseDownloadedFacts() {
        XCTAssertTrue(RomaTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: false
        ).isUsable)

        XCTAssertTrue(RomaTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: false
        ).isUsable)
    }

    func testQwenNeedsInstalledModelAndSupportedHardware() {
        for installed in [false, true] {
            for supported in [false, true] {
                let facts = RomaTranscriptionModelAvailabilityFacts(
                    requirement: .downloadedLocalQwenModel,
                    hasConfiguredAPIKey: true,
                    isAvailableOnCurrentOS: supported,
                    isLocalFluidAudioModelDownloaded: true,
                    isLocalQwenModelDownloaded: installed
                )
                XCTAssertEqual(facts.isUsable, installed && supported)
            }
        }
    }

    func testQwenRoutesAndLanguagesStayLocalAndRespectEnglishChoice() async {
        let provider = RomaMacOSTranscriptionModelProvider.qwen
        XCTAssertNil(provider.remoteTranscriptionProviderKind)
        XCTAssertEqual(provider.modelManagementCategory, .local)
        XCTAssertEqual(provider.transcriptionServiceRoute, .localQwen)
        XCTAssertFalse(provider.transcriptionModelAvailabilityRequirement.requiresConfiguredAPIKey)
        XCTAssertTrue(provider.transcriptionModelAvailabilityRequirement.requiresCurrentOSSupport)
        let languages = provider.supportedLanguages(isMultilingual: true)
        XCTAssertEqual(Set(languages.keys), Set(["auto", "en", "zh"]))
        XCTAssertEqual(RomaTranscriptionLanguageSupport.validLanguageOrFallback(nil, source: .qwen), "auto")
        XCTAssertEqual(RomaTranscriptionLanguageSupport.validLanguageOrFallback("en", source: .qwen), "en")
        XCTAssertEqual(RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName, "parakeet-tdt-0.6b-v2")
        let streaming = RomaTranscriptionSessionRoutePlan(serviceRoute: .localQwen, usesStreaming: true)
        XCTAssertEqual(streaming.streamingAdapterKind, .localQwen)
        XCTAssertEqual(streaming.finalCommitSource, .localQwen)
        let batch = RomaTranscriptionSessionRoutePlan(serviceRoute: .localQwen, usesStreaming: false)
        XCTAssertNil(batch.streamingAdapterKind)
        let resource = RomaTranscriptionRuntimeResourcePlan(serviceRoute: .localQwen)
        var calls: [String] = []
        await resource.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: { calls.append("whisper") },
            loadLocalFluidAudioModel: { calls.append("fluid") },
            loadLocalQwenModel: { calls.append("qwen") }
        )
        XCTAssertEqual(calls, ["qwen"])
        XCTAssertTrue(resource.shouldPrewarmModel)
    }

    func testAlwaysAvailableAndUnavailableRequirementsStayExplicit() {
        XCTAssertTrue(RomaTranscriptionModelAvailabilityFacts(requirement: .alwaysAvailable).isUsable)
        XCTAssertFalse(RomaTranscriptionModelAvailabilityFacts(requirement: .unavailable).isUsable)
    }

    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() async {
        let plan = RomaTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            },
            loadLocalQwenModel: { events.append("qwen") }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["whisper"])
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() async {
        let plan = RomaTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            },
            loadLocalQwenModel: { events.append("qwen") }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["fluid"])
    }

    func testCloudRouteSkipsLocalRuntimeWork() async {
        let plan = RomaTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            },
            loadLocalQwenModel: { events.append("qwen") }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() async {
        let plan = RomaTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            },
            loadLocalQwenModel: { events.append("qwen") }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testModelSelectionResourcePlanOwnsLocalWhisperRuntimeUpdate() {
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: RomaTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
                .modelSelectionLocalWhisperRuntimeUpdate),
            []
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: RomaTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: RomaTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: RomaTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
    }

    func testDeletedCurrentModelPlanClearsSelectionAndMarksLocalWhisperUnloaded() {
        let plan = RomaTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "ggml-base.en"
        )

        XCTAssertEqual(
            transcriptionModelDeletionEvents(for: plan),
            ["clearCurrentModel", "clearLoadedModel", "isModelLoaded:false"]
        )
    }

    func testDeletedNonCurrentModelPlanPreservesSelectionAndLocalWhisperRuntime() {
        let plan = RomaTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "parakeet-tdt-0.6b-v2"
        )

        XCTAssertEqual(transcriptionModelDeletionEvents(for: plan), [])
    }

    private func localWhisperRuntimeUpdateEvents(for update: RomaLocalWhisperRuntimeUpdate) -> [String] {
        var events: [String] = []

        update.applyRuntimeState(
            clearLoadedModel: { events.append("clearLoadedModel") },
            setIsModelLoaded: { events.append("isModelLoaded:\($0)") }
        )

        return events
    }

    private func transcriptionModelDeletionEvents(for plan: RomaTranscriptionModelDeletionPlan) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            clearCurrentModel: { events.append("clearCurrentModel") },
            applyLocalWhisperRuntimeUpdate: {
                events.append(contentsOf: localWhisperRuntimeUpdateEvents(for: $0))
            }
        )

        return events
    }

    func testModelPrewarmUsesOneSecondMono16kSilence() {
        XCTAssertEqual(
            RomaModelPrewarmSamplePolicy.generatedSilenceSampleCount,
            RomaPCM16Audio.mono16kSampleRateHz
        )
    }

    func testWhisperModelPrewarmOnlyReusesMatchingLoadedContext() {
        XCTAssertTrue(
            RomaWhisperModelLoadPolicy.shouldReuseLoadedContext(
                hasContext: true,
                loadedModelName: "ggml-base.en.bin",
                requestedModelName: "ggml-base.en.bin"
            )
        )
        XCTAssertFalse(
            RomaWhisperModelLoadPolicy.shouldReuseLoadedContext(
                hasContext: false,
                loadedModelName: "ggml-base.en.bin",
                requestedModelName: "ggml-base.en.bin"
            )
        )
        XCTAssertFalse(
            RomaWhisperModelLoadPolicy.shouldReuseLoadedContext(
                hasContext: true,
                loadedModelName: "ggml-base.en.bin",
                requestedModelName: "ggml-small.en.bin"
            )
        )
    }

    func testModelPrewarmPlanUsesRuntimeAvailabilityWithoutAudioFixture() {
        XCTAssertEqual(
            RomaModelPrewarmPlan.plan(
                isEnabled: false,
                hasCurrentModel: false,
                shouldPrewarmModel: false
            ).skipReason,
            .disabledByUser
        )
        XCTAssertEqual(
            RomaModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false
            ).skipReason,
            .missingCurrentModel
        )
        XCTAssertNil(
            RomaModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false
            ).diagnosticMessage
        )
        XCTAssertEqual(
            RomaModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: false
            ).diagnosticMessage,
            "Skipping prewarm - cloud models don't need it"
        )

        XCTAssertTrue(
            RomaModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: true
            ).shouldRun
        )
    }

    func testWhisperModelWarmupPolicySchedulesOnlyCoreMLModelsNotAlreadyWarming() {
        XCTAssertTrue(
            RomaWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            RomaWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: false,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            RomaWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: true
            )
        )
    }

    func testModelManagementFiltersApplySharedModelFacts() {
        let models = [
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "custom-api", category: .custom)
        ]

        XCTAssertEqual(
            RomaModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            RomaModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en"]
        )
        XCTAssertEqual(
            RomaModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            RomaModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
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
            RomaModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            RomaModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2"]
        )
        XCTAssertEqual(
            RomaModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            RomaModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testMistralLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(
            RomaTranscriptionModelProvider.mistral.languageCodes,
            ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
        )
        XCTAssertTrue(RomaTranscriptionModelProvider.mistral.includesAutoDetect)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .mistral)
        XCTAssertEqual(models.map(\.name), ["voxtral-mini-latest"])
        XCTAssertEqual(models.first?.displayName, "Voxtral (Mistral)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testSonioxLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(RomaTranscriptionModelProvider.soniox.languageCodes?.first, "af")
        XCTAssertEqual(RomaTranscriptionModelProvider.soniox.languageCodes?.last, "cy")
        XCTAssertTrue(RomaTranscriptionModelProvider.soniox.languageCodes?.contains("en") == true)
        XCTAssertTrue(RomaTranscriptionModelProvider.soniox.includesAutoDetect)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .soniox)
        XCTAssertEqual(models.map(\.name), ["stt-async-v4"])
        XCTAssertEqual(models.first?.displayName, "Soniox V4")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testSpeechmaticsLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(RomaTranscriptionModelProvider.speechmatics.languageCodes?.first, "ar")
        XCTAssertEqual(RomaTranscriptionModelProvider.speechmatics.languageCodes?.last, "zh")
        XCTAssertTrue(RomaTranscriptionModelProvider.speechmatics.languageCodes?.contains("en") == true)
        XCTAssertTrue(RomaTranscriptionModelProvider.speechmatics.includesAutoDetect)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .speechmatics)
        XCTAssertEqual(models.map(\.name), ["speechmatics-enhanced"])
        XCTAssertEqual(models.first?.displayName, "Speechmatics")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testElevenLabsLanguageCapabilityAndModelsAreSharedProviderMetadata() {
        XCTAssertEqual(RomaTranscriptionModelProvider.elevenLabs.languageCodes?.first, "af")
        XCTAssertEqual(RomaTranscriptionModelProvider.elevenLabs.languageCodes?.last, "zu")
        XCTAssertTrue(RomaTranscriptionModelProvider.elevenLabs.languageCodes?.contains("en") == true)
        XCTAssertTrue(RomaTranscriptionModelProvider.elevenLabs.includesAutoDetect)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .elevenLabs)
        XCTAssertEqual(models.map(\.name), ["scribe_v1", "scribe_v2"])
        XCTAssertEqual(models.map(\.displayName), ["Scribe v1 (ElevenLabs)", "Scribe V2 (ElevenLabs)"])
        XCTAssertEqual(models.map(\.supportsStreaming), [false, true])
    }

    func testStreamingConnectionModelNamesAreSharedProviderPolicy() {
        XCTAssertEqual(
            RomaTranscriptionModelProvider.deepgram.streamingConnectionModelName(for: "nova-3"),
            "nova-3"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.assemblyAI.streamingConnectionModelName(for: "universal-3-pro"),
            "universal-3-pro"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.cartesia.streamingConnectionModelName(for: "ink-whisper"),
            "ink-whisper"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.mistral.streamingConnectionModelName(for: "voxtral-mini-latest"),
            "voxtral-mini-transcribe-realtime-2602"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.elevenLabs.streamingConnectionModelName(for: "scribe_v2"),
            "scribe_v2_realtime"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.xai.streamingConnectionModelName(for: "grok-stt"),
            "grok-stt"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.soniox.streamingConnectionModelName(for: "stt-async-v4"),
            "stt-rt-v4"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.speechmatics.streamingConnectionModelName(for: "speechmatics-enhanced"),
            "enhanced"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProvider.speechmatics.streamingConnectionModelName(for: "speechmatics-standard"),
            "standard"
        )
    }

    func testXAILanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(RomaTranscriptionModelProvider.xai.languageCodes?.first, "ar")
        XCTAssertEqual(RomaTranscriptionModelProvider.xai.languageCodes?.last, "vi")
        XCTAssertTrue(RomaTranscriptionModelProvider.xai.languageCodes?.contains("en") == true)
        XCTAssertTrue(RomaTranscriptionModelProvider.xai.includesAutoDetect)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .xai)
        XCTAssertEqual(models.map(\.name), ["grok-stt"])
        XCTAssertEqual(models.first?.displayName, "Grok (xAI)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testCartesiaLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(RomaTranscriptionModelProvider.cartesia.languageCodes?.first, "af")
        XCTAssertEqual(RomaTranscriptionModelProvider.cartesia.languageCodes?.last, "zu")
        XCTAssertTrue(RomaTranscriptionModelProvider.cartesia.languageCodes?.contains("en") == true)
        XCTAssertFalse(RomaTranscriptionModelProvider.cartesia.includesAutoDetect)
        XCTAssertFalse(RomaTranscriptionModelProvider.cartesia.supportsRecordedFileTranscription)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .cartesia)
        XCTAssertEqual(models.map(\.name), ["ink-whisper"])
        XCTAssertEqual(models.first?.displayName, "Ink Whisper (Cartesia)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testProviderRoleOwnsModelCategoryRouteAvailabilityAndLanguageSource() {
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localWhisper.modelManagementCategory, .local)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localWhisper.transcriptionServiceRoute, .localWhisper)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localWhisper.transcriptionModelAvailabilityRequirement, .downloadedLocalWhisperModel)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localWhisper.transcriptionLanguageSource, .whisper)
        XCTAssertNil(RomaTranscriptionModelProviderRole.localWhisper.coreTranscriptionModelProvider)

        XCTAssertEqual(RomaTranscriptionModelProviderRole.localFluidAudio.modelManagementCategory, .local)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localFluidAudio.transcriptionServiceRoute, .localFluidAudio)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localFluidAudio.transcriptionModelAvailabilityRequirement, .downloadedLocalFluidAudioModel)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.localFluidAudio.transcriptionLanguageSource, .fluidAudio)

        XCTAssertEqual(RomaTranscriptionModelProviderRole.nativeApple.modelManagementCategory, .local)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.nativeApple.transcriptionServiceRoute, .nativeApple)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.nativeApple.transcriptionModelAvailabilityRequirement, .currentOSSupport)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.nativeApple.transcriptionLanguageSource, .nativeApple)

        XCTAssertEqual(RomaTranscriptionModelProviderRole.customCloud.modelManagementCategory, .custom)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.customCloud.transcriptionServiceRoute, .cloud)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.customCloud.transcriptionModelAvailabilityRequirement, .alwaysAvailable)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.customCloud.transcriptionLanguageSource, .all)

        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.groq).modelManagementCategory, .cloud)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.groq).transcriptionServiceRoute, .cloud)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.groq).transcriptionModelAvailabilityRequirement, .configuredAPIKey)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.groq).transcriptionLanguageSource, .provider(.groq))
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.groq).coreTranscriptionModelProvider, .groq)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(nil).transcriptionModelAvailabilityRequirement, .unavailable)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(nil).transcriptionLanguageSource, .all)
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.groq).apiKeyProviderName(defaultName: "Groq"), "Groq")
        XCTAssertEqual(RomaTranscriptionModelProviderRole.customCloud.apiKeyProviderName(defaultName: "Custom"), "Custom")
        XCTAssertTrue(RomaTranscriptionModelProviderRole.localWhisper.supportsRecordedFileTranscription)
        XCTAssertTrue(RomaTranscriptionModelProviderRole.customCloud.supportsRecordedFileTranscription)
        XCTAssertFalse(RomaTranscriptionModelProviderRole.cloud(.cartesia).supportsRecordedFileTranscription)
        XCTAssertFalse(RomaTranscriptionModelProviderRole.localWhisper.isStreamingOnly)
        XCTAssertTrue(RomaTranscriptionModelProviderRole.cloud(.cartesia).isStreamingOnly)
        XCTAssertEqual(
            RomaTranscriptionModelProviderRole.cloud(.speechmatics).streamingConnectionModelName(for: "speechmatics-standard"),
            "standard"
        )
        XCTAssertEqual(
            RomaTranscriptionModelProviderRole.customCloud.streamingConnectionModelName(for: "custom-model"),
            "custom-model"
        )
        XCTAssertTrue(RomaTranscriptionModelProviderRole.cloud(.assemblyAI).mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(RomaTranscriptionModelProviderRole.cloud(.deepgram).mapsStreamingTransportTimeoutToFinalTimeout)

        let customLanguages = ["zz": "Customish"]
        XCTAssertEqual(
            RomaTranscriptionModelProviderRole.customCloud.transcriptionLanguageOptions(
                defaultLanguages: customLanguages,
                isMultilingual: true,
                usesRealtimeProviderLanguages: true
            ),
            customLanguages
        )
        XCTAssertNil(RomaTranscriptionModelProviderRole.cloud(.assemblyAI).transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: true
        )["en_uk"])
        XCTAssertEqual(RomaTranscriptionModelProviderRole.cloud(.assemblyAI).transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: false
        )["en_uk"], "British English")
    }

    func testMacOSTranscriptionModelProviderPreservesRawValuesAndLegacyLocalDecode() throws {
        XCTAssertEqual(
            RomaMacOSTranscriptionModelProvider.allCases.map(\.rawValue),
            [
                "Whisper",
                "Parakeet",
                "Qwen",
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
                "NVIDIA",
                "Custom",
                "Native Apple"
            ]
        )

        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(RomaMacOSTranscriptionModelProvider.self, from: Data(#""Local""#.utf8)),
            .whisper
        )
        XCTAssertEqual(
            try decoder.decode(RomaMacOSTranscriptionModelProvider.self, from: Data(#""Parakeet""#.utf8)),
            .fluidAudio
        )

        do {
            _ = try decoder.decode(RomaMacOSTranscriptionModelProvider.self, from: Data(#""Unknown""#.utf8))
            XCTFail("Unknown macOS transcription model provider raw value should throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMacOSTranscriptionModelFactsDeriveSharedModelPolicy() {
        let streamingFacts = RomaMacOSTranscriptionModelFacts(
            name: "scribe_v1",
            provider: .elevenLabs,
            isMultilingual: true,
            supportedLanguages: ["fallback": "Fallback"],
            supportsStreaming: true
        )
        let streamingSnapshot = RomaTranscriptionStreamingModelSnapshot(
            name: "scribe_v1",
            supportsStreaming: true
        )

        XCTAssertTrue(streamingFacts.supportsRecordedFileTranscription)
        XCTAssertEqual(streamingFacts.streamingPreferenceSnapshot, streamingSnapshot)
        XCTAssertEqual(
            streamingFacts.transcriptionSessionRouteFacts,
            RomaTranscriptionSessionRouteFacts(
                serviceRoute: .cloud,
                streamingSnapshot: streamingSnapshot
            )
        )
        XCTAssertEqual(streamingFacts.streamingConnectionModelName, "scribe_v2_realtime")
        XCTAssertFalse(streamingFacts.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertEqual(
            streamingFacts.transcriptionRuntimeResourcePlan,
            RomaTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        )
        XCTAssertEqual(
            streamingFacts.transcriptionModelAvailabilityFacts(hasConfiguredAPIKey: true),
            RomaTranscriptionModelAvailabilityFacts(
                requirement: .configuredAPIKey,
                hasConfiguredAPIKey: true
            )
        )

        let customLanguages = ["custom": "Custom"]
        let customFacts = RomaMacOSTranscriptionModelFacts(
            name: "custom-model",
            provider: .custom,
            isMultilingual: false,
            supportedLanguages: customLanguages,
            supportsStreaming: false
        )

        XCTAssertEqual(customFacts.transcriptionLanguageOptions, customLanguages)
        XCTAssertEqual(
            customFacts.transcriptionLanguageSelectionFacts,
            RomaTranscriptionLanguageSelectionFacts(
                source: .all,
                isMultilingual: false,
                languageOptions: customLanguages
            )
        )
        XCTAssertEqual(
            customFacts.powerModeTranscriptionModelFacts,
            RomaPowerModeTranscriptionModelFacts(
                name: "custom-model",
                languageSource: .all,
                isMultilingual: false,
                languageOptions: customLanguages
            )
        )
        XCTAssertEqual(
            customFacts.powerModeTranscriptionModelResourceFacts,
            RomaPowerModeTranscriptionModelResourceFacts(name: "custom-model", languageSource: .all)
        )
        XCTAssertEqual(
            customFacts.modelManagementFacts(isAvailableOnCurrentOS: false),
            RomaModelManagementModelFacts(
                name: "custom-model",
                category: .custom,
                isAvailableOnCurrentOS: false
            )
        )
    }

    func testProviderAPIErrorDomainsPreserveMacOSBatchMapping() {
        XCTAssertEqual(RomaTranscriptionModelProvider.groq.apiErrorDomain, "GroqAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.deepgram.apiErrorDomain, "DeepgramAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.gemini.apiErrorDomain, "GeminiAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.mistral.apiErrorDomain, "MistralAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.elevenLabs.apiErrorDomain, "ElevenLabsAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.soniox.apiErrorDomain, "SonioxAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.speechmatics.apiErrorDomain, "SpeechmaticsAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.assemblyAI.apiErrorDomain, "AssemblyAIAPI")
        XCTAssertEqual(RomaTranscriptionModelProvider.xai.apiErrorDomain, "XAIAPI")
        XCTAssertNil(RomaTranscriptionModelProvider.cartesia.apiErrorDomain)
        XCTAssertNil(RomaTranscriptionModelProvider.local.apiErrorDomain)
    }

    func testRequiredProviderAPIErrorDomainsMatchSharedMapping() {
        let providers: [RomaTranscriptionModelProvider] = [
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
        XCTAssertEqual(RomaTranscriptionModelProvider.assemblyAI.languageCodes, ["en", "es", "de", "fr", "pt", "it"])
        XCTAssertTrue(RomaTranscriptionModelProvider.assemblyAI.includesAutoDetect)

        let models = RomaTranscriptionModelCatalog.cloudModels(for: .assemblyAI)
        XCTAssertEqual(models.map(\.name), ["universal-3-pro", "universal-streaming"])
        XCTAssertEqual(models.map(\.displayName), ["Universal-3 Pro (AssemblyAI)", "Universal-2 (AssemblyAI)"])
        XCTAssertEqual(models.map(\.supportsStreaming), [true, true])
    }

    func testOpenAICompatibleProvidersUseAllLanguagesWithoutAutoDetectFlag() {
        XCTAssertNil(RomaTranscriptionModelProvider.groq.languageCodes)
        XCTAssertFalse(RomaTranscriptionModelProvider.groq.includesAutoDetect)
        XCTAssertNil(RomaTranscriptionModelProvider.gemini.languageCodes)
        XCTAssertFalse(RomaTranscriptionModelProvider.gemini.includesAutoDetect)
    }

    func testProviderKindExposesTranscriptionLanguageCapabilityMetadata() {
        let expected: [RomaProviderKind: RomaTranscriptionModelProvider] = [
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

    private func model(
        name: String,
        category: RomaModelManagementModelCategory,
        isAvailableOnCurrentOS: Bool = true
    ) -> ModelManagementFilterFixture {
        ModelManagementFilterFixture(
            facts: RomaModelManagementModelFacts(
                name: name,
                category: category,
                isAvailableOnCurrentOS: isAvailableOnCurrentOS
            )
        )
    }

    func testFluidAudioModelMetadataIsShared() {
        let models = RomaTranscriptionModelCatalog.fluidAudioModels

        XCTAssertEqual(models.map(\.name), ["parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3"])
        XCTAssertEqual(models.map(\.displayName), ["Parakeet V2", "Parakeet V3"])
        XCTAssertEqual(models.map(\.size), ["474 MB", "494 MB"])
        XCTAssertEqual(models.map(\.modelVersion), [.v2, .v3])
        XCTAssertEqual(
            RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
            "parakeet-tdt-0.6b-v2"
        )
        XCTAssertEqual(
            RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModel.name,
            RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )
        XCTAssertEqual(RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModel.modelVersion, .v2)
        XCTAssertEqual(models.map(\.supportsStreaming), [true, true])
        XCTAssertEqual(models.map(\.isMultilingual), [false, true])
        XCTAssertEqual(models.first?.supportedLanguages, ["en": "English"])
        XCTAssertEqual(models.last?.supportedLanguages["fr"], "French")
    }
}

private struct ModelManagementFilterFixture {
    let facts: RomaModelManagementModelFacts

}
