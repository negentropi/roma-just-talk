import Foundation
import VoiceInkCore

extension VoiceInkCustomCloudModelBackup {
    init(model: CustomCloudModel) {
        self.init(
            id: model.id,
            name: model.name,
            displayName: model.displayName,
            description: model.description,
            apiEndpoint: model.apiEndpoint,
            modelName: model.modelName,
            isMultilingualModel: model.isMultilingualModel,
            supportedLanguages: model.supportedLanguages,
            apiKey: nil
        )
    }

    func makeModel() -> CustomCloudModel {
        let importPlan = self.importPlan
        let model = CustomCloudModel(
            id: importPlan.id,
            name: importPlan.name,
            displayName: importPlan.displayName,
            description: importPlan.description,
            apiEndpoint: importPlan.apiEndpoint,
            modelName: importPlan.modelName,
            isMultilingual: importPlan.isMultilingualModel,
            supportedLanguages: importPlan.supportedLanguages
        )

        if let apiKey = importPlan.apiKeyToRestore {
            APIKeyManager.shared.saveCustomModelAPIKey(apiKey, forModelId: importPlan.id)
        }

        return model
    }
}

struct GeneralBackup: Codable {
    let primaryRecordingShortcut: ShortcutBackup?
    let secondaryRecordingShortcut: ShortcutBackup?
    let pasteLastTranscriptionShortcut: ShortcutBackup?
    let pasteLastEnhancementShortcut: ShortcutBackup?
    let retryLastTranscriptionShortcut: ShortcutBackup?
    let cancelRecorderShortcut: ShortcutBackup?
    let openHistoryWindowShortcut: ShortcutBackup?
    let quickAddToDictionaryShortcut: ShortcutBackup?
    let toggleEnhancementShortcut: ShortcutBackup?
    let primaryRecordingShortcutRawValue: String?
    let secondaryRecordingShortcutRawValue: String?
    let primaryRecordingShortcutModeRawValue: String?
    let secondaryRecordingShortcutModeRawValue: String?
    let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    let isMiddleClickToggleEnabled: Bool?
    let middleClickActivationDelay: Int?
    let launchAtLoginEnabled: Bool?
    let isMenuBarOnly: Bool?
    let recorderType: String?
    let isTranscriptionCleanupEnabled: Bool?
    let transcriptionRetentionMinutes: Int?
    let isAudioCleanupEnabled: Bool?
    let audioRetentionPeriod: Int?

    let isSoundFeedbackEnabled: Bool?
    let isSystemMuteEnabled: Bool?
    let isPauseMediaEnabled: Bool?
    let audioResumptionDelay: Double?
    let isTextFormattingEnabled: Bool?
    let punctuationCleanupMode: PunctuationCleanupMode?
    let removePunctuation: Bool?
    let lowercaseTranscription: Bool?
    let isExperimentalFeaturesEnabled: Bool?
    let restoreClipboardAfterPaste: Bool?
    let clipboardRestoreDelay: Double?
    let rollingBufferPreloadModeRawValue: String?
    let rollingBufferPreloadAutoDisableCloudModels: Bool?
    let rollingBufferPreloadAutoDisableLowBatteryLocalModels: Bool?
    let rollingBufferPreloadLowBatteryThresholdPercent: Int?
    let rollingBufferDurationSeconds: Double?
    let rollingBufferPreloadFinalization: Bool?
    let rollingBufferVADModel: String?
    let rollingBufferPreloadEnabledByModel: [String: Bool]?
}

extension GeneralBackup {
    init(
        shortcutBackupRecords: [VoiceInkShortcutActionIdentifier: ShortcutBackup],
        preferences: VoiceInkGeneralSettingsBackupPreferences
    ) {
        self.init(
            primaryRecordingShortcut: shortcutBackupRecords[.primaryRecording],
            secondaryRecordingShortcut: shortcutBackupRecords[.secondaryRecording],
            pasteLastTranscriptionShortcut: shortcutBackupRecords[.pasteLastTranscription],
            pasteLastEnhancementShortcut: shortcutBackupRecords[.pasteLastEnhancement],
            retryLastTranscriptionShortcut: shortcutBackupRecords[.retryLastTranscription],
            cancelRecorderShortcut: shortcutBackupRecords[.cancelRecorder],
            openHistoryWindowShortcut: shortcutBackupRecords[.openHistoryWindow],
            quickAddToDictionaryShortcut: shortcutBackupRecords[.quickAddToDictionary],
            toggleEnhancementShortcut: shortcutBackupRecords[.toggleEnhancement],
            primaryRecordingShortcutRawValue: preferences.recordingShortcut.primaryRecordingShortcutRawValue,
            secondaryRecordingShortcutRawValue: preferences.recordingShortcut.secondaryRecordingShortcutRawValue,
            primaryRecordingShortcutModeRawValue: preferences.recordingShortcut.primaryRecordingShortcutModeRawValue,
            secondaryRecordingShortcutModeRawValue: preferences.recordingShortcut.secondaryRecordingShortcutModeRawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: preferences.recordingShortcut.specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: preferences.recordingShortcut.isMiddleClickToggleEnabled,
            middleClickActivationDelay: preferences.recordingShortcut.middleClickActivationDelay,
            launchAtLoginEnabled: preferences.macOSShell.launchAtLoginEnabled,
            isMenuBarOnly: preferences.macOSShell.isMenuBarOnly,
            recorderType: preferences.macOSShell.recorderType,
            isTranscriptionCleanupEnabled: preferences.transcriptionAutoCleanup.isEnabled,
            transcriptionRetentionMinutes: preferences.transcriptionAutoCleanup.retentionMinutes,
            isAudioCleanupEnabled: preferences.audioCleanup.isEnabled,
            audioRetentionPeriod: preferences.audioCleanup.retentionDays,
            isSoundFeedbackEnabled: preferences.recordingFeedback.isSoundFeedbackEnabled,
            isSystemMuteEnabled: preferences.recordingFeedback.isSystemMuteEnabled,
            isPauseMediaEnabled: preferences.recordingFeedback.isPauseMediaEnabled,
            audioResumptionDelay: preferences.recordingFeedback.audioResumptionDelay,
            isTextFormattingEnabled: preferences.transcriptionCleanup.isTextFormattingEnabled,
            punctuationCleanupMode: preferences.transcriptionCleanup.punctuationCleanupMode,
            removePunctuation: preferences.transcriptionCleanup.removePunctuation,
            lowercaseTranscription: preferences.transcriptionCleanup.lowercaseTranscription,
            isExperimentalFeaturesEnabled: preferences.recordingFeedback.isExperimentalFeaturesEnabled,
            restoreClipboardAfterPaste: preferences.paste.shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: preferences.paste.clipboardRestoreDelay,
            rollingBufferPreloadModeRawValue: preferences.rollingBuffer.preloadModeRawValue,
            rollingBufferPreloadAutoDisableCloudModels: preferences.rollingBuffer.autoDisablesCloudModels,
            rollingBufferPreloadAutoDisableLowBatteryLocalModels: preferences.rollingBuffer.autoDisablesLowBatteryLocalModels,
            rollingBufferPreloadLowBatteryThresholdPercent: preferences.rollingBuffer.lowBatteryThresholdPercent,
            rollingBufferDurationSeconds: preferences.rollingBuffer.bufferDurationSeconds,
            rollingBufferPreloadFinalization: preferences.rollingBuffer.preRunFinalization,
            rollingBufferVADModel: preferences.rollingBuffer.vadModelRawValue,
            rollingBufferPreloadEnabledByModel: preferences.rollingBuffer.perModelPreloadEnabled
        )
    }

    var shortcutBackupRecords: [VoiceInkShortcutActionIdentifier: ShortcutBackup] {
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

    var generalSettingsBackupPreferences: VoiceInkGeneralSettingsBackupPreferences {
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

    var recordingShortcutBackupPreferences: VoiceInkRecordingShortcutBackupPreferences {
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

    var recordingFeedbackBackupPreferences: VoiceInkRecordingFeedbackBackupPreferences {
        VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    var macOSShellBackupPreferences: VoiceInkMacOSShellBackupPreferences {
        VoiceInkMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            isMenuBarOnly: isMenuBarOnly,
            recorderType: recorderType
        )
    }

    var pasteBackupPreferences: VoiceInkPasteBackupPreferences {
        VoiceInkPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: restoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    var transcriptionAutoCleanupBackupPreferences: VoiceInkTranscriptionAutoCleanupBackupPreferences {
        VoiceInkTranscriptionAutoCleanupBackupPreferences(
            isEnabled: isTranscriptionCleanupEnabled,
            retentionMinutes: transcriptionRetentionMinutes
        )
    }

    var audioCleanupBackupPreferences: VoiceInkAudioCleanupBackupPreferences {
        VoiceInkAudioCleanupBackupPreferences(
            isEnabled: isAudioCleanupEnabled,
            retentionDays: audioRetentionPeriod
        )
    }

    var transcriptionCleanupBackupPreferences: VoiceInkTranscriptionCleanupBackupPreferences {
        VoiceInkTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationCleanupMode: punctuationCleanupMode,
            removePunctuation: removePunctuation,
            lowercaseTranscription: lowercaseTranscription
        )
    }

    var rollingBufferBackupPreferences: VoiceInkRollingBufferBackupPreferences {
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

struct BackupFile: Codable {
    let version: String
    let customPrompts: [VoiceInkCustomPrompt]
    let powerModeConfigs: [PowerModeConfig]
    let powerModeShortcuts: [String: ShortcutBackup]?
    let vocabularyWords: [VoiceInkVocabularyWordBackup]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralBackup?
    let customEmojis: [String]?
    let customCloudModels: [VoiceInkCustomCloudModelBackup]?

    private enum CodingKeys: String, CodingKey {
        case version, customPrompts, powerModeConfigs, powerModeShortcuts, vocabularyWords, wordReplacements, generalSettings, customEmojis, customCloudModels
    }

    init(version: String, customPrompts: [VoiceInkCustomPrompt], powerModeConfigs: [PowerModeConfig], powerModeShortcuts: [String: ShortcutBackup]?, vocabularyWords: [VoiceInkVocabularyWordBackup]?, wordReplacements: [String: String]?, generalSettings: GeneralBackup?, customEmojis: [String]?, customCloudModels: [VoiceInkCustomCloudModelBackup]?) {
        self.version = version
        self.customPrompts = customPrompts
        self.powerModeConfigs = powerModeConfigs
        self.powerModeShortcuts = powerModeShortcuts
        self.vocabularyWords = vocabularyWords
        self.wordReplacements = wordReplacements
        self.generalSettings = generalSettings
        self.customEmojis = customEmojis
        self.customCloudModels = customCloudModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        customPrompts = try container.decodeIfPresent([VoiceInkCustomPrompt].self, forKey: .customPrompts) ?? []
        powerModeConfigs = try container.decodeIfPresent([PowerModeConfig].self, forKey: .powerModeConfigs) ?? []
        powerModeShortcuts = try container.decodeIfPresent([String: ShortcutBackup].self, forKey: .powerModeShortcuts)
        vocabularyWords = try container.decodeIfPresent([VoiceInkVocabularyWordBackup].self, forKey: .vocabularyWords)
        wordReplacements = try container.decodeIfPresent([String: String].self, forKey: .wordReplacements)
        generalSettings = try container.decodeIfPresent(GeneralBackup.self, forKey: .generalSettings)
        customEmojis = try container.decodeIfPresent([String].self, forKey: .customEmojis)
        customCloudModels = try container.decodeIfPresent([VoiceInkCustomCloudModelBackup].self, forKey: .customCloudModels)
    }
}
