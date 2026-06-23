import Foundation
@testable import VoiceInkCore

final class GeneralSettingsBackupPolicyTests: XCTestCase {
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
        let rollingBuffer = VoiceInkRollingBufferBackupPreferences(
            preloadModeRawValue: VoiceInkRollingBufferPreloadMode.on.rawValue,
            autoDisablesCloudModels: true,
            autoDisablesLowBatteryLocalModels: false,
            lowBatteryThresholdPercent: 55,
            bufferDurationSeconds: 4.5,
            preRunFinalization: true,
            vadModelRawValue: VoiceInkRollingBufferVADModel.silero.rawValue,
            perModelPreloadEnabled: ["parakeet": false]
        )

        XCTAssertEqual(
            VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
                recordingShortcut: recordingShortcut,
                macOSShell: macOSShell,
                transcriptionAutoCleanup: transcriptionAutoCleanup,
                audioCleanup: audioCleanup,
                recordingFeedback: recordingFeedback,
                transcriptionCleanup: transcriptionCleanup,
                paste: paste,
                rollingBuffer: rollingBuffer
            ),
            VoiceInkGeneralSettingsBackupPreferences(
                recordingShortcut: recordingShortcut,
                macOSShell: macOSShell,
                transcriptionAutoCleanup: transcriptionAutoCleanup,
                audioCleanup: audioCleanup,
                recordingFeedback: recordingFeedback,
                transcriptionCleanup: transcriptionCleanup,
                paste: paste,
                rollingBuffer: rollingBuffer
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
            ),
            rollingBuffer: VoiceInkRollingBufferBackupPreferences(
                preloadModeRawValue: VoiceInkRollingBufferPreloadMode.on.rawValue,
                autoDisablesCloudModels: false,
                autoDisablesLowBatteryLocalModels: true,
                lowBatteryThresholdPercent: 150,
                bufferDurationSeconds: 60,
                preRunFinalization: false,
                vadModelRawValue: VoiceInkRollingBufferVADModel.silero.rawValue,
                perModelPreloadEnabled: ["parakeet": false]
            )
        )

        let plans = VoiceInkGeneralSettingsBackupPolicy.importPlans(from: preferences)

        XCTAssertEqual(plans.recordingShortcut.primaryRecordingShortcut, .custom)
        XCTAssertNil(plans.recordingShortcut.secondaryRecordingShortcut)
        XCTAssertEqual(plans.recordingShortcut.primaryRecordingShortcutMode, .special)
        XCTAssertNil(plans.recordingShortcut.secondaryRecordingShortcutMode)
        XCTAssertEqual(plans.macOSShell.launchAtLoginEnabled, true)
        XCTAssertNil(plans.macOSShell.isMenuBarOnly)
        XCTAssertEqual(plans.transcriptionAutoCleanup.retentionMinutes, 60)
        XCTAssertEqual(plans.audioCleanup.retentionDays, 14)
        XCTAssertEqual(plans.recordingFeedback.systemMuteMode, .never)
        XCTAssertTrue(plans.recordingFeedback.shouldDisablePauseMediaForExperimentalImport)
        XCTAssertEqual(plans.transcriptionCleanup.punctuationCleanupMode, .removeTrailingPeriod)
        XCTAssertEqual(plans.paste.clipboardRestoreDelay, 3.0)
        XCTAssertEqual(plans.rollingBuffer.mode, .on)
        XCTAssertEqual(plans.rollingBuffer.lowBatteryThresholdPercent, 100)
        XCTAssertEqual(plans.rollingBuffer.bufferDurationSeconds, 30.0)
        XCTAssertEqual(plans.rollingBuffer.vadModel, .silero)
    }

    func testApplyCorePreferenceImportPlansWritesPortablePreferences() {
        withIsolatedDefaults { defaults in
            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(true, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveSoundFeedbackEnabled(false, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveSystemMuteMode(.automatic, to: defaults)
            VoiceInkRecordingFeedbackPreference.savePauseMediaEnabled(false, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveAudioResumptionDelay(0, to: defaults)

            let result = VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
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
                    ),
                    rollingBuffer: VoiceInkRollingBufferBackupImportPlan(
                        mode: .on,
                        autoDisablesCloudModels: false,
                        autoDisablesLowBatteryLocalModels: true,
                        lowBatteryThresholdPercent: 33,
                        bufferDurationSeconds: 6.5,
                        preRunFinalization: true,
                        vadModel: .silero,
                        perModelPreloadEnabled: ["parakeet": false]
                    )
                ),
                to: defaults
            )

            XCTAssertTrue(result.didImportRollingBufferSetting)
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

            let rollingBufferConfiguration = VoiceInkRollingBufferPreloadSettings.configuration(in: defaults)
            XCTAssertEqual(rollingBufferConfiguration.mode, .on)
            XCTAssertFalse(rollingBufferConfiguration.autoDisablesCloudModels)
            XCTAssertTrue(rollingBufferConfiguration.autoDisablesLowBatteryLocalModels)
            XCTAssertEqual(rollingBufferConfiguration.lowBatteryThresholdPercent, 33)
            XCTAssertEqual(rollingBufferConfiguration.bufferDurationSeconds, 6.5)
            XCTAssertTrue(rollingBufferConfiguration.preRunFinalization)
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "silero")
            XCTAssertFalse(
                VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                    forModelName: "parakeet",
                    in: defaults
                )
            )
        }
    }

    func testApplyCorePreferenceImportPlansIgnoresMissingFields() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(30, to: defaults)
            VoiceInkAudioCleanupPreference.saveRetentionDays(3, to: defaults)
            VoiceInkPastePreference.saveClipboardRestoreDelay(2.5, to: defaults)

            let result = VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
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
                    ),
                    rollingBuffer: VoiceInkRollingBufferBackupImportPlan(
                        mode: nil,
                        autoDisablesCloudModels: nil,
                        autoDisablesLowBatteryLocalModels: nil,
                        lowBatteryThresholdPercent: nil,
                        bufferDurationSeconds: nil,
                        preRunFinalization: nil,
                        vadModel: nil,
                        perModelPreloadEnabled: nil
                    )
                ),
                to: defaults
            )

            XCTAssertFalse(result.didImportRollingBufferSetting)
            XCTAssertEqual(VoiceInkTranscriptionAutoCleanupPreference.retentionMinutes(from: defaults), 30)
            XCTAssertEqual(VoiceInkAudioCleanupPreference.retentionDays(from: defaults), 3)
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 2.5)
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.GeneralSettingsBackupPolicyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
