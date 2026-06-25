import Foundation
@testable import VoiceInkCore

final class TranscriptionModelCatalogTests: XCTestCase {
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
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.cartesia.apiKeyProviderName, "Cartesia")
        XCTAssertEqual(VoiceInkMacOSTranscriptionModelProvider.custom.apiKeyProviderName, "Custom")
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
}
