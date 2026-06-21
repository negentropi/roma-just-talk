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
}
