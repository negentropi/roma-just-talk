import Foundation
@testable import VoiceInkCore

final class DictationProfileTests: XCTestCase {
    func testMissingAndUnknownStoredProfilesUseCustom() {
        let suiteName = "DictationProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .custom)
        defaults.set("future-profile", forKey: VoiceInkDictationProfile.storageKey)
        XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .custom)
    }

    func testProfileChangesPersistAndPreserveCustomSettingsAndLibraries() throws {
        let suiteName = "DictationProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
        let snippets = [VoiceInkSpokenSnippet(trigger: "signature", content: "\nFelix\n")]
        let rules = [VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "RJT")]
        try VoiceInkSpokenSnippets.save(snippets, to: defaults)
        VoiceInkWordReplacementPreference.saveRules(rules, to: defaults)

        VoiceInkDictationProfile.none.save(to: defaults)
        let reopened = UserDefaults(suiteName: suiteName)!
        XCTAssertEqual(VoiceInkDictationProfile.current(in: reopened), .none)
        VoiceInkDictationProfile.custom.save(to: reopened)

        XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .custom)
        XCTAssertTrue(defaults.bool(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription))
        XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
        XCTAssertEqual(VoiceInkSpokenSnippets.load(from: defaults), snippets)
        XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), rules)
    }

    func testNonePreparationPreservesExactRecognitionBytesAndSkipsReplacements() {
        let raw = "\n <noise>KEEP</noise> [music]\t Um, \"new line\"  RJT e\u{301} 台北 👩🏽‍💻\r\n\n"
        var replacementCalls = 0
        let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            raw,
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration(
                punctuationMode: .removeAll,
                shouldFormatParagraphs: true,
                shouldLowercase: true,
                shouldRemoveFillerWords: true,
                fillerWords: ["um", "RJT"]
            ),
            cleanupProfile: .none
        ) { _ in
            replacementCalls += 1
            return "REPLACED"
        }

        XCTAssertTrue(plan.filteredText?.utf8.elementsEqual(raw.utf8) == true)
        XCTAssertEqual(Array(plan.textForEnhancement.utf8), Array(raw.utf8))
        XCTAssertEqual(Array(plan.cleanedText.utf8), Array(raw.utf8))
        XCTAssertEqual(replacementCalls, 0)
        XCTAssertFalse(plan.allowsEnhancement)
    }

    func testNonePreparationPreservesEmptyAndWhitespaceRecognition() {
        for raw in ["", " \t\r\n\n"] {
            let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
                raw,
                cleanupConfiguration: .disabled,
                cleanupProfile: .none
            ) { _ in
                XCTFail("None must not invoke replacements for blank recognition")
                return "PREVIOUS TEXT"
            }

            XCTAssertEqual(Array(plan.cleanedText.utf8), Array(raw.utf8))
            XCTAssertNil(plan.enhancementRequest(
                isEnhancementEnabled: true,
                isEnhancementConfigured: true
            ))
        }
    }

    func testNoneRefusesEnhancementEvenWhenPromptTriggerForcesIt() {
        let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            "make concise keep these words",
            cleanupConfiguration: .disabled,
            cleanupProfile: .none
        )
        let trigger = VoiceInkPromptDetectionResult(
            shouldEnableAI: true,
            selectedPromptId: UUID(),
            processedText: "keep these words",
            detectedTriggerWord: "make concise",
            originalEnhancementState: false,
            originalPromptId: nil
        )

        XCTAssertTrue(plan.shouldSkipEnhancement(
            configuration: nil,
            promptTriggerForcesEnhancement: true
        ))
        XCTAssertNil(plan.enhancementRequest(
            isEnhancementEnabled: true,
            isEnhancementConfigured: true,
            promptDetectionResult: trigger,
            skipConfiguration: VoiceInkPostProcessingSkipConfiguration(isEnabled: false, wordThreshold: 1)
        ))
        XCTAssertEqual(plan.cleanedText, "make concise keep these words")
    }

    func testCustomPreparationRetainsCleanupReplacementAndEnhancement() {
        var replacementCalls = 0
        let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            "Um Hello.",
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration(
                punctuationMode: .removeTrailingPeriod,
                shouldLowercase: true,
                shouldRemoveFillerWords: true,
                fillerWords: ["um"]
            ),
            cleanupProfile: .custom
        ) { text in
            replacementCalls += 1
            return text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(replacementCalls, 1)
        XCTAssertEqual(plan.textForEnhancement, "ROMA.")
        XCTAssertEqual(plan.cleanedText, "roma")
        XCTAssertTrue(plan.allowsEnhancement)
        XCTAssertEqual(plan.enhancementRequest(
            isEnhancementEnabled: true,
            isEnhancementConfigured: true
        )?.text, "ROMA.")
    }
}
