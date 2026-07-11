import CoreTransferable
import Combine
import Foundation
import UniformTypeIdentifiers
import VoiceInkCore

struct VoiceInkIOSSettingsBackupExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(VoiceInkIOSSettingsBackupCodec.defaultFilename)
            try export.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

@MainActor
final class IOSSettingsBackupManager: ObservableObject {
    @Published private(set) var pendingImport: VoiceInkIOSSettingsBackupFile?
    @Published var selectedImportCategories = Set<VoiceInkIOSSettingsBackupCategory>()
    @Published var statusMessage: String?

    private let settings: AppSettings
    private let customModelManager: IOSCustomCloudModelManager
    private let defaults: UserDefaults

    init(
        settings: AppSettings,
        customModelManager: IOSCustomCloudModelManager,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.customModelManager = customModelManager
        self.defaults = defaults
    }

    convenience init() {
        self.init(settings: .shared, customModelManager: .shared)
    }

    var availableImportCategories: [VoiceInkIOSSettingsBackupCategory] {
        VoiceInkIOSSettingsBackupCategory.allCases.filter {
            pendingImport?.availableCategories.contains($0) == true
        }
    }

    func exportItem(
        categories: Set<VoiceInkIOSSettingsBackupCategory>
    ) throws -> VoiceInkIOSSettingsBackupExport {
        let backup = makeBackup(categories: categories)
        return VoiceInkIOSSettingsBackupExport(
            data: try VoiceInkIOSSettingsBackupCodec.encode(backup)
        )
    }

    func loadImport(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let backup = try VoiceInkIOSSettingsBackupCodec.decode(Data(contentsOf: url))
            guard !backup.availableCategories.isEmpty else {
                throw VoiceInkIOSSettingsBackupError.unavailableCategory
            }
            pendingImport = backup
            selectedImportCategories = backup.availableCategories
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func applyPendingImport() {
        guard let pendingImport else { return }
        do {
            let plan = try VoiceInkIOSSettingsBackupImportPlan(
                backup: pendingImport,
                categories: selectedImportCategories
            )
            try plan.applyRuntimeState(
                replaceCustomModels: { [customModelManager] definitions in
                    try customModelManager.replaceDefinitions(definitions)
                },
                applyGeneral: applyGeneral,
                applyModes: { [settings] backup in
                    settings.modes = backup.modes
                    settings.selectedModeId = backup.modes.contains { $0.id == backup.selectedModeId }
                        ? backup.selectedModeId
                        : backup.modes.first?.id
                },
                applyPrompts: { [settings] prompts in
                    settings.customPrompts = VoiceInkCustomPromptPolicy.promptsAfterImportingCustomPrompts(
                        prompts,
                        currentPrompts: settings.customPrompts
                    )
                },
                applyDictionary: { [settings] dictionary in
                    settings.customVocabularyTerms = dictionary.vocabularyTerms
                    settings.wordReplacements = dictionary.wordReplacements
                }
            )
            let summary = selectedImportCategories
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.title)
                .joined(separator: ", ")
            self.pendingImport = nil
            statusMessage = "Imported: \(summary). API keys are never included; configure them separately."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func cancelImport() {
        pendingImport = nil
        selectedImportCategories = []
    }

    private func makeBackup(
        categories: Set<VoiceInkIOSSettingsBackupCategory>
    ) -> VoiceInkIOSSettingsBackupFile {
        let version = VoiceInkSettingsBackupImportPolicy.currentVersion(
            bundleShortVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
        return VoiceInkIOSSettingsBackupFile(
            version: version,
            general: categories.contains(.general) ? generalBackup : nil,
            modes: categories.contains(.modes)
                ? VoiceInkIOSModesBackup(modes: settings.modes, selectedModeId: settings.selectedModeId)
                : nil,
            prompts: categories.contains(.prompts)
                ? VoiceInkCustomPromptPolicy.exportedCustomPrompts(from: settings.customPrompts)
                : nil,
            dictionary: categories.contains(.dictionary)
                ? VoiceInkIOSDictionaryBackup(
                    vocabularyTerms: settings.customVocabularyTerms,
                    wordReplacements: settings.wordReplacements
                )
                : nil,
            customModels: categories.contains(.customModels)
                ? customModelManager.models.map(VoiceInkIOSCustomModelDefinition.init)
                : nil
        )
    }

    private var generalBackup: VoiceInkIOSGeneralSettingsBackup {
        let transcriptionCleanup = VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults)
        let audioCleanup = VoiceInkAudioCleanupPreference.current(from: defaults)
        return VoiceInkIOSGeneralSettingsBackup(
            audioSessionTimeoutSeconds: settings.audioSessionTimeoutSeconds,
            transcriptionCleanupSettings: VoiceInkIOSTranscriptionCleanupBackup(
                settings.transcriptionCleanupSettings
            ),
            fillerWords: settings.fillerWords,
            selectedTranscriptionLanguage: settings.selectedTranscriptionLanguage,
            isVADEnabled: VoiceInkVADPreference.isEnabled(from: defaults),
            shouldPrewarmModel: VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults),
            appendTrailingSpace: VoiceInkAppendTrailingSpacePreference.isEnabled(from: defaults),
            isTranscriptionCleanupEnabled: transcriptionCleanup.isEnabled,
            transcriptionRetentionMinutes: transcriptionCleanup.retentionMinutes,
            isAudioCleanupEnabled: audioCleanup.isEnabled,
            audioRetentionDays: audioCleanup.retentionDays
        )
    }

    private func applyGeneral(_ backup: VoiceInkIOSGeneralSettingsBackup) {
        settings.audioSessionTimeoutSeconds = backup.audioSessionTimeoutSeconds
        settings.transcriptionCleanupSettings = backup.transcriptionCleanupSettings.settings
        settings.fillerWords = backup.fillerWords
        settings.selectedTranscriptionLanguage = backup.selectedTranscriptionLanguage
        VoiceInkVADPreference.saveIsEnabled(backup.isVADEnabled, to: defaults)
        VoiceInkModelRuntimePreference.saveShouldPrewarmModelOnWake(
            backup.shouldPrewarmModel,
            to: defaults
        )
        VoiceInkAppendTrailingSpacePreference.saveIsEnabled(backup.appendTrailingSpace, to: defaults)
        VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(
            backup.isTranscriptionCleanupEnabled,
            to: defaults
        )
        VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(
            backup.transcriptionRetentionMinutes,
            to: defaults
        )
        VoiceInkAudioCleanupPreference.saveIsEnabled(backup.isAudioCleanupEnabled, to: defaults)
        VoiceInkAudioCleanupPreference.saveRetentionDays(backup.audioRetentionDays, to: defaults)
    }
}
