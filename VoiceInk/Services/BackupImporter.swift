import Foundation
import LaunchAtLogin
import SwiftData
import VoiceInkCore

enum BackupImportError: LocalizedError {
    case saveFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let error):
            return VoiceInkSettingsBackupImportDiagnostics.saveFailedDescription(
                item: item,
                localizedDescription: error.localizedDescription
            )
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
            print(
                VoiceInkSettingsBackupImportDiagnostics.customPromptsImportedMessage(
                    count: backup.customPrompts.count
                )
            )
        }

        if categories.contains(.powerMode) {
            let powerModeManager = PowerModeManager.shared
            let importPlan = VoiceInkPowerModePolicy.powerModeBackupImportPlan(
                existingConfigurations: powerModeManager.configurations,
                importedConfigurations: backup.powerModeConfigs,
                backupShortcutKeys: backup.powerModeShortcuts.map { Array($0.keys) } ?? [],
                customEmojis: backup.customEmojis
            )

            for id in importPlan.existingConfigurationIdsToClear {
                ShortcutStore.removeShortcutStorage(for: .powerMode(id))
            }

            powerModeManager.configurations = importPlan.importedConfigurations

            for shortcutImport in importPlan.shortcutImports {
                guard let shortcutBackup = backup.powerModeShortcuts?[shortcutImport.backupKey] else { continue }
                ShortcutStore.setShortcut(shortcutBackup.shortcut, for: .powerMode(shortcutImport.id))
            }

            powerModeManager.saveConfigurations()

            if importPlan.hasCustomEmojiBackupRecord {
                let emojiManager = EmojiManager.shared
                for emoji in importPlan.customEmojisToImport {
                    _ = emojiManager.addCustomEmoji(emoji)
                }
            }
            print(
                VoiceInkSettingsBackupImportDiagnostics.powerModeConfigurationsImportedMessage(
                    count: importPlan.importedConfigurationCount
                )
            )
        }

        if categories.contains(.customModels) {
            importCustomModels(backup.customCloudModels, transcriptionModelManager: transcriptionModelManager)
        }
    }

    @MainActor
    private static func importGeneral(_ general: GeneralBackup?, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager) {
        guard let general else {
            print(VoiceInkSettingsBackupImportDiagnostics.noGeneralSettingsMessage)
            return
        }

        importShortcutBackups(
            general.shortcutBackupRecords,
            recordingShortcutManager: recordingShortcutManager
        )

        let generalImportPlans = VoiceInkGeneralSettingsBackupPolicy.importPlans(
            from: general.generalSettingsBackupPreferences
        )

        let recordingShortcutImportPlan = generalImportPlans.recordingShortcut
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
        let macOSShellImportPlan = generalImportPlans.macOSShell
        if let launch = macOSShellImportPlan.launchAtLoginEnabled {
            LaunchAtLogin.isEnabled = launch
        }
        if let menuOnly = macOSShellImportPlan.isMenuBarOnly {
            menuBarManager.isMenuBarOnly = menuOnly
        }
        if let recType = macOSShellImportPlan.recorderType {
            recorderUIManager.recorderType = recType
        }

        let transcriptionAutoCleanupImportPlan = generalImportPlans.transcriptionAutoCleanup
        if let transcriptionCleanup = transcriptionAutoCleanupImportPlan.isEnabled {
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(transcriptionCleanup)
        }
        if let transcriptionMinutes = transcriptionAutoCleanupImportPlan.retentionMinutes {
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(transcriptionMinutes)
        }

        let audioCleanupImportPlan = generalImportPlans.audioCleanup
        if let audioCleanup = audioCleanupImportPlan.isEnabled {
            VoiceInkAudioCleanupPreference.saveIsEnabled(audioCleanup)
        }
        if let audioRetention = audioCleanupImportPlan.retentionDays {
            VoiceInkAudioCleanupPreference.saveRetentionDays(audioRetention)
        }

        let recordingFeedbackImportPlan = generalImportPlans.recordingFeedback
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
        let transcriptionCleanupImportPlan = generalImportPlans.transcriptionCleanup
        if let textFormattingEnabled = transcriptionCleanupImportPlan.isTextFormattingEnabled {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(textFormattingEnabled)
        }
        if let punctuationCleanupMode = transcriptionCleanupImportPlan.punctuationCleanupMode {
            PunctuationCleanupMode.setCurrent(punctuationCleanupMode)
        }
        if let lowercaseTranscription = transcriptionCleanupImportPlan.lowercaseTranscription {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(lowercaseTranscription)
        }
        let pasteImportPlan = generalImportPlans.paste
        if let restoreClipboard = pasteImportPlan.shouldRestoreClipboardAfterPaste {
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(restoreClipboard)
        }
        if let clipboardDelay = pasteImportPlan.clipboardRestoreDelay {
            VoiceInkPastePreference.saveClipboardRestoreDelay(clipboardDelay)
        }
        importRollingBufferSettings(generalImportPlans.rollingBuffer)

        print(VoiceInkSettingsBackupImportDiagnostics.generalSettingsImportedMessage)
    }

    @MainActor
    private static func importShortcutBackups(
        _ shortcutBackups: [VoiceInkShortcutActionIdentifier: ShortcutBackup],
        recordingShortcutManager: RecordingShortcutManager
    ) {
        let shortcutImportPlan = VoiceInkShortcutBackupPolicy.generalBackupShortcutImportPlan(
            importedActionIdentifiers: Set(shortcutBackups.keys)
        )

        for shortcutImport in shortcutImportPlan {
            guard let shortcutBackup = shortcutBackups[shortcutImport.actionIdentifier] else {
                continue
            }

            ShortcutStore.setShortcut(
                shortcutBackup.shortcut,
                for: ShortcutAction(coreIdentifier: shortcutImport.actionIdentifier)
            )

            guard let recordingShortcutSelection = shortcutImport.recordingShortcutSelection else {
                continue
            }

            switch shortcutImport.recordingShortcutSlot {
            case .some(.primary):
                recordingShortcutManager.primaryRecordingShortcut = recordingShortcutSelection
            case .some(.secondary):
                recordingShortcutManager.secondaryRecordingShortcut = recordingShortcutSelection
            case .none:
                break
            }
        }
    }

    private static func importRollingBufferSettings(_ rollingBufferImportPlan: VoiceInkRollingBufferBackupImportPlan) {
        var didImportRollingBufferSetting = VoiceInkRollingBufferPreloadSettings.saveImportedSettings(
            from: rollingBufferImportPlan
        )

        if VoiceInkRollingBufferVADSettings.saveImportedModel(from: rollingBufferImportPlan) {
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
            print(VoiceInkSettingsBackupImportDiagnostics.noVocabularyWordsMessage)
        }
        if !importPlan.hasWordReplacementBackupRecords {
            print(VoiceInkSettingsBackupImportDiagnostics.noWordReplacementsMessage)
        }

        for word in importPlan.vocabularyWordsToInsert {
            modelContext.insert(VocabularyWord(word: word))
        }
        for rule in importPlan.wordReplacementRulesToInsert {
            modelContext.insert(WordReplacement(originalText: rule.originalText, replacementText: rule.replacementText))
        }

        guard importPlan.shouldSave else {
            print(VoiceInkSettingsBackupImportDiagnostics.noDictionaryEntriesImportedMessage)
            if importPlan.skippedInvalidReplacementCount > 0 {
                print(
                    VoiceInkSettingsBackupImportDiagnostics.skippedInvalidReplacementsMessage(
                        count: importPlan.skippedInvalidReplacementCount
                    )
                )
            }
            return
        }

        do {
            try modelContext.save()
            if importPlan.shouldInvalidateWordReplacementCache {
                WordReplacementService.shared.invalidateCache()
            }
            print(
                VoiceInkSettingsBackupImportDiagnostics.dictionaryEntriesImportedMessage(
                    vocabularyWordCount: importPlan.insertedVocabularyWordCount,
                    wordReplacementCount: importPlan.insertedWordReplacementCount
                )
            )
            if importPlan.skippedInvalidReplacementCount > 0 {
                print(
                    VoiceInkSettingsBackupImportDiagnostics.skippedInvalidReplacementsMessage(
                        count: importPlan.skippedInvalidReplacementCount
                    )
                )
            }
        } catch {
            modelContext.rollback()
            throw BackupImportError.saveFailed("dictionary entries", error)
        }
    }

    @MainActor
    private static func importCustomModels(_ models: [VoiceInkCustomCloudModelBackup]?, transcriptionModelManager: TranscriptionModelManager) {
        guard let models else {
            print(VoiceInkSettingsBackupImportDiagnostics.noCustomModelsMessage)
            return
        }

        let customModelManager = CustomCloudModelManager.shared
        customModelManager.customModels = models.map { $0.makeModel() }
        customModelManager.saveCustomModels()
        transcriptionModelManager.refreshAllAvailableModels()
        print(
            VoiceInkSettingsBackupImportDiagnostics.customModelsImportedMessage(
                count: models.count
            )
        )
    }

}
