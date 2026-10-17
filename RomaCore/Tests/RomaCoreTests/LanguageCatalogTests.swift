import Foundation
@testable import RomaCore

final class LanguageCatalogTests: XCTestCase {
    func testLanguageCatalogPreservesSharedNames() {
        XCTAssertEqual(RomaLanguageCatalog.all["auto"], "Auto-detect")
        XCTAssertEqual(RomaLanguageCatalog.all["en_uk"], "British English")
        XCTAssertEqual(RomaLanguageCatalog.all["de_ch"], "Swiss German")
        XCTAssertEqual(RomaLanguageCatalog.all["yue"], "Cantonese")
        XCTAssertEqual(RomaLanguageCatalog.all["zu"], "Zulu")
    }

    func testWhisperLanguagesPreserveMacOSWhisperSet() {
        let languages = RomaLanguageCatalog.whisperLanguages()

        XCTAssertEqual(languages["auto"], "Auto-detect")
        XCTAssertEqual(languages["yue"], "Cantonese")
        XCTAssertEqual(languages["zh"], "Chinese")
        XCTAssertNil(languages["zu"])
        XCTAssertEqual(RomaLanguageCatalog.whisperLanguages(isMultilingual: false), ["en": "English"])
    }

    func testNativeAppleLanguagesUseBCP47Identifiers() {
        XCTAssertEqual(RomaLanguageCatalog.nativeApple["en-US"], "English (United States)")
        XCTAssertEqual(RomaLanguageCatalog.nativeApple["zh-TW"], "Chinese (Taiwan)")
        XCTAssertNil(RomaLanguageCatalog.nativeApple["en"])
    }

    func testNativeAppleDisplayNameUsesCatalogThenLocalizedFallback() {
        let locale = Locale(identifier: "en_US_POSIX")

        XCTAssertEqual(
            RomaLanguageCatalog.nativeAppleDisplayName(for: "en-US", locale: locale),
            "English (United States)"
        )
        XCTAssertEqual(
            RomaLanguageCatalog.nativeAppleDisplayName(for: "es-AR", locale: locale),
            "Spanish (Argentina)"
        )
        XCTAssertEqual(
            RomaLanguageCatalog.nativeAppleDisplayName(for: "zz-ZZ", locale: locale),
            "zz-ZZ"
        )
    }

    func testFluidAudioLanguagesPreserveParakeetPolicies() {
        let languages = RomaLanguageCatalog.fluidAudioLanguages()

        XCTAssertEqual(languages["auto"], "Auto-detect")
        XCTAssertEqual(languages["bg"], "Bulgarian")
        XCTAssertEqual(languages["uk"], "Ukrainian")
        XCTAssertNil(languages["ja"])
        XCTAssertEqual(RomaLanguageCatalog.fluidAudioLanguages(isMultilingual: false), ["en": "English"])
    }

    func testProviderLanguagesPreserveCloudProviderPolicies() {
        let groq = RomaLanguageCatalog.languages(for: RomaTranscriptionModelProvider.groq)
        XCTAssertEqual(groq["auto"], "Auto-detect")
        XCTAssertEqual(groq["zu"], "Zulu")

        let deepgram = RomaLanguageCatalog.languages(for: RomaTranscriptionModelProvider.deepgram)
        XCTAssertEqual(deepgram["auto"], "Auto-detect")
        XCTAssertEqual(deepgram["ar"], "Arabic")
        XCTAssertNil(deepgram["zu"])

        let cartesia = RomaLanguageCatalog.languages(for: RomaTranscriptionModelProvider.cartesia)
        XCTAssertNil(cartesia["auto"])
        XCTAssertEqual(cartesia["zu"], "Zulu")
    }

    func testProviderKindLanguagesExposeLocalWhisperPolicy() {
        let local = RomaLanguageCatalog.languages(for: RomaProviderKind.localWhisper)

        XCTAssertEqual(local["auto"], "Auto-detect")
        XCTAssertEqual(local["yue"], "Cantonese")
        XCTAssertNil(local["zu"])
    }

    func testAssemblyAILanguagesPreserveRealtimeAndBatchPolicies() {
        let realtime = RomaTranscriptionLanguageSupport.assemblyAILanguages(usesRealtime: true)
        XCTAssertEqual(realtime["auto"], "Auto-detect")
        XCTAssertEqual(realtime["en"], "English")
        XCTAssertNil(realtime["en_uk"])

        let batch = RomaTranscriptionLanguageSupport.assemblyAILanguages(usesRealtime: false)
        XCTAssertEqual(batch["auto"], "Auto-detect")
        XCTAssertEqual(batch["en_uk"], "British English")
        XCTAssertEqual(batch["de_ch"], "Swiss German")
    }

    func testTranscriptionLanguageSourceRoutesMacOSModelProviderPolicies() {
        let whisper = RomaTranscriptionLanguageSupport.languages(for: .whisper)
        XCTAssertEqual(whisper["auto"], "Auto-detect")
        XCTAssertEqual(whisper["yue"], "Cantonese")
        XCTAssertNil(whisper["zu"])

        let nativeApple = RomaTranscriptionLanguageSupport.languages(for: .nativeApple)
        XCTAssertEqual(nativeApple["en-US"], "English (United States)")
        XCTAssertNil(nativeApple["auto"])

        let fluidAudio = RomaTranscriptionLanguageSupport.languages(for: .fluidAudio)
        XCTAssertEqual(fluidAudio["auto"], "Auto-detect")
        XCTAssertEqual(fluidAudio["bg"], "Bulgarian")
        XCTAssertNil(fluidAudio["ja"])

        let deepgram = RomaTranscriptionLanguageSupport.languages(for: .provider(.deepgram))
        XCTAssertEqual(deepgram["auto"], "Auto-detect")
        XCTAssertEqual(deepgram["ar"], "Arabic")
        XCTAssertNil(deepgram["zu"])

        let all = RomaTranscriptionLanguageSupport.languages(for: .all)
        XCTAssertEqual(all["auto"], "Auto-detect")
        XCTAssertEqual(all["zu"], "Zulu")

        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.languages(for: .nativeApple, isMultilingual: false),
            ["en": "English"]
        )
    }

    func testTranscriptionLanguageSourceRoutesAssemblyAIRealtimePolicy() {
        let realtime = RomaTranscriptionLanguageSupport.languages(
            for: .provider(.assemblyAI),
            assemblyAIUsesRealtime: true
        )
        XCTAssertEqual(realtime["auto"], "Auto-detect")
        XCTAssertNil(realtime["en_uk"])

        let batch = RomaTranscriptionLanguageSupport.languages(
            for: .provider(.assemblyAI),
            assemblyAIUsesRealtime: false
        )
        XCTAssertEqual(batch["auto"], "Auto-detect")
        XCTAssertEqual(batch["en_uk"], "British English")
    }

    func testValidLanguageOrFallbackPreservesMacOSFallbackOrder() {
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "es",
                languages: ["auto": "Auto-detect", "es": "Spanish"]
            ),
            "es"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: RomaLanguageCatalog.nativeApple,
                prefersNativeAppleEnglish: true
            ),
            "en-US"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: ["auto": "Auto-detect", "en": "English"]
            ),
            "auto"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: ["aa": "Aardvark", "zz": "Zed"]
            ),
            "aa"
        )
    }

    func testValidLanguageOrFallbackSupportsProviderKindLanguages() {
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "zu",
                provider: .localWhisper
            ),
            "auto"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "zu",
                provider: .elevenLabs
            ),
            "zu"
        )
    }

    func testValidLanguageOrFallbackSupportsLanguageSourcePolicy() {
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                source: .nativeApple
            ),
            "en-US"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "en_uk",
                source: .provider(.assemblyAI),
                assemblyAIUsesRealtime: true
            ),
            "auto"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguageSupport.validLanguageOrFallback(
                "en_uk",
                source: .provider(.assemblyAI),
                assemblyAIUsesRealtime: false
            ),
            "en_uk"
        )
    }

    func testTranscriptionLanguageSelectionFactsDeriveControlFromSource() {
        let geminiFacts = RomaTranscriptionLanguageSelectionFacts(
            source: .provider(.gemini),
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.all
        )
        let whisperFacts = RomaTranscriptionLanguageSelectionFacts(
            source: .whisper,
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.whisperLanguages()
        )
        let nativeAppleFacts = RomaTranscriptionLanguageSelectionFacts(
            source: .nativeApple,
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.nativeApple
        )
        let englishOnlyFacts = RomaTranscriptionLanguageSelectionFacts(
            source: .provider(.groq),
            isMultilingual: false,
            languageOptions: RomaLanguageCatalog.englishOnly
        )

        XCTAssertEqual(geminiFacts.control, .disabledAutodetect)
        XCTAssertTrue(geminiFacts.shouldShowDisabledAutodetectControl)
        XCTAssertFalse(geminiFacts.shouldShowPicker)
        XCTAssertFalse(geminiFacts.shouldShowDefaultLanguageOnly)
        XCTAssertFalse(geminiFacts.showsNativeAppleAssetControl)
        XCTAssertEqual(whisperFacts.control, .picker)
        XCTAssertFalse(whisperFacts.shouldShowDisabledAutodetectControl)
        XCTAssertTrue(whisperFacts.shouldShowPicker)
        XCTAssertFalse(whisperFacts.shouldShowDefaultLanguageOnly)
        XCTAssertFalse(whisperFacts.showsNativeAppleAssetControl)
        XCTAssertEqual(nativeAppleFacts.control, .picker)
        XCTAssertFalse(nativeAppleFacts.shouldShowDisabledAutodetectControl)
        XCTAssertTrue(nativeAppleFacts.shouldShowPicker)
        XCTAssertFalse(nativeAppleFacts.shouldShowDefaultLanguageOnly)
        XCTAssertTrue(nativeAppleFacts.showsNativeAppleAssetControl)
        XCTAssertEqual(englishOnlyFacts.control, .hiddenDefault)
        XCTAssertFalse(englishOnlyFacts.shouldShowDisabledAutodetectControl)
        XCTAssertFalse(englishOnlyFacts.shouldShowPicker)
        XCTAssertTrue(englishOnlyFacts.shouldShowDefaultLanguageOnly)
    }

    func testTranscriptionLanguageSelectionFactsUseSharedCompatibleFallback() {
        let nativeAppleFacts = RomaTranscriptionLanguageSelectionFacts(
            source: .nativeApple,
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.nativeApple
        )
        let whisperFacts = RomaTranscriptionLanguageSelectionFacts(
            source: .whisper,
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.whisperLanguages()
        )

        XCTAssertEqual(nativeAppleFacts.compatibleLanguage("bad"), "en-US")
        XCTAssertEqual(whisperFacts.compatibleLanguage("bad"), RomaLanguageCatalog.autoDetectCode)
        XCTAssertEqual(whisperFacts.compatibleLanguage("fr"), "fr")
    }

    func testModelEffectiveLanguagePreservesAutoAcrossEnglishOnlyAndBilingualModels() {
        withLanguageDefaults { defaults in
            let english = languageFacts(.fluidAudio, multilingual: false)
            let bilingual = languageFacts(.qwen)
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(RomaTranscriptionLanguagePreference.effectiveLanguage(for: english, from: defaults), "en")
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: english, from: defaults), "en")
            XCTAssertEqual(RomaTranscriptionLanguagePreference.effectiveLanguage(for: bilingual, from: defaults), "auto")
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults))
            XCTAssertEqual(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults), "auto")
        }
    }

    func testModelEffectiveLanguagePreservesExplicitEnglishAndLaterUserChoices() {
        withLanguageDefaults { defaults in
            let bilingual = languageFacts(.qwen)
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("en", to: defaults)
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults), "en")
            XCTAssertEqual(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults), "en")
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("zh", to: defaults)
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.whisper, multilingual: false), from: defaults), "en")
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults), "zh")
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults))
        }
    }

    func testModelEffectiveLanguageResolvesUnsupportedPreferencesWithoutPersistingFallbacks() {
        withLanguageDefaults { defaults in
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.qwen), from: defaults))
            XCTAssertNil(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults))
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr-FR", to: defaults)
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.nativeApple), from: defaults), "fr-FR")
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.qwen), from: defaults))
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.provider(.groq)), from: defaults))
            XCTAssertEqual(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults), "fr-FR")
            RomaTranscriptionPromptPreference.savePrompt("Saved French prompt", to: defaults)
            RomaLocalWhisperPromptCatalog.saveCustomPrompt("Edited auto prompt", for: "auto", to: defaults)
            XCTAssertEqual(RomaTranscriptionPromptPreference.requestPrompt(
                forEffectiveLanguage: "auto", from: defaults
            ), "Edited auto prompt")
            XCTAssertEqual(RomaTranscriptionPromptPreference.requestPrompt(
                forEffectiveLanguage: "fr-FR", from: defaults
            ), "Saved French prompt")
            XCTAssertEqual(RomaTranscriptionPromptPreference.storedPrompt(from: defaults), "Saved French prompt")
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.nativeApple), from: defaults), "en-US")
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.provider(.cartesia)), from: defaults), "en")
            XCTAssertEqual(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults), "auto")
        }
    }

    private func languageFacts(_ source: RomaTranscriptionLanguageSource, multilingual: Bool = true) -> RomaTranscriptionLanguageSelectionFacts {
        RomaTranscriptionLanguageSelectionFacts(source: source, isMultilingual: multilingual,
            languageOptions: RomaTranscriptionLanguageSupport.languages(for: source, isMultilingual: multilingual))
    }

    private func withLanguageDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "LanguageCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testNativeAppleLanguageAssetPresentationPreservesProgressAndIconStates() {
        let checking = RomaNativeAppleLanguageAssetPresentation.presentation(for: .checking)
        XCTAssertEqual(checking.display, .progress)
        XCTAssertEqual(checking.helpText, "Checking Apple Speech language download status.")
        XCTAssertNil(checking.accessibilityLabel)

        let downloaded = RomaNativeAppleLanguageAssetPresentation.presentation(for: .downloaded)
        XCTAssertEqual(downloaded.display, .hidden)
        XCTAssertNil(downloaded.helpText)
        XCTAssertNil(downloaded.accessibilityLabel)

        let downloading = RomaNativeAppleLanguageAssetPresentation.presentation(for: .downloading)
        XCTAssertEqual(downloading.display, .progress)
        XCTAssertEqual(downloading.helpText, "Downloading Apple Speech language.")
        XCTAssertNil(downloading.accessibilityLabel)

        let unsupported = RomaNativeAppleLanguageAssetPresentation.presentation(for: .notSupported)
        XCTAssertEqual(unsupported.display, .statusIcon(systemImageName: "exclamationmark.triangle"))
        XCTAssertEqual(unsupported.helpText, "This language is not supported by Apple Speech.")
        XCTAssertNil(unsupported.accessibilityLabel)

        let unavailable = RomaNativeAppleLanguageAssetPresentation.presentation(for: .assetManagementUnavailable)
        XCTAssertEqual(unavailable.display, .statusIcon(systemImageName: "exclamationmark.triangle"))
        XCTAssertEqual(unavailable.helpText, "Apple Speech asset management is not available on this system.")
        XCTAssertNil(unavailable.accessibilityLabel)
    }

    func testNativeAppleLanguageAssetPresentationPreservesActionStates() {
        let needsDownload = RomaNativeAppleLanguageAssetPresentation.presentation(for: .needsDownload)
        XCTAssertEqual(needsDownload.display, .actionButton(systemImageName: "arrow.down.circle.fill"))
        XCTAssertEqual(needsDownload.helpText, "Download this Apple Speech language before transcribing.")
        XCTAssertEqual(needsDownload.accessibilityLabel, "Download Apple Speech language")

        let failed = RomaNativeAppleLanguageAssetPresentation.presentation(for: .failed("Network unavailable"))
        XCTAssertEqual(failed.display, .actionButton(systemImageName: "arrow.clockwise.circle.fill"))
        XCTAssertEqual(
            failed.helpText,
            "Retry downloading this Apple Speech language. Network unavailable"
        )
        XCTAssertEqual(failed.accessibilityLabel, "Retry Apple Speech language download")
    }

    func testSortedLanguageOptionsPutAutoDetectFirstThenSortByDisplayName() {
        XCTAssertEqual(
            RomaLanguageCatalog.sortedOptions([
                "es": "Spanish",
                "auto": "Auto-detect",
                "de": "German",
                "en": "English"
            ]),
            [
                RomaLanguageOption(code: "auto", name: "Auto-detect"),
                RomaLanguageOption(code: "en", name: "English"),
                RomaLanguageOption(code: "de", name: "German"),
                RomaLanguageOption(code: "es", name: "Spanish")
            ]
        )
    }

    func testSortedLanguageOptionsUseCodeForStableTies() {
        XCTAssertEqual(
            RomaLanguageCatalog.sortedOptions([
                "en_us": "English",
                "en": "English"
            ]),
            [
                RomaLanguageOption(code: "en", name: "English"),
                RomaLanguageOption(code: "en_us", name: "English")
            ]
        )
    }

    func testDisplayNameUsesLanguageMapThenFallback() {
        XCTAssertEqual(
            RomaLanguageCatalog.displayName(
                for: "es",
                in: ["es": "Spanish", "en": "English"]
            ),
            "Spanish"
        )
        XCTAssertEqual(
            RomaLanguageCatalog.displayName(
                for: "bad",
                in: ["es": "Spanish", "en": "English"]
            ),
            "Unknown"
        )
        XCTAssertEqual(
            RomaLanguageCatalog.displayName(
                for: "bad",
                in: ["es": "Spanish"],
                fallback: "Unavailable"
            ),
            "Unavailable"
        )
    }

    func testTranscriptionLanguagePresentationBuildsMenuLabelWithSharedDisplayName() {
        XCTAssertEqual(
            RomaTranscriptionLanguagePresentation.menuLabel(
                selectedLanguage: "es",
                languages: ["es": "Spanish", "en": "English"]
            ),
            "Language: Spanish"
        )
        XCTAssertEqual(
            RomaTranscriptionLanguagePresentation.menuLabel(
                selectedLanguage: "bad",
                languages: ["es": "Spanish", "en": "English"]
            ),
            "Language: Unknown"
        )
    }

    func testRequestLanguageStripsAutoAndBlankValues() {
        XCTAssertNil(RomaTranscriptionLanguageSupport.requestLanguage(nil))
        XCTAssertNil(RomaTranscriptionLanguageSupport.requestLanguage(""))
        XCTAssertNil(RomaTranscriptionLanguageSupport.requestLanguage("  "))
        XCTAssertNil(RomaTranscriptionLanguageSupport.requestLanguage("auto"))
        XCTAssertEqual(RomaTranscriptionLanguageSupport.requestLanguage(" fr "), "fr")
    }
}
