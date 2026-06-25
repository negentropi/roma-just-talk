import Foundation

public struct VoiceInkGeneralSettingsBackupPreferences: Equatable, Sendable {
    public let recordingShortcut: VoiceInkRecordingShortcutBackupPreferences
    public let macOSShell: VoiceInkMacOSShellBackupPreferences
    public let transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences
    public let audioCleanup: VoiceInkAudioCleanupBackupPreferences
    public let recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences
    public let transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences
    public let paste: VoiceInkPasteBackupPreferences
    public let rollingBuffer: VoiceInkRollingBufferBackupPreferences

    public init(
        recordingShortcut: VoiceInkRecordingShortcutBackupPreferences,
        macOSShell: VoiceInkMacOSShellBackupPreferences,
        transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences,
        audioCleanup: VoiceInkAudioCleanupBackupPreferences,
        recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences,
        transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences,
        paste: VoiceInkPasteBackupPreferences,
        rollingBuffer: VoiceInkRollingBufferBackupPreferences
    ) {
        self.recordingShortcut = recordingShortcut
        self.macOSShell = macOSShell
        self.transcriptionAutoCleanup = transcriptionAutoCleanup
        self.audioCleanup = audioCleanup
        self.recordingFeedback = recordingFeedback
        self.transcriptionCleanup = transcriptionCleanup
        self.paste = paste
        self.rollingBuffer = rollingBuffer
    }
}

public struct VoiceInkGeneralSettingsBackupImportPlans: Equatable, Sendable {
    fileprivate let recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan
    fileprivate let macOSShell: VoiceInkMacOSShellBackupImportPlan
    fileprivate let transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan
    fileprivate let audioCleanup: VoiceInkAudioCleanupBackupImportPlan
    fileprivate let recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan
    fileprivate let transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan
    fileprivate let paste: VoiceInkPasteBackupImportPlan
    fileprivate let rollingBuffer: VoiceInkRollingBufferBackupImportPlan

    public init(
        recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan,
        macOSShell: VoiceInkMacOSShellBackupImportPlan,
        transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan,
        audioCleanup: VoiceInkAudioCleanupBackupImportPlan,
        recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan,
        transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan,
        paste: VoiceInkPasteBackupImportPlan,
        rollingBuffer: VoiceInkRollingBufferBackupImportPlan
    ) {
        self.recordingShortcut = recordingShortcut
        self.macOSShell = macOSShell
        self.transcriptionAutoCleanup = transcriptionAutoCleanup
        self.audioCleanup = audioCleanup
        self.recordingFeedback = recordingFeedback
        self.transcriptionCleanup = transcriptionCleanup
        self.paste = paste
        self.rollingBuffer = rollingBuffer
    }

    @discardableResult
    public func applyRuntimeState(
        to defaults: UserDefaults = .standard,
        applyRecordingShortcutImportPlan: (VoiceInkRecordingShortcutBackupImportPlan) -> Void,
        applyMacOSShellImportPlan: (VoiceInkMacOSShellBackupImportPlan) -> Void,
        applyRecordingFeedbackImportPlan: (VoiceInkRecordingFeedbackBackupImportPlan) -> Void,
        postCorePreferenceSettingsDidChange: () -> Void,
        reportImportedGeneralSettings: () -> Void
    ) -> VoiceInkGeneralSettingsCorePreferenceImportResult {
        applyRecordingShortcutImportPlan(recordingShortcut)
        applyMacOSShellImportPlan(macOSShell)
        applyRecordingFeedbackImportPlan(recordingFeedback)

        let result = VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
            self,
            to: defaults
        )
        if result.didImportRollingBufferSetting {
            postCorePreferenceSettingsDidChange()
        }

        reportImportedGeneralSettings()
        return result
    }
}

public struct VoiceInkGeneralSettingsCorePreferenceImportResult: Equatable, Sendable {
    public let didImportRollingBufferSetting: Bool

    public init(didImportRollingBufferSetting: Bool) {
        self.didImportRollingBufferSetting = didImportRollingBufferSetting
    }
}

public enum VoiceInkGeneralSettingsBackupPolicy {
    public static func backupPreferences(
        recordingShortcut: VoiceInkRecordingShortcutBackupPreferences,
        macOSShell: VoiceInkMacOSShellBackupPreferences,
        transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences,
        audioCleanup: VoiceInkAudioCleanupBackupPreferences,
        recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences,
        transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences,
        paste: VoiceInkPasteBackupPreferences,
        rollingBuffer: VoiceInkRollingBufferBackupPreferences
    ) -> VoiceInkGeneralSettingsBackupPreferences {
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
    }

    public static func importPlans(
        from preferences: VoiceInkGeneralSettingsBackupPreferences
    ) -> VoiceInkGeneralSettingsBackupImportPlans {
        VoiceInkGeneralSettingsBackupImportPlans(
            recordingShortcut: VoiceInkRecordingShortcutPreference.backupImportPlan(
                from: preferences.recordingShortcut
            ),
            macOSShell: VoiceInkMacOSShellBackupPreference.backupImportPlan(
                from: preferences.macOSShell
            ),
            transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
                from: preferences.transcriptionAutoCleanup
            ),
            audioCleanup: VoiceInkAudioCleanupPreference.backupImportPlan(
                from: preferences.audioCleanup
            ),
            recordingFeedback: VoiceInkRecordingFeedbackPreference.backupImportPlan(
                from: preferences.recordingFeedback
            ),
            transcriptionCleanup: VoiceInkTranscriptionCleanupSettings.backupImportPlan(
                from: preferences.transcriptionCleanup
            ),
            paste: VoiceInkPastePreference.backupImportPlan(
                from: preferences.paste
            ),
            rollingBuffer: VoiceInkRollingBufferPreloadSettings.backupImportPlan(
                from: preferences.rollingBuffer
            )
        )
    }

    @discardableResult
    public static func applyCorePreferenceImportPlans(
        _ importPlans: VoiceInkGeneralSettingsBackupImportPlans,
        to defaults: UserDefaults = .standard
    ) -> VoiceInkGeneralSettingsCorePreferenceImportResult {
        applyTranscriptionAutoCleanupImportPlan(importPlans.transcriptionAutoCleanup, to: defaults)
        applyAudioCleanupImportPlan(importPlans.audioCleanup, to: defaults)
        applyRecordingFeedbackCorePreferenceImportPlan(importPlans.recordingFeedback, to: defaults)
        applyTranscriptionCleanupImportPlan(importPlans.transcriptionCleanup, to: defaults)
        applyPasteImportPlan(importPlans.paste, to: defaults)

        var didImportRollingBufferSetting = VoiceInkRollingBufferPreloadSettings.saveImportedSettings(
            from: importPlans.rollingBuffer,
            to: defaults
        )
        if VoiceInkRollingBufferVADSettings.saveImportedModel(from: importPlans.rollingBuffer, to: defaults) {
            didImportRollingBufferSetting = true
        }

        return VoiceInkGeneralSettingsCorePreferenceImportResult(
            didImportRollingBufferSetting: didImportRollingBufferSetting
        )
    }

    private static func applyTranscriptionAutoCleanupImportPlan(
        _ importPlan: VoiceInkTranscriptionAutoCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isEnabled = importPlan.isEnabled {
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(isEnabled, to: defaults)
        }
        if let retentionMinutes = importPlan.retentionMinutes {
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(retentionMinutes, to: defaults)
        }
    }

    private static func applyAudioCleanupImportPlan(
        _ importPlan: VoiceInkAudioCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isEnabled = importPlan.isEnabled {
            VoiceInkAudioCleanupPreference.saveIsEnabled(isEnabled, to: defaults)
        }
        if let retentionDays = importPlan.retentionDays {
            VoiceInkAudioCleanupPreference.saveRetentionDays(retentionDays, to: defaults)
        }
    }

    private static func applyRecordingFeedbackCorePreferenceImportPlan(
        _ importPlan: VoiceInkRecordingFeedbackBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isExperimentalFeaturesEnabled = importPlan.isExperimentalFeaturesEnabled {
            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(
                isExperimentalFeaturesEnabled,
                to: defaults
            )
        }
    }

    private static func applyTranscriptionCleanupImportPlan(
        _ importPlan: VoiceInkTranscriptionCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isTextFormattingEnabled = importPlan.isTextFormattingEnabled {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(
                isTextFormattingEnabled,
                to: defaults
            )
        }
        if let punctuationCleanupMode = importPlan.punctuationCleanupMode {
            PunctuationCleanupMode.setCurrent(punctuationCleanupMode, in: defaults)
        }
        if let lowercaseTranscription = importPlan.lowercaseTranscription {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(
                lowercaseTranscription,
                to: defaults
            )
        }
    }

    private static func applyPasteImportPlan(
        _ importPlan: VoiceInkPasteBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let shouldRestoreClipboardAfterPaste = importPlan.shouldRestoreClipboardAfterPaste {
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(
                shouldRestoreClipboardAfterPaste,
                to: defaults
            )
        }
        if let clipboardRestoreDelay = importPlan.clipboardRestoreDelay {
            VoiceInkPastePreference.saveClipboardRestoreDelay(clipboardRestoreDelay, to: defaults)
        }
    }
}
