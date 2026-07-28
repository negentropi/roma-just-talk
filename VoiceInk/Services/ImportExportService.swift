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
        self.currentSettingsVersion = VoiceInkSettingsBackupImportPolicy.currentVersion(
            bundleShortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    @MainActor
    func exportSettings(enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext) {
        let powerModeManager = PowerModeManager.shared
        let emojiManager = EmojiManager.shared

        let exportablePrompts = VoiceInkCustomPromptPolicy.exportedCustomPrompts(
            from: enhancementService.customPrompts
        )

        let powerModeExportPlan = VoiceInkPowerModePolicy.powerModeBackupExportPlan(
            configurations: powerModeManager.configurations,
            customEmojis: emojiManager.customEmojis
        )
        var powerModeConfigs: [PowerModeConfig] = []
        var powerModeShortcuts: [String: ShortcutBackup]?
        var powerModeCustomEmojis: [String]?
        powerModeExportPlan.applyRuntimeState(
            backupForConfiguration: { id in
                ShortcutStore.shortcut(for: .powerMode(id)).map(ShortcutBackup.init)
            },
            setConfigurations: { configurations in
                powerModeConfigs = configurations
            },
            setShortcutBackups: { shortcuts in
                powerModeShortcuts = shortcuts
            },
            setCustomEmojis: { customEmojis in
                powerModeCustomEmojis = customEmojis
            }
        )

        // Export custom models
        let customModels = CustomCloudModelManager.shared.customModels.map { VoiceInkCustomCloudModelBackup(model: $0) }

        let vocabularyDescriptor = FetchDescriptor<VocabularyWord>()
        let vocabularyWords = (try? modelContext.fetch(vocabularyDescriptor).map(\.word)) ?? []

        let replacementsDescriptor = FetchDescriptor<WordReplacement>()
        let wordReplacementRules = (try? modelContext.fetch(replacementsDescriptor).map(\.voiceInkRule)) ?? []
        let dictionaryExportPlan = VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
            vocabularyWords: vocabularyWords,
            wordReplacementRules: wordReplacementRules
        )
        var vocabularyBackupRecords: [VoiceInkVocabularyWordBackup]?
        var wordReplacementBackupRecords: [String: String]?
        dictionaryExportPlan.applyRuntimeState(
            setVocabularyBackupRecords: { records in
                vocabularyBackupRecords = records
            },
            setWordReplacementBackupRecords: { records in
                wordReplacementBackupRecords = records
            }
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
        let recordingFeedbackBackupPreferences = VoiceInkRecordingFeedbackPreference.backupPreferences(
            isSoundFeedbackEnabled: soundManager.isEnabled,
            isSystemMuteEnabled: mediaController.isSystemMuteEnabled,
            isPauseMediaEnabled: playbackController.isPauseMediaEnabled,
            audioResumptionDelay: mediaController.audioResumptionDelay,
            isExperimentalFeaturesEnabled: VoiceInkRecordingFeedbackPreference.isExperimentalFeaturesEnabled()
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
        let macOSShellBackupPreferences = VoiceInkMacOSShellBackupPreference.backupPreferences(
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            isMenuBarOnly: menuBarManager.isMenuBarOnly,
            recorderType: recorderUIManager.recorderType
        )
        let generalSettingsBackupPreferences = VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
            recordingShortcut: recordingShortcutBackupPreferences,
            macOSShell: macOSShellBackupPreferences,
            transcriptionAutoCleanup: transcriptionAutoCleanupBackupPreferences,
            audioCleanup: audioCleanupBackupPreferences,
            recordingFeedback: recordingFeedbackBackupPreferences,
            transcriptionCleanup: transcriptionCleanupBackupPreferences,
            paste: pasteBackupPreferences
        )
        let shortcutBackupRecords = VoiceInkShortcutBackupPolicy.generalBackupShortcutRecords { actionIdentifier in
            ShortcutStore.shortcut(for: actionIdentifier).map(ShortcutBackup.init)
        }
        let generalSettingsToExport = VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>(
            shortcutBackupRecords: shortcutBackupRecords,
            preferences: generalSettingsBackupPreferences
        )

        let exportedSettings = VoiceInkSettingsBackupFile<ShortcutBackup>(
            version: currentSettingsVersion,
            customPrompts: exportablePrompts,
            powerModeConfigs: powerModeConfigs,
            powerModeShortcuts: powerModeShortcuts,
            vocabularyWords: vocabularyBackupRecords,
            wordReplacements: wordReplacementBackupRecords,
            generalSettings: generalSettingsToExport,
            customEmojis: powerModeCustomEmojis,
            customCloudModels: customModels
        )

        do {
            let jsonData = try VoiceInkSettingsBackupFileCodec.encode(exportedSettings)

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
    func importSettings(enhancementService: AIEnhancementService, recordingShortcutManager: RecordingShortcutManager, menuBarManager: MenuBarManager, launchAtLoginController: LaunchAtLoginController, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, recorderUIManager: RecorderUIManager, modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager) {
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
            let backup: VoiceInkSettingsBackupFile<ShortcutBackup> = try VoiceInkSettingsBackupFileCodec.decode(from: jsonData)

            VoiceInkSettingsBackupImportPolicy.versionReview(
                importedVersion: backup.version,
                currentVersion: currentSettingsVersion
            ).applyRuntimeState { importedVersion, currentVersion in
                showAlert(
                    title: backupPresentation.versionMismatchTitle,
                    message: backupPresentation.versionMismatchMessage(
                        importedVersion: importedVersion,
                        currentVersion: currentVersion
                    )
                )
            }

            try VoiceInkSettingsBackupImportPolicy.importSelectionReview(
                selectedCategories: presentImportSelectionDialog()
            ).applyRuntimeState(
                reportNoSettingsImported: {
                    showAlert(
                        title: backupPresentation.importCanceledTitle,
                        message: backupPresentation.noSettingsImportedMessage
                    )
                },
                reportEmptyCategorySelection: {
                    showAlert(
                        title: backupPresentation.importErrorTitle,
                        message: backupPresentation.emptyCategorySelectionMessage
                    )
                },
                importSelectedCategories: { selectedCategories in
                    try BackupImporter.apply(
                        backup,
                        categories: selectedCategories,
                        enhancementService: enhancementService,
                        recordingShortcutManager: recordingShortcutManager,
                        menuBarManager: menuBarManager,
                        launchAtLoginController: launchAtLoginController,
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
                }
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
            let importSuccessPlan = VoiceInkSettingsBackupImportPolicy.importSuccessPlan(
                categories: categories
            )
            alert.messageText = self.backupPresentation.importSuccessTitle
            alert.informativeText = self.backupPresentation.importSuccessInformativeText(
                fileName: fileName,
                categories: categories
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: self.backupPresentation.okActionTitle)
            if importSuccessPlan.isConfigureAPIKeysActionVisible {
                alert.addButton(withTitle: self.backupPresentation.configureAPIKeysActionTitle)
            }
            
            let response = alert.runModal()
            importSuccessPlan.applyRuntimeState(
                selectedConfigureAPIKeysAction: response == .alertSecondButtonReturn,
                navigateToAPIKeySettings: {
                    NotificationCenter.default.post(
                        name: .navigateToDestination,
                        object: nil,
                        userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .enhancement)
                    )
                }
            )
        }
    }
}
