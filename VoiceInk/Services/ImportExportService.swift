import Foundation
import AppKit
import UniformTypeIdentifiers
import LaunchAtLogin
import SwiftData
import VoiceInkCore

private final class BackupOptions: NSObject {
    let view: NSView

    private let allButton: NSButton
    private let individualButton: NSButton
    private let categoryButtons: [VoiceInkSettingsBackupCategory: NSButton]

    override init() {
        let presentation = VoiceInkSettingsBackupPresentation.macOS
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 188))
        self.allButton = NSButton(radioButtonWithTitle: presentation.allCategoriesTitle, target: nil, action: nil)
        self.individualButton = NSButton(radioButtonWithTitle: presentation.individualCategoriesTitle, target: nil, action: nil)

        var buttons: [VoiceInkSettingsBackupCategory: NSButton] = [:]
        for category in VoiceInkSettingsBackupCategory.allCases {
            let button = NSButton(checkboxWithTitle: category.title, target: nil, action: nil)
            button.state = .on
            button.isEnabled = false
            buttons[category] = button
        }
        self.categoryButtons = buttons

        super.init()

        allButton.state = .on
        individualButton.state = .off
        allButton.target = self
        allButton.action = #selector(modeChanged(_:))
        individualButton.target = self
        individualButton.action = #selector(modeChanged(_:))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let categoryStack = NSStackView()
        categoryStack.orientation = .vertical
        categoryStack.alignment = .leading
        categoryStack.spacing = 6
        categoryStack.translatesAutoresizingMaskIntoConstraints = false

        for category in VoiceInkSettingsBackupCategory.allCases {
            guard let button = categoryButtons[category] else { continue }
            button.target = self
            button.action = #selector(categoryChanged(_:))
            categoryStack.addArrangedSubview(button)
        }

        view.addSubview(stack)
        view.addSubview(categoryStack)
        stack.addArrangedSubview(allButton)
        stack.addArrangedSubview(individualButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            categoryStack.topAnchor.constraint(equalTo: individualButton.bottomAnchor, constant: 6),
            categoryStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            categoryStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    var selectedCategories: Set<VoiceInkSettingsBackupCategory> {
        if allButton.state == .on {
            return Set(VoiceInkSettingsBackupCategory.allCases)
        }

        return Set(categoryButtons.compactMap { category, button in
            button.state == .on ? category : nil
        })
    }

    @objc private func modeChanged(_ sender: NSButton) {
        let useAll = sender == allButton
        allButton.state = useAll ? .on : .off
        individualButton.state = useAll ? .off : .on
        setCategoryButtonsEnabled(!useAll)
    }

    @objc private func categoryChanged(_ sender: NSButton) {
        guard individualButton.state != .on else { return }
        allButton.state = .off
        individualButton.state = .on
        setCategoryButtonsEnabled(true)
    }

    private func setCategoryButtonsEnabled(_ isEnabled: Bool) {
        for button in categoryButtons.values {
            button.isEnabled = isEnabled
        }
    }
}

class ImportExportService {
    static let shared = ImportExportService()
    private let backupPresentation = VoiceInkSettingsBackupPresentation.macOS
    private let currentSettingsVersion: String

    private init() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            self.currentSettingsVersion = version
        } else {
            self.currentSettingsVersion = "0.0.0"
        }
    }

    @MainActor
    func exportSettings(enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext) {
        let powerModeManager = PowerModeManager.shared
        let emojiManager = EmojiManager.shared

        let exportablePrompts = VoiceInkCustomPromptPolicy.exportedCustomPrompts(
            from: enhancementService.customPrompts
        )

        let powerConfigs = powerModeManager.configurations
        let powerModeShortcuts = Dictionary(uniqueKeysWithValues: powerConfigs.compactMap { config -> (String, ShortcutBackup)? in
            guard let shortcut = ShortcutStore.shortcut(for: .powerMode(config.id)) else { return nil }
            return (config.id.uuidString, ShortcutBackup(shortcut))
        })

        // Export custom models
        let customModels = CustomCloudModelManager.shared.customModels.map { VoiceInkCustomCloudModelBackup(model: $0) }

        let vocabularyDescriptor = FetchDescriptor<VocabularyWord>()
        let vocabularyWords = (try? modelContext.fetch(vocabularyDescriptor).map(\.word)) ?? []

        let replacementsDescriptor = FetchDescriptor<WordReplacement>()
        let wordReplacementRules = (try? modelContext.fetch(replacementsDescriptor).map {
            VoiceInkWordReplacementRule(originalText: $0.originalText, replacementText: $0.replacementText)
        }) ?? []
        let dictionaryExportPlan = VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
            vocabularyWords: vocabularyWords,
            wordReplacementRules: wordReplacementRules
        )

        let cleanupSettings = VoiceInkTranscriptionCleanupSettings.current()
        let transcriptionCleanup = VoiceInkTranscriptionAutoCleanupPreference.current()
        let audioCleanup = VoiceInkAudioCleanupPreference.current()
        let transcriptionAutoCleanupBackupPreferences = VoiceInkTranscriptionAutoCleanupPreference.backupPreferences(
            from: transcriptionCleanup
        )
        let audioCleanupBackupPreferences = VoiceInkAudioCleanupPreference.backupPreferences(
            from: audioCleanup
        )
        let rollingBufferConfiguration = VoiceInkRollingBufferPreloadSettings.configuration()
        let perModelPreloadSettings = VoiceInkRollingBufferPreloadSettings.exportedPerModelPreloadEnabled()
        let recordingFeedbackBackupPreferences = VoiceInkRecordingFeedbackPreference.backupPreferences(
            isSoundFeedbackEnabled: soundManager.isEnabled,
            isSystemMuteEnabled: mediaController.isSystemMuteEnabled,
            isPauseMediaEnabled: playbackController.isPauseMediaEnabled,
            audioResumptionDelay: mediaController.audioResumptionDelay
        )
        let pasteBackupPreferences = VoiceInkPastePreference.backupPreferences(
            shouldRestoreClipboardAfterPaste: VoiceInkPastePreference.shouldRestoreClipboardAfterPaste(),
            clipboardRestoreDelay: VoiceInkPastePreference.clipboardRestoreDelay()
        )
        let transcriptionCleanupBackupPreferences = cleanupSettings.backupPreferences
        let recordingShortcutBackupPreferences = VoiceInkRecordingShortcutPreference.backupPreferences(
            primaryRecordingShortcut: recordingShortcutManager.primaryRecordingShortcut,
            secondaryRecordingShortcut: recordingShortcutManager.secondaryRecordingShortcut,
            primaryRecordingShortcutMode: recordingShortcutManager.primaryRecordingShortcutMode,
            secondaryRecordingShortcutMode: recordingShortcutManager.secondaryRecordingShortcutMode,
            specialShortcutPasteLastTranscriptOnEmptyTap: recordingShortcutManager.specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: recordingShortcutManager.isMiddleClickToggleEnabled,
            middleClickActivationDelay: recordingShortcutManager.middleClickActivationDelay
        )
        let generalSettingsToExport = GeneralBackup(
            primaryRecordingShortcut: ShortcutStore.shortcut(for: .primaryRecording).map(ShortcutBackup.init),
            secondaryRecordingShortcut: ShortcutStore.shortcut(for: .secondaryRecording).map(ShortcutBackup.init),
            pasteLastTranscriptionShortcut: ShortcutStore.shortcut(for: .pasteLastTranscription).map(ShortcutBackup.init),
            pasteLastEnhancementShortcut: ShortcutStore.shortcut(for: .pasteLastEnhancement).map(ShortcutBackup.init),
            retryLastTranscriptionShortcut: ShortcutStore.shortcut(for: .retryLastTranscription).map(ShortcutBackup.init),
            cancelRecorderShortcut: ShortcutStore.shortcut(for: .cancelRecorder).map(ShortcutBackup.init),
            openHistoryWindowShortcut: ShortcutStore.shortcut(for: .openHistoryWindow).map(ShortcutBackup.init),
            quickAddToDictionaryShortcut: ShortcutStore.shortcut(for: .quickAddToDictionary).map(ShortcutBackup.init),
            toggleEnhancementShortcut: ShortcutStore.shortcut(for: .toggleEnhancement).map(ShortcutBackup.init),
            primaryRecordingShortcutRawValue: recordingShortcutBackupPreferences.primaryRecordingShortcutRawValue,
            secondaryRecordingShortcutRawValue: recordingShortcutBackupPreferences.secondaryRecordingShortcutRawValue,
            primaryRecordingShortcutModeRawValue: recordingShortcutBackupPreferences.primaryRecordingShortcutModeRawValue,
            secondaryRecordingShortcutModeRawValue: recordingShortcutBackupPreferences.secondaryRecordingShortcutModeRawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: recordingShortcutBackupPreferences.specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: recordingShortcutBackupPreferences.isMiddleClickToggleEnabled,
            middleClickActivationDelay: recordingShortcutBackupPreferences.middleClickActivationDelay,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            isMenuBarOnly: menuBarManager.isMenuBarOnly,
            recorderType: recorderUIManager.recorderType,
            isTranscriptionCleanupEnabled: transcriptionAutoCleanupBackupPreferences.isEnabled,
            transcriptionRetentionMinutes: transcriptionAutoCleanupBackupPreferences.retentionMinutes,
            isAudioCleanupEnabled: audioCleanupBackupPreferences.isEnabled,
            audioRetentionPeriod: audioCleanupBackupPreferences.retentionDays,

            isSoundFeedbackEnabled: recordingFeedbackBackupPreferences.isSoundFeedbackEnabled,
            isSystemMuteEnabled: recordingFeedbackBackupPreferences.isSystemMuteEnabled,
            isPauseMediaEnabled: recordingFeedbackBackupPreferences.isPauseMediaEnabled,
            audioResumptionDelay: recordingFeedbackBackupPreferences.audioResumptionDelay,
            isTextFormattingEnabled: transcriptionCleanupBackupPreferences.isTextFormattingEnabled,
            punctuationCleanupMode: transcriptionCleanupBackupPreferences.punctuationCleanupMode,
            removePunctuation: transcriptionCleanupBackupPreferences.removePunctuation,
            lowercaseTranscription: transcriptionCleanupBackupPreferences.lowercaseTranscription,
            isExperimentalFeaturesEnabled: VoiceInkRecordingFeedbackPreference.isExperimentalFeaturesEnabled(),
            restoreClipboardAfterPaste: pasteBackupPreferences.shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: pasteBackupPreferences.clipboardRestoreDelay,
            rollingBufferPreloadModeRawValue: rollingBufferConfiguration.mode.rawValue,
            rollingBufferPreloadAutoDisableCloudModels: rollingBufferConfiguration.autoDisablesCloudModels,
            rollingBufferPreloadAutoDisableLowBatteryLocalModels: rollingBufferConfiguration.autoDisablesLowBatteryLocalModels,
            rollingBufferPreloadLowBatteryThresholdPercent: rollingBufferConfiguration.lowBatteryThresholdPercent,
            rollingBufferDurationSeconds: rollingBufferConfiguration.bufferDurationSeconds,
            rollingBufferPreloadFinalization: rollingBufferConfiguration.preRunFinalization,
            rollingBufferVADModel: VoiceInkRollingBufferVADSettings.selectedModel(),
            rollingBufferPreloadEnabledByModel: perModelPreloadSettings.isEmpty ? nil : perModelPreloadSettings
        )

        let exportedSettings = BackupFile(
            version: currentSettingsVersion,
            customPrompts: exportablePrompts,
            powerModeConfigs: powerConfigs,
            powerModeShortcuts: powerModeShortcuts.isEmpty ? nil : powerModeShortcuts,
            vocabularyWords: dictionaryExportPlan.vocabularyBackupRecords,
            wordReplacements: dictionaryExportPlan.wordReplacementBackupRecords,
            generalSettings: generalSettingsToExport,
            customEmojis: emojiManager.customEmojis,
            customCloudModels: customModels
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(exportedSettings)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.nameFieldStringValue = backupPresentation.defaultFileName
            savePanel.title = backupPresentation.exportPanelTitle
            savePanel.message = backupPresentation.exportPanelMessage

            DispatchQueue.main.async {
                if savePanel.runModal() == .OK {
                    if let url = savePanel.url {
                        do {
                            try jsonData.write(to: url)
                            self.showAlert(
                                title: self.backupPresentation.exportSuccessTitle,
                                message: self.backupPresentation.exportSuccessMessage(fileName: url.lastPathComponent)
                            )
                        } catch {
                            self.showAlert(
                                title: self.backupPresentation.exportErrorTitle,
                                message: self.backupPresentation.exportSaveFailureMessage(localizedDescription: error.localizedDescription)
                            )
                        }
                    }
                } else {
                    self.showAlert(
                        title: self.backupPresentation.exportCanceledTitle,
                        message: self.backupPresentation.exportCanceledMessage
                    )
                }
            }
        } catch {
            self.showAlert(
                title: backupPresentation.exportErrorTitle,
                message: backupPresentation.exportEncodingFailureMessage(localizedDescription: error.localizedDescription)
            )
        }
    }

    @MainActor
    func importSettings(enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = backupPresentation.importPanelTitle
        openPanel.message = backupPresentation.importPanelMessage

        guard openPanel.runModal() == .OK else {
            showAlert(
                title: backupPresentation.importCanceledTitle,
                message: backupPresentation.importCanceledMessage
            )
            return
        }

        guard let url = openPanel.url else {
            showAlert(
                title: backupPresentation.importErrorTitle,
                message: backupPresentation.missingFileURLMessage
            )
            return
        }

        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let backup = try decoder.decode(BackupFile.self, from: jsonData)

            if backup.version != currentSettingsVersion {
                showAlert(
                    title: backupPresentation.versionMismatchTitle,
                    message: backupPresentation.versionMismatchMessage(
                        importedVersion: backup.version,
                        currentVersion: currentSettingsVersion
                    )
                )
            }

            guard let selectedCategories = presentImportSelectionDialog() else {
                showAlert(
                    title: backupPresentation.importCanceledTitle,
                    message: backupPresentation.noSettingsImportedMessage
                )
                return
            }

            guard !selectedCategories.isEmpty else {
                showAlert(
                    title: backupPresentation.importErrorTitle,
                    message: backupPresentation.emptyCategorySelectionMessage
                )
                return
            }

            try BackupImporter.apply(
                backup,
                categories: selectedCategories,
                enhancementService: enhancementService,
                recordingShortcutManager: recordingShortcutManager,
                menuBarManager: menuBarManager,
                mediaController: mediaController,
                playbackController: playbackController,
                soundManager: soundManager,
                recorderUIManager: recorderUIManager,
                modelContext: modelContext,
                transcriptionModelManager: transcriptionModelManager
            )

            showImportSuccessAlert(
                fileName: url.lastPathComponent,
                categories: selectedCategories
            )
        } catch {
            showAlert(
                title: backupPresentation.importErrorTitle,
                message: backupPresentation.importFailureMessage(localizedDescription: error.localizedDescription)
            )
        }
    }

    private func presentImportSelectionDialog() -> Set<VoiceInkSettingsBackupCategory>? {
        let accessory = BackupOptions()
        let alert = NSAlert()
        alert.messageText = backupPresentation.importSelectionTitle
        alert.informativeText = backupPresentation.importSelectionMessage
        alert.alertStyle = .informational
        alert.accessoryView = accessory.view
        alert.addButton(withTitle: backupPresentation.importActionTitle)
        alert.addButton(withTitle: backupPresentation.cancelActionTitle)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return accessory.selectedCategories
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: self.backupPresentation.okActionTitle)
            alert.runModal()
        }
    }

    private func showImportSuccessAlert(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            let needsAPIKeyReminder = VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories)
            alert.messageText = self.backupPresentation.importSuccessTitle
            alert.informativeText = self.backupPresentation.importSuccessInformativeText(
                fileName: fileName,
                categories: categories
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: self.backupPresentation.okActionTitle)
            if needsAPIKeyReminder {
                alert.addButton(withTitle: self.backupPresentation.configureAPIKeysActionTitle)
            }
            
            let response = alert.runModal()
            if needsAPIKeyReminder && response == .alertSecondButtonReturn {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "Enhancement"]
                )
            }
        }
    }
}
