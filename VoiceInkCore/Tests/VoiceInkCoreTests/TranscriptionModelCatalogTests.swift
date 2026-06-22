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
