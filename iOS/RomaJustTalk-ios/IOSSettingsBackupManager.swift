import CoreTransferable
import Combine
import Foundation
import UniformTypeIdentifiers
import RomaCore

struct RomaIOSSettingsBackupExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(RomaIOSSettingsBackupCodec.defaultFilename)
            try export.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

@MainActor
final class IOSSettingsBackupManager: ObservableObject {
    @Published private(set) var pendingImport: RomaIOSSettingsBackupFile?
    @Published var selectedImportCategories = Set<RomaIOSSettingsBackupCategory>()
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

    var availableImportCategories: [RomaIOSSettingsBackupCategory] {
        RomaIOSSettingsBackupCategory.allCases.filter {
            pendingImport?.availableCategories.contains($0) == true
        }
    }

    func exportItem(
        categories: Set<RomaIOSSettingsBackupCategory>
    ) throws -> RomaIOSSettingsBackupExport {
        let backup = makeBackup(categories: categories)
        return RomaIOSSettingsBackupExport(
            data: try RomaIOSSettingsBackupCodec.encode(backup)
        )
    }

    func loadImport(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let backup = try RomaIOSSettingsBackupCodec.decode(Data(contentsOf: url))
            guard !backup.availableCategories.isEmpty else {
                throw RomaIOSSettingsBackupError.unavailableCategory
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
            let plan = try RomaIOSSettingsBackupImportPlan(
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
                    settings.customPrompts = RomaCustomPromptPolicy.promptsAfterImportingCustomPrompts(
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
        categories: Set<RomaIOSSettingsBackupCategory>
    ) -> RomaIOSSettingsBackupFile {
        let version = RomaSettingsBackupImportPolicy.currentVersion(
            bundleShortVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
        return RomaIOSSettingsBackupFile(
            version: version,
            general: categories.contains(.general) ? generalBackup : nil,
            modes: categories.contains(.modes)
                ? RomaIOSModesBackup(modes: settings.modes, selectedModeId: settings.selectedModeId)
                : nil,
            prompts: categories.contains(.prompts)
                ? RomaCustomPromptPolicy.exportedCustomPrompts(from: settings.customPrompts)
                : nil,
            dictionary: categories.contains(.dictionary)
                ? RomaIOSDictionaryBackup(
                    vocabularyTerms: settings.customVocabularyTerms,
                    wordReplacements: settings.wordReplacements
                )
                : nil,
            customModels: categories.contains(.customModels)
                ? customModelManager.models.map(RomaIOSCustomModelDefinition.init)
                : nil
        )
    }

    private var generalBackup: RomaIOSGeneralSettingsBackup {
        let transcriptionCleanup = RomaTranscriptionAutoCleanupPreference.current(from: defaults)
        let audioCleanup = RomaAudioCleanupPreference.current(from: defaults)
        return RomaIOSGeneralSettingsBackup(
            audioSessionTimeoutSeconds: settings.audioSessionTimeoutSeconds,
            transcriptionCleanupSettings: RomaIOSTranscriptionCleanupBackup(
                settings.transcriptionCleanupSettings
            ),
            fillerWords: settings.fillerWords,
            selectedTranscriptionLanguage: settings.selectedTranscriptionLanguage,
            isVADEnabled: RomaVADPreference.isEnabled(from: defaults),
            shouldPrewarmModel: RomaModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults),
            appendTrailingSpace: RomaAppendTrailingSpacePreference.isEnabled(from: defaults),
            isTranscriptionCleanupEnabled: transcriptionCleanup.isEnabled,
            transcriptionRetentionMinutes: transcriptionCleanup.retentionMinutes,
            isAudioCleanupEnabled: audioCleanup.isEnabled,
            audioRetentionDays: audioCleanup.retentionDays
        )
    }

    private func applyGeneral(_ backup: RomaIOSGeneralSettingsBackup) {
        settings.audioSessionTimeoutSeconds = backup.audioSessionTimeoutSeconds
        settings.transcriptionCleanupSettings = backup.transcriptionCleanupSettings.settings
        settings.fillerWords = backup.fillerWords
        settings.selectedTranscriptionLanguage = backup.selectedTranscriptionLanguage
        RomaVADPreference.saveIsEnabled(backup.isVADEnabled, to: defaults)
        RomaModelRuntimePreference.saveShouldPrewarmModelOnWake(
            backup.shouldPrewarmModel,
            to: defaults
        )
        RomaAppendTrailingSpacePreference.saveIsEnabled(backup.appendTrailingSpace, to: defaults)
        RomaTranscriptionAutoCleanupPreference.saveIsEnabled(
            backup.isTranscriptionCleanupEnabled,
            to: defaults
        )
        RomaTranscriptionAutoCleanupPreference.saveRetentionMinutes(
            backup.transcriptionRetentionMinutes,
            to: defaults
        )
        RomaAudioCleanupPreference.saveIsEnabled(backup.isAudioCleanupEnabled, to: defaults)
        RomaAudioCleanupPreference.saveRetentionDays(backup.audioRetentionDays, to: defaults)
    }
}
