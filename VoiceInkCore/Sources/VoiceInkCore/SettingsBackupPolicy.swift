import Foundation

public enum VoiceInkSettingsBackupCategory: String, CaseIterable, Hashable, Sendable {
    case general
    case prompts
    case powerMode
    case dictionary
    case customModels

    public var title: String {
        switch self {
        case .general:
            return "General Settings"
        case .prompts:
            return "Custom Prompts"
        case .powerMode:
            return "Power Mode"
        case .dictionary:
            return "Dictionary"
        case .customModels:
            return "Custom Model Definitions"
        }
    }
}

public enum VoiceInkSettingsBackupImportPolicy {
    public static let fallbackVersion = "0.0.0"

    public static func currentVersion(bundleShortVersion: String?) -> String {
        bundleShortVersion ?? fallbackVersion
    }

    public static func categorySummary(for categories: Set<VoiceInkSettingsBackupCategory>) -> String {
        if categories == Set(VoiceInkSettingsBackupCategory.allCases) {
            return "All settings"
        }

        return VoiceInkSettingsBackupCategory.allCases
            .filter { categories.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    public static func needsAPIKeyReminder(for categories: Set<VoiceInkSettingsBackupCategory>) -> Bool {
        !categories.isDisjoint(with: [.prompts, .powerMode, .customModels])
    }

    public static func versionReview(
        importedVersion: String,
        currentVersion: String
    ) -> VoiceInkSettingsBackupVersionReview {
        VoiceInkSettingsBackupVersionReview(
            importedVersion: importedVersion,
            currentVersion: currentVersion
        )
    }

    public static func importSelectionReview(
        selectedCategories: Set<VoiceInkSettingsBackupCategory>?
    ) -> VoiceInkSettingsBackupImportSelectionReview {
        VoiceInkSettingsBackupImportSelectionReview(
            selectedCategories: selectedCategories
        )
    }

    public static func importSuccessPlan(
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> VoiceInkSettingsBackupImportSuccessPlan {
        VoiceInkSettingsBackupImportSuccessPlan(categories: categories)
    }
}

public struct VoiceInkSettingsBackupVersionReview: Equatable, Sendable {
    public let importedVersion: String
    public let currentVersion: String

    public var hasMismatch: Bool {
        importedVersion != currentVersion
    }

    public init(importedVersion: String, currentVersion: String) {
        self.importedVersion = importedVersion
        self.currentVersion = currentVersion
    }

    public func applyRuntimeState(
        reportVersionMismatch: (_ importedVersion: String, _ currentVersion: String) -> Void
    ) {
        guard hasMismatch else { return }
        reportVersionMismatch(importedVersion, currentVersion)
    }
}

public enum VoiceInkSettingsBackupImportSelectionReview: Equatable, Sendable {
    case canceled
    case emptySelection
    case selected(Set<VoiceInkSettingsBackupCategory>)

    public init(selectedCategories: Set<VoiceInkSettingsBackupCategory>?) {
        guard let selectedCategories else {
            self = .canceled
            return
        }

        if selectedCategories.isEmpty {
            self = .emptySelection
        } else {
            self = .selected(selectedCategories)
        }
    }

    public func applyRuntimeState(
        reportNoSettingsImported: () -> Void,
        reportEmptyCategorySelection: () -> Void,
        importSelectedCategories: (Set<VoiceInkSettingsBackupCategory>) throws -> Void
    ) rethrows {
        switch self {
        case .canceled:
            reportNoSettingsImported()
        case .emptySelection:
            reportEmptyCategorySelection()
        case .selected(let categories):
            try importSelectedCategories(categories)
        }
    }
}

public struct VoiceInkSettingsBackupImportSuccessPlan: Equatable, Sendable {
    public let categories: Set<VoiceInkSettingsBackupCategory>

    public var isConfigureAPIKeysActionVisible: Bool {
        VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories)
    }

    public init(categories: Set<VoiceInkSettingsBackupCategory>) {
        self.categories = categories
    }

    public func applyRuntimeState(
        selectedConfigureAPIKeysAction: Bool,
        navigateToAPIKeySettings: () -> Void
    ) {
        guard isConfigureAPIKeysActionVisible,
              selectedConfigureAPIKeysAction else { return }
        navigateToAPIKeySettings()
    }
}

public enum VoiceInkSettingsBackupImportDiagnostics {
    public static let noGeneralSettingsMessage = "No general settings found in the imported file."
    public static let noVocabularyWordsMessage = "No vocabulary words found in the imported file. Existing items remain unchanged."
    public static let noWordReplacementsMessage = "No word replacements found in the imported file. Existing replacements remain unchanged."
    public static let noDictionaryEntriesImportedMessage = "No new dictionary entries were imported."
    public static let generalSettingsImportedMessage = "Successfully imported general settings."
    public static let noCustomModelsMessage = "No custom models found in the imported file."

    public static func saveFailedDescription(item: String, localizedDescription: String) -> String {
        "Failed to save imported \(item): \(localizedDescription)"
    }

    public static func customPromptsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) custom prompts."
    }

    public static func powerModeConfigurationsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) Power Mode configurations."
    }

    public static func skippedInvalidReplacementsMessage(count: Int) -> String {
        "Skipped \(count) invalid word replacements from the imported file."
    }

    public static func dictionaryEntriesImportedMessage(
        vocabularyWordCount: Int,
        wordReplacementCount: Int
    ) -> String {
        "Successfully imported \(vocabularyWordCount) vocabulary words and \(wordReplacementCount) word replacements to SwiftData."
    }

    public static func customModelsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) custom model definitions."
    }
}

public enum VoiceInkSettingsBackupImportError: LocalizedError, Sendable {
    case saveFailed(item: String, localizedDescription: String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let localizedDescription):
            VoiceInkSettingsBackupImportDiagnostics.saveFailedDescription(
                item: item,
                localizedDescription: localizedDescription
            )
        }
    }
}

public struct VoiceInkSettingsBackupFile<ShortcutBackup: Codable>: Codable {
    public let version: String
    public let customPrompts: [VoiceInkCustomPrompt]
    public let powerModeConfigs: [PowerModeConfig]
    public let powerModeShortcuts: [String: ShortcutBackup]?
    public let vocabularyWords: [VoiceInkVocabularyWordBackup]?
    public let wordReplacements: [String: String]?
    public let generalSettings: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?
    public let customEmojis: [String]?
    public let customCloudModels: [VoiceInkCustomCloudModelBackup]?

    private enum CodingKeys: String, CodingKey {
        case version
        case customPrompts
        case powerModeConfigs
        case powerModeShortcuts
        case vocabularyWords
        case wordReplacements
        case generalSettings
        case customEmojis
        case customCloudModels
    }

    public init(
        version: String,
        customPrompts: [VoiceInkCustomPrompt],
        powerModeConfigs: [PowerModeConfig],
        powerModeShortcuts: [String: ShortcutBackup]?,
        vocabularyWords: [VoiceInkVocabularyWordBackup]?,
        wordReplacements: [String: String]?,
        generalSettings: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?,
        customEmojis: [String]?,
        customCloudModels: [VoiceInkCustomCloudModelBackup]?
    ) {
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        customPrompts = try container.decodeIfPresent([VoiceInkCustomPrompt].self, forKey: .customPrompts) ?? []
        powerModeConfigs = try container.decodeIfPresent([PowerModeConfig].self, forKey: .powerModeConfigs) ?? []
        powerModeShortcuts = try container.decodeIfPresent([String: ShortcutBackup].self, forKey: .powerModeShortcuts)
        vocabularyWords = try container.decodeIfPresent([VoiceInkVocabularyWordBackup].self, forKey: .vocabularyWords)
        wordReplacements = try container.decodeIfPresent([String: String].self, forKey: .wordReplacements)
        generalSettings = try container.decodeIfPresent(VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>.self, forKey: .generalSettings)
        customEmojis = try container.decodeIfPresent([String].self, forKey: .customEmojis)
        customCloudModels = try container.decodeIfPresent([VoiceInkCustomCloudModelBackup].self, forKey: .customCloudModels)
    }
}

public enum VoiceInkSettingsBackupFileCodec {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }

    public static func encode<ShortcutBackup: Codable>(
        _ backupFile: VoiceInkSettingsBackupFile<ShortcutBackup>,
        encoder: JSONEncoder = makeEncoder()
    ) throws -> Data {
        try encoder.encode(backupFile)
    }

    public static func decode<ShortcutBackup: Codable>(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> VoiceInkSettingsBackupFile<ShortcutBackup> {
        try decoder.decode(VoiceInkSettingsBackupFile<ShortcutBackup>.self, from: data)
    }
}

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

public struct VoiceInkSettingsBackupPresentation: Equatable, Sendable {
    public let defaultFileName: String
    public let exportPanelTitle: String
    public let exportPanelMessage: String
    public let importPanelTitle: String
    public let importPanelMessage: String
    public let importSelectionTitle: String
    public let importSelectionMessage: String
    public let allCategoriesTitle: String
    public let individualCategoriesTitle: String
    public let importActionTitle: String
    public let cancelActionTitle: String
    public let okActionTitle: String
    public let configureAPIKeysActionTitle: String
    public let exportSuccessTitle: String
    public let exportErrorTitle: String
    public let exportCanceledTitle: String
    public let importCanceledTitle: String
    public let importErrorTitle: String
    public let versionMismatchTitle: String
    public let importSuccessTitle: String
    public let exportCanceledMessage: String
    public let importCanceledMessage: String
    public let noSettingsImportedMessage: String
    public let missingFileURLMessage: String
    public let emptyCategorySelectionMessage: String
    public let apiKeyReminderText: String
    public let restartRecommendationText: String

    public static let macOS = VoiceInkSettingsBackupPresentation(
        defaultFileName: "VoiceInk_Settings_Backup.json",
        exportPanelTitle: "Export VoiceInk Settings",
        exportPanelMessage: "Choose a location to save your settings.",
        importPanelTitle: "Import VoiceInk Settings",
        importPanelMessage: "Choose a settings backup, then select what you want to import.",
        importSelectionTitle: "Import Settings",
        importSelectionMessage: "Choose what to import from this backup.",
        allCategoriesTitle: "All",
        individualCategoriesTitle: "Individual categories",
        importActionTitle: "Import",
        cancelActionTitle: "Cancel",
        okActionTitle: "OK",
        configureAPIKeysActionTitle: "Configure API Keys",
        exportSuccessTitle: "Export Successful",
        exportErrorTitle: "Export Error",
        exportCanceledTitle: "Export Canceled",
        importCanceledTitle: "Import Canceled",
        importErrorTitle: "Import Error",
        versionMismatchTitle: "Version Mismatch",
        importSuccessTitle: "Import Successful",
        exportCanceledMessage: "The settings export operation was canceled.",
        importCanceledMessage: "The settings import operation was canceled.",
        noSettingsImportedMessage: "No settings were imported.",
        missingFileURLMessage: "Could not get the file URL from the open panel.",
        emptyCategorySelectionMessage: "Select at least one category to import.",
        apiKeyReminderText: "IMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.",
        restartRecommendationText: "It is recommended to restart VoiceInk for all changes to take full effect."
    )

    public func exportSuccessMessage(fileName: String) -> String {
        "Your settings have been successfully exported to \(fileName)."
    }

    public func exportSaveFailureMessage(localizedDescription: String) -> String {
        "Could not save settings to file: \(localizedDescription)"
    }

    public func exportEncodingFailureMessage(localizedDescription: String) -> String {
        "Could not encode settings to JSON: \(localizedDescription)"
    }

    public func versionMismatchMessage(importedVersion: String, currentVersion: String) -> String {
        "The imported settings file (version \(importedVersion)) is from a different version than your application (version \(currentVersion)). Proceeding with import, but be aware of potential incompatibilities."
    }

    public func importSuccessMessage(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> String {
        "Settings imported successfully from \(fileName).\n\nImported: \(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))."
    }

    public func importFailureMessage(localizedDescription: String) -> String {
        "Error importing settings: \(localizedDescription). The file might be corrupted or not in the correct format."
    }

    public func importSuccessInformativeText(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> String {
        var informativeText = importSuccessMessage(fileName: fileName, categories: categories)
        if VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories) {
            informativeText += "\n\n\(apiKeyReminderText)"
        }
        informativeText += "\n\n\(restartRecommendationText)"
        return informativeText
    }
}
