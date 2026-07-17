import Foundation
import VoiceInkCore

final class UserDefaultsSettingsBackupPolicyTests: XCTestCase {
    private struct TestShortcutBackup: Codable, Equatable {
        let shortcut: String
    }

    func testBackupCategoriesPreserveMacOSImportOrderAndTitles() {
        XCTAssertEqual(
            VoiceInkSettingsBackupCategory.allCases.map(\.rawValue),
            ["general", "prompts", "powerMode", "dictionary", "customModels"]
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupCategory.allCases.map(\.title),
            [
                "General Settings",
                "Custom Prompts",
                "Power Mode",
                "Dictionary",
                "Custom Model Definitions"
            ]
        )
    }

    func testBackupImportPolicySummarizesAllAndSelectedCategories() {
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(
                for: Set(VoiceInkSettingsBackupCategory.allCases)
            ),
            "All settings"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(for: [.dictionary, .prompts]),
            "Custom Prompts, Dictionary"
        )
    }

    func testBackupImportPolicyRemindsOnlyForAPIKeyDependentCategories() {
        XCTAssertFalse(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: []))
        XCTAssertFalse(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.general, .dictionary]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.prompts]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.powerMode]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.customModels]))
    }

    func testBackupImportPolicyBuildsCurrentVersionWithFallback() {
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.currentVersion(bundleShortVersion: "2.4.0"),
            "2.4.0"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.currentVersion(bundleShortVersion: nil),
            VoiceInkSettingsBackupImportPolicy.fallbackVersion
        )
    }

    func testBackupVersionReviewReportsOnlyMismatches() {
        var events = [String]()
        let mismatchReview = VoiceInkSettingsBackupVersionReview(
            importedVersion: "2.3.0",
            currentVersion: "2.4.0"
        )

        XCTAssertTrue(mismatchReview.hasMismatch)

        VoiceInkSettingsBackupImportPolicy.versionReview(
            importedVersion: "2.4.0",
            currentVersion: "2.4.0"
        ).applyRuntimeState { importedVersion, currentVersion in
            events.append("\(importedVersion)->\(currentVersion)")
        }

        VoiceInkSettingsBackupImportPolicy.versionReview(
            importedVersion: "2.3.0",
            currentVersion: "2.4.0"
        ).applyRuntimeState { importedVersion, currentVersion in
            events.append("\(importedVersion)->\(currentVersion)")
        }

        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.versionReview(
                importedVersion: "2.3.0",
                currentVersion: "2.4.0"
            ),
            mismatchReview
        )
        XCTAssertEqual(events, ["2.3.0->2.4.0"])
    }

    func testBackupImportSelectionReviewAppliesMacOSImportFlowDecisions() {
        var events = [String]()

        VoiceInkSettingsBackupImportPolicy.importSelectionReview(
            selectedCategories: nil
        ).applyRuntimeState(
            reportNoSettingsImported: {
                events.append("canceled")
            },
            reportEmptyCategorySelection: {
                events.append("empty")
            },
            importSelectedCategories: { categories in
                events.append("import:\(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))")
            }
        )

        VoiceInkSettingsBackupImportPolicy.importSelectionReview(
            selectedCategories: []
        ).applyRuntimeState(
            reportNoSettingsImported: {
                events.append("canceled")
            },
            reportEmptyCategorySelection: {
                events.append("empty")
            },
            importSelectedCategories: { categories in
                events.append("import:\(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))")
            }
        )

        VoiceInkSettingsBackupImportPolicy.importSelectionReview(
            selectedCategories: [.general, .dictionary]
        ).applyRuntimeState(
            reportNoSettingsImported: {
                events.append("canceled")
            },
            reportEmptyCategorySelection: {
                events.append("empty")
            },
            importSelectedCategories: { categories in
                events.append("import:\(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))")
            }
        )

        XCTAssertEqual(
            events,
            [
                "canceled",
                "empty",
                "import:General Settings, Dictionary"
            ]
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportSelectionReview(selectedCategories: nil),
            .canceled
        )
    }

    func testBackupImportSuccessPlanShowsAndAppliesAPIKeyFollowUpOnlyWhenNeeded() {
        let generalPlan = VoiceInkSettingsBackupImportPolicy.importSuccessPlan(categories: [.general])
        let customModelsPlan = VoiceInkSettingsBackupImportSuccessPlan(categories: [.customModels])

        XCTAssertFalse(generalPlan.isConfigureAPIKeysActionVisible)
        XCTAssertTrue(customModelsPlan.isConfigureAPIKeysActionVisible)

        var events = [String]()
        generalPlan.applyRuntimeState(
            selectedConfigureAPIKeysAction: true,
            navigateToAPIKeySettings: {
                events.append("navigate")
            }
        )

        let promptPlan = VoiceInkSettingsBackupImportPolicy.importSuccessPlan(categories: [.prompts])
        XCTAssertTrue(promptPlan.isConfigureAPIKeysActionVisible)
        promptPlan.applyRuntimeState(
            selectedConfigureAPIKeysAction: false,
            navigateToAPIKeySettings: {
                events.append("navigate")
            }
        )
        promptPlan.applyRuntimeState(
            selectedConfigureAPIKeysAction: true,
            navigateToAPIKeySettings: {
                events.append("navigate")
            }
        )

        XCTAssertEqual(events, ["navigate"])
    }

    func testBackupPresentationBuildsDynamicExportAndImportMessages() {
        let presentation = VoiceInkSettingsBackupPresentation.macOS

        XCTAssertEqual(
            presentation.exportSuccessMessage(fileName: "Roma.json"),
            "Your settings have been successfully exported to Roma.json."
        )
        XCTAssertEqual(
            presentation.exportSaveFailureMessage(localizedDescription: "disk full"),
            "Could not save settings to file: disk full"
        )
        XCTAssertEqual(
            presentation.exportEncodingFailureMessage(localizedDescription: "bad data"),
            "Could not encode settings to JSON: bad data"
        )
        XCTAssertEqual(
            presentation.versionMismatchMessage(importedVersion: "1.0", currentVersion: "2.0"),
            "The imported settings file (version 1.0) is from a different version than your application (version 2.0). Proceeding with import, but be aware of potential incompatibilities."
        )
        XCTAssertEqual(
            presentation.importFailureMessage(localizedDescription: "bad json"),
            "Error importing settings: bad json. The file might be corrupted or not in the correct format."
        )
    }

    func testBackupPresentationBuildsImportSuccessTextWithOptionalAPIKeyReminder() {
        let presentation = VoiceInkSettingsBackupPresentation.macOS

        XCTAssertEqual(
            presentation.importSuccessInformativeText(fileName: "Roma.json", categories: [.general]),
            """
            Settings imported successfully from Roma.json.

            Imported: General Settings.

            It is recommended to restart VoiceInk for all changes to take full effect.
            """
        )
        XCTAssertEqual(
            presentation.importSuccessInformativeText(fileName: "Roma.json", categories: [.prompts]),
            """
            Settings imported successfully from Roma.json.

            Imported: Custom Prompts.

            IMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.

            It is recommended to restart VoiceInk for all changes to take full effect.
            """
        )
    }

    func testSettingsBackupFilePreservesMacOSLegacyDecodeDefaults() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        let backup = try JSONDecoder().decode(VoiceInkSettingsBackupFile<TestShortcutBackup>.self, from: data)

        XCTAssertEqual(backup.version, "0.0.0")
        XCTAssertEqual(backup.customPrompts, [])
        XCTAssertEqual(backup.powerModeConfigs, [])
        XCTAssertNil(backup.powerModeShortcuts)
        XCTAssertNil(backup.vocabularyWords)
        XCTAssertNil(backup.wordReplacements)
        XCTAssertNil(backup.generalSettings)
        XCTAssertNil(backup.customEmojis)
        XCTAssertNil(backup.customCloudModels)
    }

    func testSettingsBackupFileRoundTripsTopLevelSharedWireShape() throws {
        let promptId = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let powerModeId = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let customModelId = UUID(uuidString: "00000000-0000-0000-0000-000000000703")!
        let backup = VoiceInkSettingsBackupFile<TestShortcutBackup>(
            version: "2.4.0",
            customPrompts: [
                VoiceInkCustomPrompt(
                    id: promptId,
                    title: "Roma",
                    promptText: "Clean dictation",
                    isActive: true,
                    icon: "sparkles",
                    description: "Polish transcript",
                    isPredefined: false,
                    triggerWords: ["roma"],
                    useSystemInstructions: true
                )
            ],
            powerModeConfigs: [
                PowerModeConfig(
                    id: powerModeId,
                    name: "Focus",
                    emoji: "F",
                    isAIEnhancementEnabled: true,
                    selectedPrompt: promptId.uuidString,
                    selectedTranscriptionModelName: "large-v3",
                    selectedLanguage: "en",
                    selectedAIProvider: "openai",
                    selectedAIModel: "gpt-4.1"
                )
            ],
            powerModeShortcuts: [
                powerModeId.uuidString: TestShortcutBackup(shortcut: "command-space")
            ],
            vocabularyWords: [
                VoiceInkVocabularyWordBackup(word: "VoiceInk")
            ],
            wordReplacements: [
                "voice ink": "VoiceInk"
            ],
            generalSettings: nil,
            customEmojis: ["F"],
            customCloudModels: [
                VoiceInkCustomCloudModelBackup(
                    id: customModelId,
                    name: "custom",
                    displayName: "Custom",
                    description: "Custom OpenAI-compatible model",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    modelName: "whisper-1",
                    isMultilingualModel: true,
                    supportedLanguages: ["en": "English"],
                    apiKey: nil
                )
            ]
        )

        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(VoiceInkSettingsBackupFile<TestShortcutBackup>.self, from: data)

        XCTAssertEqual(decoded.version, "2.4.0")
        XCTAssertEqual(decoded.customPrompts.map(\.id), [promptId])
        XCTAssertEqual(decoded.customPrompts.map(\.title), ["Roma"])
        XCTAssertEqual(decoded.powerModeConfigs.map(\.id), [powerModeId])
        XCTAssertEqual(decoded.powerModeConfigs.map(\.name), ["Focus"])
        XCTAssertEqual(decoded.powerModeShortcuts, [powerModeId.uuidString: TestShortcutBackup(shortcut: "command-space")])
        XCTAssertEqual(decoded.vocabularyWords, [VoiceInkVocabularyWordBackup(word: "VoiceInk")])
        XCTAssertEqual(decoded.wordReplacements, ["voice ink": "VoiceInk"])
        XCTAssertEqual(decoded.customEmojis, ["F"])
        XCTAssertEqual(decoded.customCloudModels?.map(\.id), [customModelId])
        XCTAssertEqual(decoded.customCloudModels?.map(\.modelName), ["whisper-1"])
    }

    func testSettingsBackupFileCodecPreservesPrettyPrintedExportAndSharedDecode() throws {
        let backup = VoiceInkSettingsBackupFile<TestShortcutBackup>(
            version: "2.4.0",
            customPrompts: [],
            powerModeConfigs: [],
            powerModeShortcuts: nil,
            vocabularyWords: nil,
            wordReplacements: nil,
            generalSettings: nil,
            customEmojis: nil,
            customCloudModels: nil
        )

        let data = try VoiceInkSettingsBackupFileCodec.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded: VoiceInkSettingsBackupFile<TestShortcutBackup> = try VoiceInkSettingsBackupFileCodec.decode(from: data)

        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("  \"version\""))
        XCTAssertEqual(decoded.version, "2.4.0")
        XCTAssertEqual(decoded.customPrompts, [])
        XCTAssertEqual(decoded.powerModeConfigs, [])
    }

    func testSettingsBackupFileCodecRoundTripsGeneralSettingsPublicSurface() throws {
        let preferences = generalSettingsPublicSurfaceBackupPreferences()
        let payload = VoiceInkGeneralSettingsBackupPayload(
            shortcutBackupRecords: [.primaryRecording: TestShortcutBackup(shortcut: "command-space")],
            preferences: preferences
        )
        let backupFile = VoiceInkSettingsBackupFile(
            version: "2.4.0",
            customPrompts: [],
            powerModeConfigs: [],
            powerModeShortcuts: nil,
            vocabularyWords: nil,
            wordReplacements: nil,
            generalSettings: payload,
            customEmojis: nil,
            customCloudModels: nil
        )

        let data = try VoiceInkSettingsBackupFileCodec.encode(backupFile)
        let decoded: VoiceInkSettingsBackupFile<TestShortcutBackup> = try VoiceInkSettingsBackupFileCodec.decode(from: data)

        XCTAssertEqual(decoded.version, "2.4.0")
        XCTAssertEqual(
            decoded.generalSettings?.shortcutBackupRecords[.primaryRecording],
            TestShortcutBackup(shortcut: "command-space")
        )
        XCTAssertEqual(decoded.generalSettings?.generalSettingsBackupPreferences, preferences)
    }

    func testGeneralSettingsBackupPayloadPreservesWireShapeAndGroupedPreferences() throws {
        let preferences = generalSettingsBackupPreferencesFixture()
        let payload = VoiceInkGeneralSettingsBackupPayload(
            shortcutBackupRecords: [
                .primaryRecording: "primary-shortcut",
                .toggleEnhancement: "toggle-shortcut"
            ],
            preferences: preferences
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["primaryRecordingShortcut"] as? String, "primary-shortcut")
        XCTAssertEqual(json["toggleEnhancementShortcut"] as? String, "toggle-shortcut")
        XCTAssertEqual(json["primaryRecordingShortcutRawValue"] as? String, "custom")
        XCTAssertEqual(json["secondaryRecordingShortcutModeRawValue"] as? String, "hybrid")
        XCTAssertEqual(json["launchAtLoginEnabled"] as? Bool, true)
        XCTAssertEqual(json["isSoundFeedbackEnabled"] as? Bool, true)
        let decoded = try JSONDecoder().decode(
            VoiceInkGeneralSettingsBackupPayload<String>.self,
            from: data
        )

        XCTAssertEqual(
            decoded.shortcutBackupRecords,
            [
                .primaryRecording: "primary-shortcut",
                .toggleEnhancement: "toggle-shortcut"
            ]
        )
        XCTAssertEqual(decoded.generalSettingsBackupPreferences, preferences)
    }

    func testBackupPreferencesPreserveGroupedExportShape() {
        let recordingShortcut = VoiceInkRecordingShortcutBackupPreferences(
            primaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.custom.rawValue,
            secondaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.none.rawValue,
            primaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.special.rawValue,
            secondaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.hybrid.rawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: true,
            isMiddleClickToggleEnabled: false,
            middleClickActivationDelay: 220
        )
        let macOSShell = VoiceInkMacOSShellBackupPreferences(
            launchAtLoginEnabled: true,
            isMenuBarOnly: false,
            recorderType: "mini"
        )
        let transcriptionAutoCleanup = VoiceInkTranscriptionAutoCleanupBackupPreferences(
            isEnabled: true,
            retentionMinutes: 120
        )
        let audioCleanup = VoiceInkAudioCleanupBackupPreferences(
            isEnabled: false,
            retentionDays: 9
        )
        let recordingFeedback = VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: true,
            isSystemMuteEnabled: false,
            isPauseMediaEnabled: true,
            audioResumptionDelay: 2.5,
            isExperimentalFeaturesEnabled: false
        )
        let transcriptionCleanup = VoiceInkTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .removeTrailingPeriod,
            removePunctuation: true,
            lowercaseTranscription: true
        )
        let paste = VoiceInkPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: false,
            clipboardRestoreDelay: 1.25
        )
        XCTAssertEqual(
            VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
                recordingShortcut: recordingShortcut,
                macOSShell: macOSShell,
                transcriptionAutoCleanup: transcriptionAutoCleanup,
                audioCleanup: audioCleanup,
                recordingFeedback: recordingFeedback,
                transcriptionCleanup: transcriptionCleanup,
                paste: paste
            ),
            VoiceInkGeneralSettingsBackupPreferences(
                recordingShortcut: recordingShortcut,
                macOSShell: macOSShell,
                transcriptionAutoCleanup: transcriptionAutoCleanup,
                audioCleanup: audioCleanup,
                recordingFeedback: recordingFeedback,
                transcriptionCleanup: transcriptionCleanup,
                paste: paste
            )
        )
    }

    func testImportPlansApplySharedSubPolicies() {
        let preferences = VoiceInkGeneralSettingsBackupPreferences(
            recordingShortcut: VoiceInkRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.custom.rawValue,
                secondaryRecordingShortcutRawValue: "invalid",
                primaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.special.rawValue,
                secondaryRecordingShortcutModeRawValue: "invalid",
                specialShortcutPasteLastTranscriptOnEmptyTap: true,
                isMiddleClickToggleEnabled: true,
                middleClickActivationDelay: 180
            ),
            macOSShell: VoiceInkMacOSShellBackupPreferences(
                launchAtLoginEnabled: true,
                isMenuBarOnly: nil,
                recorderType: "mini"
            ),
            transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                isEnabled: false,
                retentionMinutes: 60
            ),
            audioCleanup: VoiceInkAudioCleanupBackupPreferences(
                isEnabled: true,
                retentionDays: 14
            ),
            recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: true,
                isSystemMuteEnabled: false,
                isPauseMediaEnabled: true,
                audioResumptionDelay: 2.0,
                isExperimentalFeaturesEnabled: false
            ),
            transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences(
                isTextFormattingEnabled: true,
                punctuationCleanupMode: .removeTrailingPeriod,
                removePunctuation: nil,
                lowercaseTranscription: false
            ),
            paste: VoiceInkPasteBackupPreferences(
                shouldRestoreClipboardAfterPaste: true,
                clipboardRestoreDelay: 3.0
            )
        )

        withIsolatedDefaults { defaults in
            let plans = VoiceInkGeneralSettingsBackupPolicy.importPlans(from: preferences)

            XCTAssertEqual(
                generalSettingsImportRuntimeEvents(for: plans, defaults: defaults),
                [
                    "recordingShortcut:custom:nil:special:nil:true:true:180",
                    "macOSShell:true:nil:mini",
                    "recordingFeedback:true:never:true:2.0:true",
                    "imported"
                ]
            )
            XCTAssertEqual(VoiceInkTranscriptionAutoCleanupPreference.retentionMinutes(from: defaults), 60)
            XCTAssertEqual(VoiceInkAudioCleanupPreference.retentionDays(from: defaults), 14)
            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeTrailingPeriod)
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 3.0)
        }
    }

    func testImportPlansPublicSurfaceAppliesRuntimeState() {
        let preferences = generalSettingsPublicSurfaceBackupPreferences()

        withIsolatedDefaults { defaults in
            let importPlans: VoiceInkGeneralSettingsBackupImportPlans = VoiceInkGeneralSettingsBackupPolicy.importPlans(
                from: preferences
            )
            var events = [String]()
            importPlans.applyRuntimeState(
                to: defaults,
                applyRecordingShortcutImportPlan: { _ in events.append("shortcut") },
                applyMacOSShellImportPlan: { _ in events.append("shell") },
                applyRecordingFeedbackImportPlan: { _ in events.append("feedback") },
                reportImportedGeneralSettings: { events.append("imported") }
            )

            XCTAssertEqual(events, ["shortcut", "shell", "feedback", "imported"])
        }
    }

    func testApplyCorePreferenceImportPlansWritesPortablePreferences() {
        withIsolatedDefaults { defaults in
            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(true, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveSoundFeedbackEnabled(false, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveSystemMuteMode(.automatic, to: defaults)
            VoiceInkRecordingFeedbackPreference.savePauseMediaEnabled(false, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveAudioResumptionDelay(0, to: defaults)

            VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
                VoiceInkGeneralSettingsBackupImportPlans(
                    recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan(
                        primaryRecordingShortcut: .custom,
                        secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection.none,
                        primaryRecordingShortcutMode: .toggle,
                        secondaryRecordingShortcutMode: .hybrid,
                        specialShortcutPasteLastTranscriptOnEmptyTap: false,
                        isMiddleClickToggleEnabled: true,
                        middleClickActivationDelay: 250
                    ),
                    macOSShell: VoiceInkMacOSShellBackupImportPlan(
                        launchAtLoginEnabled: true,
                        isMenuBarOnly: false,
                        recorderType: "mini"
                    ),
                    transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan(
                        isEnabled: true,
                        retentionMinutes: 45
                    ),
                    audioCleanup: VoiceInkAudioCleanupBackupImportPlan(
                        isEnabled: true,
                        retentionDays: 11
                    ),
                    recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan(
                        isSoundFeedbackEnabled: true,
                        systemMuteMode: .never,
                        isPauseMediaEnabled: true,
                        audioResumptionDelay: 4.0,
                        isExperimentalFeaturesEnabled: false
                    ),
                    transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan(
                        isTextFormattingEnabled: false,
                        punctuationCleanupMode: .removeTrailingPeriod,
                        lowercaseTranscription: true
                    ),
                    paste: VoiceInkPasteBackupImportPlan(
                        shouldRestoreClipboardAfterPaste: false,
                        clipboardRestoreDelay: 1.5
                    )
                ),
                to: defaults
            )
            XCTAssertTrue(VoiceInkTranscriptionAutoCleanupPreference.isEnabled(from: defaults))
            XCTAssertEqual(VoiceInkTranscriptionAutoCleanupPreference.retentionMinutes(from: defaults), 45)
            XCTAssertTrue(VoiceInkAudioCleanupPreference.isEnabled(from: defaults))
            XCTAssertEqual(VoiceInkAudioCleanupPreference.retentionDays(from: defaults), 11)
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabled(from: defaults))
            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isPauseMediaEnabled(from: defaults))
            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.audioResumptionDelay(from: defaults), 0)
            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeTrailingPeriod)
            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertFalse(VoiceInkPastePreference.shouldRestoreClipboardAfterPaste(from: defaults))
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 1.5)
        }
    }

    func testApplyCorePreferenceImportPlansIgnoresMissingFields() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(30, to: defaults)
            VoiceInkAudioCleanupPreference.saveRetentionDays(3, to: defaults)
            VoiceInkPastePreference.saveClipboardRestoreDelay(2.5, to: defaults)

            VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
                VoiceInkGeneralSettingsBackupImportPlans(
                    recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan(
                        primaryRecordingShortcut: nil,
                        secondaryRecordingShortcut: nil,
                        primaryRecordingShortcutMode: nil,
                        secondaryRecordingShortcutMode: nil,
                        specialShortcutPasteLastTranscriptOnEmptyTap: nil,
                        isMiddleClickToggleEnabled: nil,
                        middleClickActivationDelay: nil
                    ),
                    macOSShell: VoiceInkMacOSShellBackupImportPlan(
                        launchAtLoginEnabled: nil,
                        isMenuBarOnly: nil,
                        recorderType: nil
                    ),
                    transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan(
                        isEnabled: nil,
                        retentionMinutes: nil
                    ),
                    audioCleanup: VoiceInkAudioCleanupBackupImportPlan(
                        isEnabled: nil,
                        retentionDays: nil
                    ),
                    recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan(
                        isSoundFeedbackEnabled: nil,
                        systemMuteMode: nil,
                        isPauseMediaEnabled: nil,
                        audioResumptionDelay: nil,
                        isExperimentalFeaturesEnabled: nil
                    ),
                    transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan(
                        isTextFormattingEnabled: nil,
                        punctuationCleanupMode: nil,
                        lowercaseTranscription: nil
                    ),
                    paste: VoiceInkPasteBackupImportPlan(
                        shouldRestoreClipboardAfterPaste: nil,
                        clipboardRestoreDelay: nil
                    )
                ),
                to: defaults
            )
            XCTAssertEqual(VoiceInkTranscriptionAutoCleanupPreference.retentionMinutes(from: defaults), 30)
            XCTAssertEqual(VoiceInkAudioCleanupPreference.retentionDays(from: defaults), 3)
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 2.5)
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.UserDefaultsSettingsBackupPolicyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func generalSettingsBackupPreferencesFixture() -> VoiceInkGeneralSettingsBackupPreferences {
        VoiceInkGeneralSettingsBackupPreferences(
            recordingShortcut: VoiceInkRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.custom.rawValue,
                secondaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.none.rawValue,
                primaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.special.rawValue,
                secondaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.hybrid.rawValue,
                specialShortcutPasteLastTranscriptOnEmptyTap: true,
                isMiddleClickToggleEnabled: false,
                middleClickActivationDelay: 220
            ),
            macOSShell: VoiceInkMacOSShellBackupPreferences(
                launchAtLoginEnabled: true,
                isMenuBarOnly: false,
                recorderType: "mini"
            ),
            transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                isEnabled: true,
                retentionMinutes: 120
            ),
            audioCleanup: VoiceInkAudioCleanupBackupPreferences(
                isEnabled: false,
                retentionDays: 9
            ),
            recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: true,
                isSystemMuteEnabled: false,
                isPauseMediaEnabled: true,
                audioResumptionDelay: 2.5,
                isExperimentalFeaturesEnabled: false
            ),
            transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences(
                isTextFormattingEnabled: false,
                punctuationCleanupMode: .removeTrailingPeriod,
                removePunctuation: true,
                lowercaseTranscription: true
            ),
            paste: VoiceInkPasteBackupPreferences(
                shouldRestoreClipboardAfterPaste: false,
                clipboardRestoreDelay: 1.25
            )
        )
    }

    private func generalSettingsPublicSurfaceBackupPreferences() -> VoiceInkGeneralSettingsBackupPreferences {
        VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
            recordingShortcut: VoiceInkRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.custom.rawValue,
                secondaryRecordingShortcutRawValue: VoiceInkRecordingShortcutSelection.none.rawValue,
                primaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.special.rawValue,
                secondaryRecordingShortcutModeRawValue: VoiceInkRecordingShortcutMode.hybrid.rawValue,
                specialShortcutPasteLastTranscriptOnEmptyTap: true,
                isMiddleClickToggleEnabled: false,
                middleClickActivationDelay: 220
            ),
            macOSShell: VoiceInkMacOSShellBackupPreferences(
                launchAtLoginEnabled: true,
                isMenuBarOnly: false,
                recorderType: "mini"
            ),
            transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                isEnabled: true,
                retentionMinutes: 120
            ),
            audioCleanup: VoiceInkAudioCleanupBackupPreferences(
                isEnabled: false,
                retentionDays: 9
            ),
            recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: true,
                isSystemMuteEnabled: false,
                isPauseMediaEnabled: true,
                audioResumptionDelay: 2.5,
                isExperimentalFeaturesEnabled: false
            ),
            transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences(
                isTextFormattingEnabled: false,
                punctuationCleanupMode: .removeTrailingPeriod,
                removePunctuation: true,
                lowercaseTranscription: true
            ),
            paste: VoiceInkPasteBackupPreferences(
                shouldRestoreClipboardAfterPaste: false,
                clipboardRestoreDelay: 1.25
            )
        )
    }

    private func generalSettingsImportRuntimeEvents(
        for plans: VoiceInkGeneralSettingsBackupImportPlans,
        defaults: UserDefaults
    ) -> [String] {
        var events = [String]()
        let appendRecordingShortcut: (VoiceInkRecordingShortcutBackupImportPlan) -> Void = { plan in
            var primaryShortcut = "nil"
            var secondaryShortcut = "nil"
            var primaryMode = "nil"
            var secondaryMode = "nil"
            var pasteLastTranscriptOnEmptyTap = "nil"
            var middleClickEnabled = "nil"
            var middleClickDelay = "nil"
            plan.applyRuntimeState(
                setPrimaryRecordingShortcut: { primaryShortcut = $0.rawValue },
                setSecondaryRecordingShortcut: { secondaryShortcut = $0.rawValue },
                setPrimaryRecordingShortcutMode: { primaryMode = $0.rawValue },
                setSecondaryRecordingShortcutMode: { secondaryMode = $0.rawValue },
                setSpecialShortcutPasteLastTranscriptOnEmptyTap: {
                    pasteLastTranscriptOnEmptyTap = String($0)
                },
                setMiddleClickToggleEnabled: { middleClickEnabled = String($0) },
                setMiddleClickActivationDelay: { middleClickDelay = String($0) }
            )
            events.append(
                "recordingShortcut:\(primaryShortcut):\(secondaryShortcut):\(primaryMode):\(secondaryMode):\(pasteLastTranscriptOnEmptyTap):\(middleClickEnabled):\(middleClickDelay)"
            )
        }
        let appendMacOSShell: (VoiceInkMacOSShellBackupImportPlan) -> Void = { plan in
            var launchAtLogin = "nil"
            var menuOnly = "nil"
            var recorderType = "nil"
            plan.applyRuntimeState(
                setLaunchAtLoginEnabled: { launchAtLogin = String($0) },
                setMenuBarOnly: { menuOnly = String($0) },
                setRecorderType: { recorderType = $0 }
            )
            events.append("macOSShell:\(launchAtLogin):\(menuOnly):\(recorderType)")
        }
        let appendRecordingFeedback: (VoiceInkRecordingFeedbackBackupImportPlan) -> Void = { plan in
            var soundFeedback = "nil"
            var systemMuteMode = "nil"
            var pauseMedia = "nil"
            var audioResumptionDelay = "nil"
            var disablesPauseMedia = "false"
            plan.applyRuntimeState(
                setSoundFeedbackEnabled: { soundFeedback = String($0) },
                setSystemMuteMode: { systemMuteMode = $0.rawValue },
                setPauseMediaEnabled: { pauseMedia = String($0) },
                setAudioResumptionDelay: { audioResumptionDelay = String($0) },
                disablePauseMediaForExperimentalImport: { disablesPauseMedia = "true" }
            )
            events.append(
                "recordingFeedback:\(soundFeedback):\(systemMuteMode):\(pauseMedia):\(audioResumptionDelay):\(disablesPauseMedia)"
            )
        }

        plans.applyRuntimeState(
            to: defaults,
            applyRecordingShortcutImportPlan: appendRecordingShortcut,
            applyMacOSShellImportPlan: appendMacOSShell,
            applyRecordingFeedbackImportPlan: appendRecordingFeedback,
            reportImportedGeneralSettings: {
                events.append("imported")
            }
        )

        return events
    }
}
