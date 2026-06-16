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
