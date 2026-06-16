#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class TranscriptionModelCatalogTests: XCTestCase {
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

    func testOpenAICompatibleProvidersUseAllLanguagesWithoutAutoDetectFlag() {
        XCTAssertNil(VoiceInkTranscriptionModelProvider.groq.languageCodes)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.groq.includesAutoDetect)
        XCTAssertNil(VoiceInkTranscriptionModelProvider.gemini.languageCodes)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.gemini.includesAutoDetect)
    }

    func testProviderKindExposesTranscriptionLanguageCapabilityMetadata() {
        XCTAssertEqual(
            VoiceInkProviderKind.deepgram.transcriptionModelProvider?.languageCodes,
            VoiceInkTranscriptionModelProvider.deepgram.languageCodes
        )
        XCTAssertEqual(
            VoiceInkProviderKind.deepgram.transcriptionModelProvider?.includesAutoDetect,
            VoiceInkTranscriptionModelProvider.deepgram.includesAutoDetect
        )
    }
}
#endif
