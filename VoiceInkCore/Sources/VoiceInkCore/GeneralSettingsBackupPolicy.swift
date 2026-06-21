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
    public let recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan
    public let macOSShell: VoiceInkMacOSShellBackupImportPlan
    public let transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan
    public let audioCleanup: VoiceInkAudioCleanupBackupImportPlan
    public let recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan
    public let transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan
    public let paste: VoiceInkPasteBackupImportPlan
    public let rollingBuffer: VoiceInkRollingBufferBackupImportPlan

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
}
