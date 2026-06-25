import Foundation

public struct VoiceInkGeneralSettingsBackupPayload<ShortcutBackup: Codable>: Codable {
    private let primaryRecordingShortcut: ShortcutBackup?
    private let secondaryRecordingShortcut: ShortcutBackup?
    private let pasteLastTranscriptionShortcut: ShortcutBackup?
    private let pasteLastEnhancementShortcut: ShortcutBackup?
    private let retryLastTranscriptionShortcut: ShortcutBackup?
    private let cancelRecorderShortcut: ShortcutBackup?
    private let openHistoryWindowShortcut: ShortcutBackup?
    private let quickAddToDictionaryShortcut: ShortcutBackup?
    private let toggleEnhancementShortcut: ShortcutBackup?
    private let primaryRecordingShortcutRawValue: String?
    private let secondaryRecordingShortcutRawValue: String?
    private let primaryRecordingShortcutModeRawValue: String?
    private let secondaryRecordingShortcutModeRawValue: String?
    private let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    private let isMiddleClickToggleEnabled: Bool?
    private let middleClickActivationDelay: Int?
    private let launchAtLoginEnabled: Bool?
    private let isMenuBarOnly: Bool?
    private let recorderType: String?
    private let isTranscriptionCleanupEnabled: Bool?
    private let transcriptionRetentionMinutes: Int?
    private let isAudioCleanupEnabled: Bool?
    private let audioRetentionPeriod: Int?
    private let isSoundFeedbackEnabled: Bool?
    private let isSystemMuteEnabled: Bool?
    private let isPauseMediaEnabled: Bool?
    private let audioResumptionDelay: Double?
    private let isTextFormattingEnabled: Bool?
    private let punctuationCleanupMode: PunctuationCleanupMode?
    private let removePunctuation: Bool?
    private let lowercaseTranscription: Bool?
    private let isExperimentalFeaturesEnabled: Bool?
    private let restoreClipboardAfterPaste: Bool?
    private let clipboardRestoreDelay: Double?
    private let rollingBufferPreloadModeRawValue: String?
    private let rollingBufferPreloadAutoDisableCloudModels: Bool?
    private let rollingBufferPreloadAutoDisableLowBatteryLocalModels: Bool?
    private let rollingBufferPreloadLowBatteryThresholdPercent: Int?
    private let rollingBufferDurationSeconds: Double?
    private let rollingBufferPreloadFinalization: Bool?
    private let rollingBufferVADModel: String?
    private let rollingBufferPreloadEnabledByModel: [String: Bool]?

    public init(
        shortcutBackupRecords: [VoiceInkShortcutActionIdentifier: ShortcutBackup],
        preferences: VoiceInkGeneralSettingsBackupPreferences
    ) {
        self.primaryRecordingShortcut = shortcutBackupRecords[.primaryRecording]
        self.secondaryRecordingShortcut = shortcutBackupRecords[.secondaryRecording]
        self.pasteLastTranscriptionShortcut = shortcutBackupRecords[.pasteLastTranscription]
        self.pasteLastEnhancementShortcut = shortcutBackupRecords[.pasteLastEnhancement]
        self.retryLastTranscriptionShortcut = shortcutBackupRecords[.retryLastTranscription]
        self.cancelRecorderShortcut = shortcutBackupRecords[.cancelRecorder]
        self.openHistoryWindowShortcut = shortcutBackupRecords[.openHistoryWindow]
        self.quickAddToDictionaryShortcut = shortcutBackupRecords[.quickAddToDictionary]
        self.toggleEnhancementShortcut = shortcutBackupRecords[.toggleEnhancement]
        self.primaryRecordingShortcutRawValue = preferences.recordingShortcut.primaryRecordingShortcutRawValue
        self.secondaryRecordingShortcutRawValue = preferences.recordingShortcut.secondaryRecordingShortcutRawValue
        self.primaryRecordingShortcutModeRawValue = preferences.recordingShortcut.primaryRecordingShortcutModeRawValue
        self.secondaryRecordingShortcutModeRawValue = preferences.recordingShortcut.secondaryRecordingShortcutModeRawValue
        self.specialShortcutPasteLastTranscriptOnEmptyTap = preferences.recordingShortcut.specialShortcutPasteLastTranscriptOnEmptyTap
        self.isMiddleClickToggleEnabled = preferences.recordingShortcut.isMiddleClickToggleEnabled
        self.middleClickActivationDelay = preferences.recordingShortcut.middleClickActivationDelay
        self.launchAtLoginEnabled = preferences.macOSShell.launchAtLoginEnabled
        self.isMenuBarOnly = preferences.macOSShell.isMenuBarOnly
        self.recorderType = preferences.macOSShell.recorderType
        self.isTranscriptionCleanupEnabled = preferences.transcriptionAutoCleanup.isEnabled
        self.transcriptionRetentionMinutes = preferences.transcriptionAutoCleanup.retentionMinutes
        self.isAudioCleanupEnabled = preferences.audioCleanup.isEnabled
        self.audioRetentionPeriod = preferences.audioCleanup.retentionDays
        self.isSoundFeedbackEnabled = preferences.recordingFeedback.isSoundFeedbackEnabled
        self.isSystemMuteEnabled = preferences.recordingFeedback.isSystemMuteEnabled
        self.isPauseMediaEnabled = preferences.recordingFeedback.isPauseMediaEnabled
        self.audioResumptionDelay = preferences.recordingFeedback.audioResumptionDelay
        self.isTextFormattingEnabled = preferences.transcriptionCleanup.isTextFormattingEnabled
        self.punctuationCleanupMode = preferences.transcriptionCleanup.punctuationCleanupMode
        self.removePunctuation = preferences.transcriptionCleanup.removePunctuation
        self.lowercaseTranscription = preferences.transcriptionCleanup.lowercaseTranscription
        self.isExperimentalFeaturesEnabled = preferences.recordingFeedback.isExperimentalFeaturesEnabled
        self.restoreClipboardAfterPaste = preferences.paste.shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = preferences.paste.clipboardRestoreDelay
        self.rollingBufferPreloadModeRawValue = preferences.rollingBuffer.preloadModeRawValue
        self.rollingBufferPreloadAutoDisableCloudModels = preferences.rollingBuffer.autoDisablesCloudModels
        self.rollingBufferPreloadAutoDisableLowBatteryLocalModels = preferences.rollingBuffer.autoDisablesLowBatteryLocalModels
        self.rollingBufferPreloadLowBatteryThresholdPercent = preferences.rollingBuffer.lowBatteryThresholdPercent
        self.rollingBufferDurationSeconds = preferences.rollingBuffer.bufferDurationSeconds
        self.rollingBufferPreloadFinalization = preferences.rollingBuffer.preRunFinalization
        self.rollingBufferVADModel = preferences.rollingBuffer.vadModelRawValue
        self.rollingBufferPreloadEnabledByModel = preferences.rollingBuffer.perModelPreloadEnabled
    }

    public var shortcutBackupRecords: [VoiceInkShortcutActionIdentifier: ShortcutBackup] {
        var records: [VoiceInkShortcutActionIdentifier: ShortcutBackup] = [:]
        records[.primaryRecording] = primaryRecordingShortcut
        records[.secondaryRecording] = secondaryRecordingShortcut
        records[.pasteLastTranscription] = pasteLastTranscriptionShortcut
        records[.pasteLastEnhancement] = pasteLastEnhancementShortcut
        records[.retryLastTranscription] = retryLastTranscriptionShortcut
        records[.cancelRecorder] = cancelRecorderShortcut
        records[.openHistoryWindow] = openHistoryWindowShortcut
        records[.quickAddToDictionary] = quickAddToDictionaryShortcut
        records[.toggleEnhancement] = toggleEnhancementShortcut
        return records
    }

    public var generalSettingsBackupPreferences: VoiceInkGeneralSettingsBackupPreferences {
        VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
            recordingShortcut: recordingShortcutBackupPreferences,
            macOSShell: macOSShellBackupPreferences,
            transcriptionAutoCleanup: transcriptionAutoCleanupBackupPreferences,
            audioCleanup: audioCleanupBackupPreferences,
            recordingFeedback: recordingFeedbackBackupPreferences,
            transcriptionCleanup: transcriptionCleanupBackupPreferences,
            paste: pasteBackupPreferences,
            rollingBuffer: rollingBufferBackupPreferences
        )
    }

    private var recordingShortcutBackupPreferences: VoiceInkRecordingShortcutBackupPreferences {
        VoiceInkRecordingShortcutBackupPreferences(
            primaryRecordingShortcutRawValue: primaryRecordingShortcutRawValue,
            secondaryRecordingShortcutRawValue: secondaryRecordingShortcutRawValue,
            primaryRecordingShortcutModeRawValue: primaryRecordingShortcutModeRawValue,
            secondaryRecordingShortcutModeRawValue: secondaryRecordingShortcutModeRawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: isMiddleClickToggleEnabled,
            middleClickActivationDelay: middleClickActivationDelay
        )
    }

    private var recordingFeedbackBackupPreferences: VoiceInkRecordingFeedbackBackupPreferences {
        VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    private var macOSShellBackupPreferences: VoiceInkMacOSShellBackupPreferences {
        VoiceInkMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            isMenuBarOnly: isMenuBarOnly,
            recorderType: recorderType
        )
    }

    private var pasteBackupPreferences: VoiceInkPasteBackupPreferences {
        VoiceInkPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: restoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    private var transcriptionAutoCleanupBackupPreferences: VoiceInkTranscriptionAutoCleanupBackupPreferences {
        VoiceInkTranscriptionAutoCleanupBackupPreferences(
            isEnabled: isTranscriptionCleanupEnabled,
            retentionMinutes: transcriptionRetentionMinutes
        )
    }

    private var audioCleanupBackupPreferences: VoiceInkAudioCleanupBackupPreferences {
        VoiceInkAudioCleanupBackupPreferences(
            isEnabled: isAudioCleanupEnabled,
            retentionDays: audioRetentionPeriod
        )
    }

    private var transcriptionCleanupBackupPreferences: VoiceInkTranscriptionCleanupBackupPreferences {
        VoiceInkTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationCleanupMode: punctuationCleanupMode,
            removePunctuation: removePunctuation,
            lowercaseTranscription: lowercaseTranscription
        )
    }

    private var rollingBufferBackupPreferences: VoiceInkRollingBufferBackupPreferences {
        VoiceInkRollingBufferBackupPreferences(
            preloadModeRawValue: rollingBufferPreloadModeRawValue,
            autoDisablesCloudModels: rollingBufferPreloadAutoDisableCloudModels,
            autoDisablesLowBatteryLocalModels: rollingBufferPreloadAutoDisableLowBatteryLocalModels,
            lowBatteryThresholdPercent: rollingBufferPreloadLowBatteryThresholdPercent,
            bufferDurationSeconds: rollingBufferDurationSeconds,
            preRunFinalization: rollingBufferPreloadFinalization,
            vadModelRawValue: rollingBufferVADModel,
            perModelPreloadEnabled: rollingBufferPreloadEnabledByModel
        )
    }
}

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
        importPlan.applyCorePreferenceState { isExperimentalFeaturesEnabled in
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
