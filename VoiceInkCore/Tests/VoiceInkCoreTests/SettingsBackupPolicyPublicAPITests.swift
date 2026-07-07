import Foundation
import VoiceInkCore

final class SettingsBackupPolicyPublicAPITests: XCTestCase {
    private struct TestShortcutBackup: Codable, Equatable {
        let shortcut: String
    }

    func testMovedSettingsBackupPolicySymbolsExposePublicAPI() throws {
        XCTAssertEqual(VoiceInkSettingsBackupCategory.general.title, "General Settings")
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(for: [.prompts, .dictionary]),
            "Custom Prompts, Dictionary"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.currentVersion(bundleShortVersion: nil),
            VoiceInkSettingsBackupImportPolicy.fallbackVersion
        )

        let versionReview = VoiceInkSettingsBackupVersionReview(
            importedVersion: "2.3.0",
            currentVersion: "2.4.0"
        )
        XCTAssertTrue(versionReview.hasMismatch)
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.versionReview(
                importedVersion: "2.3.0",
                currentVersion: "2.4.0"
            ),
            versionReview
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportSelectionReview(selectedCategories: nil),
            .canceled
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportSuccessPlan(categories: [.customModels]).isConfigureAPIKeysActionVisible,
            true
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.customModelsImportedMessage(count: 2),
            "Successfully imported 2 custom model definitions."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportError.saveFailed(
                item: "settings",
                localizedDescription: "disk full"
            ).errorDescription,
            "Failed to save imported settings: disk full"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupPresentation.macOS.defaultFileName,
            "VoiceInk_Settings_Backup.json"
        )

        let preferences = settingsBackupPreferences()
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

        withIsolatedDefaults { defaults in
            let importPlans: VoiceInkGeneralSettingsBackupImportPlans = VoiceInkGeneralSettingsBackupPolicy.importPlans(
                from: preferences
            )
            var events = [String]()
            let result = importPlans.applyRuntimeState(
                to: defaults,
                applyRecordingShortcutImportPlan: { _ in events.append("shortcut") },
                applyMacOSShellImportPlan: { _ in events.append("shell") },
                applyRecordingFeedbackImportPlan: { _ in events.append("feedback") },
                postCorePreferenceSettingsDidChange: { events.append("rolling") },
                reportImportedGeneralSettings: { events.append("imported") }
            )

            XCTAssertEqual(events, ["shortcut", "shell", "feedback", "imported"])
            XCTAssertEqual(
                result,
                VoiceInkGeneralSettingsCorePreferenceImportResult(didImportRollingBufferSetting: false)
            )
        }
    }

    private func settingsBackupPreferences() -> VoiceInkGeneralSettingsBackupPreferences {
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
            ),
            rollingBuffer: VoiceInkRollingBufferBackupPreferences(
                preloadModeRawValue: nil,
                autoDisablesCloudModels: nil,
                autoDisablesLowBatteryLocalModels: nil,
                lowBatteryThresholdPercent: nil,
                bufferDurationSeconds: nil,
                preRunFinalization: nil,
                vadModelRawValue: nil,
                perModelPreloadEnabled: nil
            )
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.SettingsBackupPolicyPublicAPITests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
