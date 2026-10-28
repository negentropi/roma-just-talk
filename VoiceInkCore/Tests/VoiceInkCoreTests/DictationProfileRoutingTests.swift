import Foundation
import VoiceInkCore

final class DictationProfileRoutingTests: XCTestCase {
    func testAllProfilesPersistWithoutChangingUnknownDefaultsFallback() throws {
        let name = "DictationProfileRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(VoiceInkDictationProfile.allCases.map(\.rawValue), ["custom", "none", "light", "clarity"])
        for profile in VoiceInkDictationProfile.allCases {
            profile.save(to: defaults)
            XCTAssertEqual(defaults.string(forKey: VoiceInkDictationProfile.storageKey), profile.rawValue)
            XCTAssertEqual(VoiceInkDictationProfile.current(in: UserDefaults(suiteName: name)!), profile)
            XCTAssertEqual(try JSONDecoder().decode(VoiceInkDictationProfile.self, from: JSONEncoder().encode(profile)), profile)
        }
        defaults.set("future-profile", forKey: VoiceInkDictationProfile.storageKey)
        XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .custom)
    }

    func testNewProfilesPreserveRawTextAndNeverUseLegacyPreparationOrEnhancement() throws {
        let trigger = VoiceInkPromptDetectionResult(
            shouldEnableAI: true, selectedPromptId: UUID(), processedText: "trigger removed",
            detectedTriggerWord: "rewrite", originalEnhancementState: false, originalPromptId: nil
        )
        for profile in [VoiceInkDictationProfile.light, .clarity] {
            for raw in ["", " \r\n\t ", "\n <noise>Um, Roma.</noise> [music] e\u{301} て\u{3099} 👩🏽‍💻\r\n "] {
                var legacyCalls = 0
                let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
                    raw,
                    cleanupConfiguration: .init(punctuationMode: .removeAll, shouldFormatParagraphs: true,
                                                shouldLowercase: true, shouldRemoveFillerWords: true,
                                                fillerWords: ["um", "Roma"]),
                    cleanupProfile: profile
                ) { _ in legacyCalls += 1; return "LEGACY OUTPUT" }
                XCTAssertEqual(plan.cleanupProfile, profile)
                XCTAssertEqual(legacyCalls, 0)
                for output in [try XCTUnwrap(plan.filteredText), plan.textForEnhancement, plan.cleanedText] {
                    XCTAssertEqual(Array(output.utf8), Array(raw.utf8))
                    XCTAssertEqual(Array(output.utf16), Array(raw.utf16))
                }
                XCTAssertFalse(plan.allowsEnhancement)
                XCTAssertTrue(plan.shouldSkipEnhancement(configuration: nil, promptTriggerForcesEnhancement: true))
                XCTAssertNil(plan.enhancementRequest(
                    isEnhancementEnabled: true, isEnhancementConfigured: true, promptDetectionResult: trigger,
                    skipConfiguration: .init(isEnabled: false, wordThreshold: 1)
                ))
            }
        }
    }

    func testNewProfilesRoundTripAndImportThroughExistingGeneralBackupCodec() throws {
        let name = "DictationProfileRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for profile in [VoiceInkDictationProfile.light, .clarity] {
            let input = try JSONSerialization.data(withJSONObject: [
                "generalSettings": ["dictationProfile": profile.rawValue, "clipboardRestoreDelay": 1.25]
            ])
            let decoded: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: input)
            let encoded = try VoiceInkSettingsBackupFileCodec.encode(decoded)
            let reopened: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: encoded)
            let preferences = try XCTUnwrap(reopened.generalSettings?.generalSettingsBackupPreferences)
            XCTAssertEqual(preferences.dictationProfile, profile)
            VoiceInkDictationProfile.none.save(to: defaults)
            VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
                VoiceInkGeneralSettingsBackupPolicy.importPlans(from: preferences), to: defaults
            )
            XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), profile)
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 1.25)
        }
    }

    func testUnknownProfileBackupStillRejectsBeforeAnyPreferenceApplication() throws {
        let name = "DictationProfileRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for invalid: Any in ["future-profile", "Light", 7] {
            VoiceInkDictationProfile.none.save(to: defaults)
            VoiceInkPastePreference.saveClipboardRestoreDelay(2.5, to: defaults)
            let input = try JSONSerialization.data(withJSONObject: [
                "generalSettings": ["dictationProfile": invalid, "clipboardRestoreDelay": 1.25]
            ])
            var rejected = false
            do {
                let backup: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: input)
                if let preferences = backup.generalSettings?.generalSettingsBackupPreferences {
                    VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
                        VoiceInkGeneralSettingsBackupPolicy.importPlans(from: preferences), to: defaults
                    )
                }
            } catch {
                rejected = true
            }
            XCTAssertTrue(rejected)
            XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .none)
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 2.5)
        }
    }
}
