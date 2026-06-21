import Foundation
import LaunchAtLogin
import SwiftData
import VoiceInkCore

enum BackupImportError: LocalizedError {
    case saveFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let error):
            return "Failed to save imported \(item): \(error.localizedDescription)"
        }
    }
}

enum BackupImporter {
    @MainActor
    static func apply(_ backup: BackupFile, categories: Set<VoiceInkSettingsBackupCategory>, enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) throws {
        if categories.contains(.dictionary) {
            try importDictionary(from: backup, modelContext: modelContext)
        }

        if categories.contains(.general) {
            importGeneral(
                backup.generalSettings,
                recordingShortcutManager: recordingShortcutManager,
                menuBarManager: menuBarManager,
                mediaController: mediaController,
                playbackController: playbackController,
                soundManager: soundManager,
                recorderUIManager: recorderUIManager
            )
        }

        if categories.contains(.prompts) {
            enhancementService.customPrompts = VoiceInkCustomPromptPolicy.promptsAfterImportingCustomPrompts(
                backup.customPrompts,
                currentPrompts: enhancementService.customPrompts
            )
            print("Successfully imported \(backup.customPrompts.count) custom prompts.")
        }

        if categories.contains(.powerMode) {
            let powerModeManager = PowerModeManager.shared
            for config in powerModeManager.configurations {
                ShortcutStore.removeShortcutStorage(for: .powerMode(config.id))
            }

            powerModeManager.configurations = backup.powerModeConfigs

            if let shortcuts = backup.powerModeShortcuts {
                let shortcutImports = VoiceInkPowerModePolicy.powerModeShortcutImports(
                    backupKeys: Array(shortcuts.keys),
                    importedConfigurations: backup.powerModeConfigs
                )
                for shortcutImport in shortcutImports {
                    guard let shortcutBackup = shortcuts[shortcutImport.backupKey] else { continue }
                    ShortcutStore.setShortcut(shortcutBackup.shortcut, for: .powerMode(shortcutImport.id))
                }
            }

            powerModeManager.saveConfigurations()

            if let customEmojis = backup.customEmojis {
                let emojiManager = EmojiManager.shared
                for emoji in customEmojis {
                    _ = emojiManager.addCustomEmoji(emoji)
                }
            }
            print("Successfully imported \(backup.powerModeConfigs.count) Power Mode configurations.")
        }

        if categories.contains(.customModels) {
            importCustomModels(backup.customCloudModels, transcriptionModelManager: transcriptionModelManager)
        }
    }

    @MainActor
    private static func importGeneral(_ general: GeneralBackup?, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager) {
        guard let general else {
            print("No general settings found in the imported file.")
            return
        }

        if let shortcut = general.primaryRecordingShortcut {
            ShortcutStore.setShortcut(shortcut.shortcut, for: .primaryRecording)
            recordingShortcutManager.primaryRecordingShortcut = .custom
        }
        if let shortcut2 = general.secondaryRecordingShortcut {
            ShortcutStore.setShortcut(shortcut2.shortcut, for: .secondaryRecording)
            recordingShortcutManager.secondaryRecordingShortcut = .custom
        }
        if let pasteShortcut = general.pasteLastTranscriptionShortcut {
            ShortcutStore.setShortcut(pasteShortcut.shortcut, for: .pasteLastTranscription)
        }
        if let pasteEnhancementShortcut = general.pasteLastEnhancementShortcut {
            ShortcutStore.setShortcut(pasteEnhancementShortcut.shortcut, for: .pasteLastEnhancement)
        }
        if let retryShortcut = general.retryLastTranscriptionShortcut {
            ShortcutStore.setShortcut(retryShortcut.shortcut, for: .retryLastTranscription)
        }
        if let cancelShortcut = general.cancelRecorderShortcut {
            ShortcutStore.setShortcut(cancelShortcut.shortcut, for: .cancelRecorder)
        }
        if let historyShortcut = general.openHistoryWindowShortcut {
            ShortcutStore.setShortcut(historyShortcut.shortcut, for: .openHistoryWindow)
        }
        if let dictionaryShortcut = general.quickAddToDictionaryShortcut {
            ShortcutStore.setShortcut(dictionaryShortcut.shortcut, for: .quickAddToDictionary)
        }
        if let enhancementShortcut = general.toggleEnhancementShortcut {
            ShortcutStore.setShortcut(enhancementShortcut.shortcut, for: .toggleEnhancement)
        }

        let recordingShortcutImportPlan = VoiceInkRecordingShortcutPreference.backupImportPlan(
            from: general.recordingShortcutBackupPreferences
        )
        if let shortcut = recordingShortcutImportPlan.primaryRecordingShortcut {
            recordingShortcutManager.primaryRecordingShortcut = shortcut
        }
        if let shortcut = recordingShortcutImportPlan.secondaryRecordingShortcut {
            recordingShortcutManager.secondaryRecordingShortcut = shortcut
        }
        if let mode = recordingShortcutImportPlan.primaryRecordingShortcutMode {
            recordingShortcutManager.primaryRecordingShortcutMode = mode
        }
        if let mode = recordingShortcutImportPlan.secondaryRecordingShortcutMode {
            recordingShortcutManager.secondaryRecordingShortcutMode = mode
        }
        if let pasteLastTranscriptOnEmptyTap = recordingShortcutImportPlan.specialShortcutPasteLastTranscriptOnEmptyTap {
            recordingShortcutManager.specialShortcutPasteLastTranscriptOnEmptyTap = pasteLastTranscriptOnEmptyTap
        }
        if let isMiddleClickToggleEnabled = recordingShortcutImportPlan.isMiddleClickToggleEnabled {
            recordingShortcutManager.isMiddleClickToggleEnabled = isMiddleClickToggleEnabled
        }
        if let middleClickActivationDelay = recordingShortcutImportPlan.middleClickActivationDelay {
            recordingShortcutManager.middleClickActivationDelay = middleClickActivationDelay
        }
        if let launch = general.launchAtLoginEnabled {
            LaunchAtLogin.isEnabled = launch
        }
        if let menuOnly = general.isMenuBarOnly {
            menuBarManager.isMenuBarOnly = menuOnly
        }
        if let recType = general.recorderType {
            recorderUIManager.recorderType = recType
        }

        let transcriptionAutoCleanupImportPlan = VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
            from: general.transcriptionAutoCleanupBackupPreferences
        )
        if let transcriptionCleanup = transcriptionAutoCleanupImportPlan.isEnabled {
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(transcriptionCleanup)
        }
        if let transcriptionMinutes = transcriptionAutoCleanupImportPlan.retentionMinutes {
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(transcriptionMinutes)
        }

        let audioCleanupImportPlan = VoiceInkAudioCleanupPreference.backupImportPlan(
            from: general.audioCleanupBackupPreferences
        )
        if let audioCleanup = audioCleanupImportPlan.isEnabled {
            VoiceInkAudioCleanupPreference.saveIsEnabled(audioCleanup)
        }
        if let audioRetention = audioCleanupImportPlan.retentionDays {
            VoiceInkAudioCleanupPreference.saveRetentionDays(audioRetention)
        }

        let recordingFeedbackImportPlan = VoiceInkRecordingFeedbackPreference.backupImportPlan(
            from: general.recordingFeedbackBackupPreferences,
            experimentalFeaturesEnabled: general.isExperimentalFeaturesEnabled
        )
        if let soundFeedback = recordingFeedbackImportPlan.isSoundFeedbackEnabled {
            soundManager.isEnabled = soundFeedback
        }
        if let systemMuteMode = recordingFeedbackImportPlan.systemMuteMode {
            mediaController.systemMuteMode = systemMuteMode
        }
        if let pauseMedia = recordingFeedbackImportPlan.isPauseMediaEnabled {
            playbackController.isPauseMediaEnabled = pauseMedia
        }
        if let audioDelay = recordingFeedbackImportPlan.audioResumptionDelay {
            mediaController.audioResumptionDelay = audioDelay
        }
        if let experimentalEnabled = recordingFeedbackImportPlan.isExperimentalFeaturesEnabled {
            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(experimentalEnabled)
        }
        if recordingFeedbackImportPlan.shouldDisablePauseMediaForExperimentalImport {
            playbackController.isPauseMediaEnabled = false
        }
        let transcriptionCleanupImportPlan = VoiceInkTranscriptionCleanupSettings.backupImportPlan(
            from: general.transcriptionCleanupBackupPreferences
        )
        if let textFormattingEnabled = transcriptionCleanupImportPlan.isTextFormattingEnabled {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(textFormattingEnabled)
        }
        if let punctuationCleanupMode = transcriptionCleanupImportPlan.punctuationCleanupMode {
            PunctuationCleanupMode.setCurrent(punctuationCleanupMode)
        }
        if let lowercaseTranscription = transcriptionCleanupImportPlan.lowercaseTranscription {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(lowercaseTranscription)
        }
        let pasteImportPlan = VoiceInkPastePreference.backupImportPlan(
            from: general.pasteBackupPreferences
        )
        if let restoreClipboard = pasteImportPlan.shouldRestoreClipboardAfterPaste {
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(restoreClipboard)
        }
        if let clipboardDelay = pasteImportPlan.clipboardRestoreDelay {
            VoiceInkPastePreference.saveClipboardRestoreDelay(clipboardDelay)
        }
        importRollingBufferSettings(general)

        print("Successfully imported general settings.")
    }

    private static func importRollingBufferSettings(_ general: GeneralBackup) {
        var didImportRollingBufferSetting = VoiceInkRollingBufferPreloadSettings.saveImportedSettings(
            modeRawValue: general.rollingBufferPreloadModeRawValue,
            autoDisablesCloudModels: general.rollingBufferPreloadAutoDisableCloudModels,
            autoDisablesLowBatteryLocalModels: general.rollingBufferPreloadAutoDisableLowBatteryLocalModels,
            lowBatteryThresholdPercent: general.rollingBufferPreloadLowBatteryThresholdPercent,
            bufferDurationSeconds: general.rollingBufferDurationSeconds,
            preRunFinalization: general.rollingBufferPreloadFinalization,
            perModelPreloadEnabled: general.rollingBufferPreloadEnabledByModel
        )

        if VoiceInkRollingBufferVADSettings.saveImportedModel(rawValue: general.rollingBufferVADModel) {
            didImportRollingBufferSetting = true
        }

        if didImportRollingBufferSetting {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @MainActor
    private static func importDictionary(from backup: BackupFile, modelContext: ModelContext) throws {
        let existingWords: [String]
        if backup.vocabularyWords != nil {
            let descriptor = FetchDescriptor<VocabularyWord>()
            existingWords = try modelContext.fetch(descriptor).map(\.word)
        } else {
            existingWords = []
        }

        let existingOriginalTexts: [String]
        if backup.wordReplacements != nil {
            let descriptor = FetchDescriptor<WordReplacement>()
            existingOriginalTexts = try modelContext.fetch(descriptor).map(\.originalText)
        } else {
            existingOriginalTexts = []
        }

        let importPlan = VoiceInkDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: backup.vocabularyWords,
            wordReplacements: backup.wordReplacements,
            existingWords: existingWords,
            existingOriginalTexts: existingOriginalTexts
        )

        if !importPlan.hasVocabularyBackupRecords {
            print("No vocabulary words found in the imported file. Existing items remain unchanged.")
        }
        if !importPlan.hasWordReplacementBackupRecords {
            print("No word replacements found in the imported file. Existing replacements remain unchanged.")
        }

        for word in importPlan.vocabularyWordsToInsert {
            modelContext.insert(VocabularyWord(word: word))
        }
        for rule in importPlan.wordReplacementRulesToInsert {
            modelContext.insert(WordReplacement(originalText: rule.originalText, replacementText: rule.replacementText))
        }

        guard importPlan.shouldSave else {
            print("No new dictionary entries were imported.")
            if importPlan.skippedInvalidReplacementCount > 0 {
                print("Skipped \(importPlan.skippedInvalidReplacementCount) invalid word replacements from the imported file.")
            }
            return
        }

        do {
            try modelContext.save()
            if importPlan.shouldInvalidateWordReplacementCache {
                WordReplacementService.shared.invalidateCache()
            }
            print("Successfully imported \(importPlan.insertedVocabularyWordCount) vocabulary words and \(importPlan.insertedWordReplacementCount) word replacements to SwiftData.")
            if importPlan.skippedInvalidReplacementCount > 0 {
                print("Skipped \(importPlan.skippedInvalidReplacementCount) invalid word replacements from the imported file.")
            }
        } catch {
            modelContext.rollback()
            throw BackupImportError.saveFailed("dictionary entries", error)
        }
    }

    @MainActor
    private static func importCustomModels(_ models: [VoiceInkCustomCloudModelBackup]?, transcriptionModelManager: TranscriptionModelManager) {
        guard let models else {
            print("No custom models found in the imported file.")
            return
        }

        let customModelManager = CustomCloudModelManager.shared
        customModelManager.customModels = models.map { $0.makeModel() }
        customModelManager.saveCustomModels()
        transcriptionModelManager.refreshAllAvailableModels()
        print("Successfully imported \(models.count) custom model definitions.")
    }

}
