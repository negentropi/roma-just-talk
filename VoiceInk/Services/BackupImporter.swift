import Foundation
import LaunchAtLogin
import SwiftData
import VoiceInkCore

enum BackupImporter {
    @MainActor
    static func apply(_ backup: VoiceInkSettingsBackupFile<ShortcutBackup>, categories: Set<VoiceInkSettingsBackupCategory>, enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) throws {
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
            let importPlan = VoiceInkCustomPromptPolicy.customPromptBackupImportPlan(
                importedPrompts: backup.customPrompts,
                currentPrompts: enhancementService.customPrompts
            )
            importPlan.applyRuntimeState(
                setPrompts: { prompts in
                    enhancementService.customPrompts = prompts
                },
                reportImportedPromptCount: { count in
                    print(
                        VoiceInkSettingsBackupImportDiagnostics.customPromptsImportedMessage(
                            count: count
                        )
                    )
                }
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
    private static func importGeneral(_ general: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager) {
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

        generalImportPlans.applyRuntimeState(
            applyRecordingShortcutImportPlan: { recordingShortcutImportPlan in
                recordingShortcutImportPlan.applyRuntimeState(
                    setPrimaryRecordingShortcut: { recordingShortcutManager.primaryRecordingShortcut = $0 },
                    setSecondaryRecordingShortcut: { recordingShortcutManager.secondaryRecordingShortcut = $0 },
                    setPrimaryRecordingShortcutMode: { recordingShortcutManager.primaryRecordingShortcutMode = $0 },
                    setSecondaryRecordingShortcutMode: { recordingShortcutManager.secondaryRecordingShortcutMode = $0 },
                    setSpecialShortcutPasteLastTranscriptOnEmptyTap: {
                        recordingShortcutManager.specialShortcutPasteLastTranscriptOnEmptyTap = $0
                    },
                    setMiddleClickToggleEnabled: { recordingShortcutManager.isMiddleClickToggleEnabled = $0 },
                    setMiddleClickActivationDelay: { recordingShortcutManager.middleClickActivationDelay = $0 }
                )
            },
            applyMacOSShellImportPlan: { macOSShellImportPlan in
                macOSShellImportPlan.applyRuntimeState(
                    setLaunchAtLoginEnabled: { LaunchAtLogin.isEnabled = $0 },
                    setMenuBarOnly: { menuBarManager.isMenuBarOnly = $0 },
                    setRecorderType: { recorderUIManager.recorderType = $0 }
                )
            },
            applyRecordingFeedbackImportPlan: { recordingFeedbackImportPlan in
                recordingFeedbackImportPlan.applyRuntimeState(
                    setSoundFeedbackEnabled: { soundManager.isEnabled = $0 },
                    setSystemMuteMode: { mediaController.systemMuteMode = $0 },
                    setPauseMediaEnabled: { playbackController.isPauseMediaEnabled = $0 },
                    setAudioResumptionDelay: { mediaController.audioResumptionDelay = $0 },
                    disablePauseMediaForExperimentalImport: {
                        playbackController.isPauseMediaEnabled = false
                    }
                )
            },
            postCorePreferenceSettingsDidChange: {
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            },
            reportImportedGeneralSettings: {
                print(VoiceInkSettingsBackupImportDiagnostics.generalSettingsImportedMessage)
            }
        )
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
    private static func importDictionary(from backup: VoiceInkSettingsBackupFile<ShortcutBackup>, modelContext: ModelContext) throws {
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

        do {
            try importPlan.applyRuntimeState(
                reportNoVocabularyBackupRecords: {
                    print(VoiceInkSettingsBackupImportDiagnostics.noVocabularyWordsMessage)
                },
                reportNoWordReplacementBackupRecords: {
                    print(VoiceInkSettingsBackupImportDiagnostics.noWordReplacementsMessage)
                },
                insertVocabularyWord: { word in
                    modelContext.insert(VocabularyWord(word: word))
                },
                insertWordReplacementRule: { rule in
                    modelContext.insert(WordReplacement(originalText: rule.originalText, replacementText: rule.replacementText))
                },
                reportNoDictionaryEntriesImported: {
                    print(VoiceInkSettingsBackupImportDiagnostics.noDictionaryEntriesImportedMessage)
                },
                save: modelContext.save,
                invalidateWordReplacementCache: WordReplacementService.shared.invalidateCache,
                reportImportedEntryCounts: { vocabularyWordCount, wordReplacementCount in
                    print(
                        VoiceInkSettingsBackupImportDiagnostics.dictionaryEntriesImportedMessage(
                            vocabularyWordCount: vocabularyWordCount,
                            wordReplacementCount: wordReplacementCount
                        )
                    )
                },
                reportSkippedInvalidReplacementCount: { count in
                    print(VoiceInkSettingsBackupImportDiagnostics.skippedInvalidReplacementsMessage(count: count))
                }
            )
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
        let customModelManager = CustomCloudModelManager.shared
        let importPlan = VoiceInkCustomCloudModelBackupImportPlan(backups: models)
        importPlan.applyRuntimeState(
            makeModel: { $0.makeModel() },
            setCustomModels: { customModelManager.customModels = $0 },
            saveCustomModels: customModelManager.saveCustomModels,
            refreshAvailableModels: transcriptionModelManager.refreshAllAvailableModels,
            reportNoCustomModels: {
                print(VoiceInkSettingsBackupImportDiagnostics.noCustomModelsMessage)
            },
            reportImportedModelCount: { count in
                print(
                    VoiceInkSettingsBackupImportDiagnostics.customModelsImportedMessage(
                        count: count
                    )
                )
            }
        )
    }

}
