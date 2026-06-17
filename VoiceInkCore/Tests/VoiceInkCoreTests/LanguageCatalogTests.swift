import Foundation
@testable import VoiceInkCore

final class LanguageCatalogTests: XCTestCase {
    func testLanguageCatalogPreservesSharedNames() {
        XCTAssertEqual(VoiceInkLanguageCatalog.all["auto"], "Auto-detect")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["en_uk"], "British English")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["de_ch"], "Swiss German")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["yue"], "Cantonese")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["zu"], "Zulu")
    }

    func testWhisperLanguagesPreserveMacOSWhisperSet() {
        let languages = VoiceInkLanguageCatalog.whisperLanguages()

        XCTAssertEqual(languages["auto"], "Auto-detect")
        XCTAssertEqual(languages["yue"], "Cantonese")
        XCTAssertEqual(languages["zh"], "Chinese")
        XCTAssertNil(languages["zu"])
        XCTAssertEqual(VoiceInkLanguageCatalog.whisperLanguages(isMultilingual: false), ["en": "English"])
    }

    func testNativeAppleLanguagesUseBCP47Identifiers() {
        XCTAssertEqual(VoiceInkLanguageCatalog.nativeApple["en-US"], "English (United States)")
        XCTAssertEqual(VoiceInkLanguageCatalog.nativeApple["zh-TW"], "Chinese (Taiwan)")
        XCTAssertNil(VoiceInkLanguageCatalog.nativeApple["en"])
    }

    func testFluidAudioLanguagesPreserveParakeetPolicies() {
        let languages = VoiceInkLanguageCatalog.fluidAudioLanguages()

        XCTAssertEqual(languages["auto"], "Auto-detect")
        XCTAssertEqual(languages["bg"], "Bulgarian")
        XCTAssertEqual(languages["uk"], "Ukrainian")
        XCTAssertNil(languages["ja"])
        XCTAssertEqual(VoiceInkLanguageCatalog.fluidAudioLanguages(isMultilingual: false), ["en": "English"])
    }

    func testProviderLanguagesPreserveCloudProviderPolicies() {
        let groq = VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.groq)
        XCTAssertEqual(groq["auto"], "Auto-detect")
        XCTAssertEqual(groq["zu"], "Zulu")

        let deepgram = VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.deepgram)
        XCTAssertEqual(deepgram["auto"], "Auto-detect")
        XCTAssertEqual(deepgram["ar"], "Arabic")
        XCTAssertNil(deepgram["zu"])

        let cartesia = VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.cartesia)
        XCTAssertNil(cartesia["auto"])
        XCTAssertEqual(cartesia["zu"], "Zulu")
    }

    func testProviderKindLanguagesExposeLocalWhisperPolicy() {
        let local = VoiceInkLanguageCatalog.languages(for: VoiceInkProviderKind.localWhisper)

        XCTAssertEqual(local["auto"], "Auto-detect")
        XCTAssertEqual(local["yue"], "Cantonese")
        XCTAssertNil(local["zu"])
    }

    func testAssemblyAILanguagesPreserveRealtimeAndBatchPolicies() {
        let realtime = VoiceInkTranscriptionLanguageSupport.assemblyAILanguages(usesRealtime: true)
        XCTAssertEqual(realtime["auto"], "Auto-detect")
        XCTAssertEqual(realtime["en"], "English")
        XCTAssertNil(realtime["en_uk"])

        let batch = VoiceInkTranscriptionLanguageSupport.assemblyAILanguages(usesRealtime: false)
        XCTAssertEqual(batch["auto"], "Auto-detect")
        XCTAssertEqual(batch["en_uk"], "British English")
        XCTAssertEqual(batch["de_ch"], "Swiss German")
    }

    func testValidLanguageOrFallbackPreservesMacOSFallbackOrder() {
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "es",
                languages: ["auto": "Auto-detect", "es": "Spanish"]
            ),
            "es"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: VoiceInkLanguageCatalog.nativeApple,
                prefersNativeAppleEnglish: true
            ),
            "en-US"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: ["auto": "Auto-detect", "en": "English"]
            ),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: ["aa": "Aardvark", "zz": "Zed"]
            ),
            "aa"
        )
    }

    func testValidLanguageOrFallbackSupportsProviderKindLanguages() {
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "zu",
                provider: .localWhisper
            ),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "zu",
                provider: .elevenLabs
            ),
            "zu"
        )
    }

    func testRequestLanguageStripsAutoAndBlankValues() {
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage(nil))
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage(""))
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage("  "))
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage("auto"))
        XCTAssertEqual(VoiceInkTranscriptionLanguageSupport.requestLanguage(" fr "), "fr")
    }
}
