import Foundation
import LaunchAtLogin
import SwiftData
import VoiceInkCore

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

            importPlan.applyRuntimeState(
                removeShortcutStorageForConfiguration: { id in
                    ShortcutStore.removeShortcutStorage(for: .powerMode(id))
                },
                setImportedConfigurations: { configurations in
                    powerModeManager.configurations = configurations
                },
                shortcutBackup: { key in
                    backup.powerModeShortcuts?[key]
                },
                importShortcut: { shortcutBackup, id in
                    ShortcutStore.setShortcut(shortcutBackup.shortcut, for: .powerMode(id))
                },
                saveConfigurations: powerModeManager.saveConfigurations,
                addCustomEmoji: { emoji in
                    _ = EmojiManager.shared.addCustomEmoji(emoji)
                },
                reportImportedConfigurationCount: { count in
                    print(
                        VoiceInkSettingsBackupImportDiagnostics.powerModeConfigurationsImportedMessage(
                            count: count
                        )
                    )
                }
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
        if recordingFeedbackImportPlan.shouldDisablePauseMediaForExperimentalImport {
            playbackController.isPauseMediaEnabled = false
        }
        let corePreferenceImportResult = VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
            generalImportPlans
        )
        if corePreferenceImportResult.didImportRollingBufferSetting {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }

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
                for: shortcutImport.actionIdentifier
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
            throw VoiceInkSettingsBackupImportError.saveFailed(
                item: "dictionary entries",
                localizedDescription: error.localizedDescription
            )
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
