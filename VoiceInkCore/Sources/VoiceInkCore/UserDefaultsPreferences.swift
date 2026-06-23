import Foundation

public enum VoiceInkUserDefaultsKey {
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let lowercaseTranscription = "LowercaseTranscription"
    public static let removeFillerWords = "RemoveFillerWords"
    public static let fillerWords = "FillerWords"
    public static let wordReplacements = "voiceInkIOSWordReplacements"
    public static let customVocabularyTerms = "voiceInkIOSCustomVocabularyTerms"
    public static let modes = "modes"
    public static let selectedModeId = "selectedModeId"
    public static let selectedTranscriptionLanguage = "SelectedLanguage"
    public static let currentTranscriptionModel = "CurrentTranscriptionModel"
    public static let transcriptionPrompt = "TranscriptionPrompt"
    public static let isTextFormattingEnabled = "IsTextFormattingEnabled"
    public static let isVADEnabled = "IsVADEnabled"
    public static let isTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    public static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    public static let isAudioCleanupEnabled = "IsAudioCleanupEnabled"
    public static let audioRetentionPeriodDays = "AudioRetentionPeriod"
    public static let audioPlaybackRate = "audioPlaybackRate"
    public static let appendTrailingSpace = "AppendTrailingSpace"
    public static let skipShortEnhancement = "SkipShortEnhancement"
    public static let shortEnhancementWordThreshold = "ShortEnhancementWordThreshold"
    public static let enhancementTimeoutSeconds = "EnhancementTimeoutSeconds"
    public static let enhancementRetryOnTimeout = "EnhancementRetryOnTimeout"
    public static let audioSessionTimeoutSeconds = "audioSessionTimeoutSeconds"
    public static let isAIEnhancementEnabled = "isAIEnhancementEnabled"
    public static let useClipboardContext = "useClipboardContext"
    public static let useScreenCaptureContext = "useScreenCaptureContext"
    public static let customPrompts = "customPrompts"
    public static let selectedPromptId = "selectedPromptId"
    public static let powerModeUIFlag = "powerModeUIFlag"
    public static let powerModePersistConfig = "powerModePersistConfig"
    public static let powerModeConfigurations = "powerModeConfigurationsV2"
    public static let activePowerModeConfigurationId = "activeConfigurationId"
    public static let activePowerModeSession = "powerModeActiveSession.v1"
    public static let prewarmModelOnWake = "PrewarmModelOnWake"
    public static let showLiveTextPreview = "showLiveTextPreview"
    public static let primaryRecordingShortcut = "primaryRecordingShortcut"
    public static let secondaryRecordingShortcut = "secondaryRecordingShortcut"
    public static let primaryRecordingShortcutMode = "primaryRecordingShortcutMode"
    public static let secondaryRecordingShortcutMode = "secondaryRecordingShortcutMode"
    public static let isMiddleClickToggleEnabled = "isMiddleClickToggleEnabled"
    public static let middleClickActivationDelay = "middleClickActivationDelay"
    public static let specialShortcutPasteLastTranscriptOnEmptyTap = "specialShortcutPasteLastTranscriptOnEmptyTap"
    public static let selectedAIProvider = "selectedAIProvider"
    public static let openRouterModels = "openRouterModels"
    public static let ollamaBaseURL = "ollamaBaseURL"
    public static let ollamaSelectedModel = "ollamaSelectedModel"
    public static let customProviderBaseURL = "customProviderBaseURL"
    public static let customProviderModel = "customProviderModel"
    public static let showMenuBarIcon = "ShowMenuBarIcon"
    public static let isMenuBarOnly = "IsMenuBarOnly"
    public static let enableAnnouncements = "enableAnnouncements"
    public static let didApplyLaunchAtLoginDefault = "DidApplyLaunchAtLoginDefault"

    public static func selectedAIProviderModel(_ providerRawValue: String) -> String {
        "\(providerRawValue)SelectedModel"
    }
}

public enum VoiceInkPreferenceDefault {
    public static let audioSessionTimeoutSeconds = 90
    public static let isTextFormattingEnabled = true
    public static let isVADEnabled = true
    public static let lowercaseTranscription = false
    public static let removeFillerWords = true
    public static let transcriptionRetentionMinutes = 24 * 60
    public static let audioRetentionDays = 7
    public static let appendTrailingSpace = true
    public static let skipShortEnhancement = true
    public static let shortEnhancementWordThreshold = 3
    public static let enhancementTimeoutSeconds = 7
    public static let enhancementRetryOnTimeout = true
    public static let powerModeUIEnabled = false
    public static let powerModePersistConfiguredPreferences = false
    public static let prewarmModelOnWake = true
    public static let showLiveTextPreview = false
    public static let isMiddleClickToggleEnabled = false
    public static let middleClickActivationDelay = 200
    public static let specialShortcutPasteLastTranscriptOnEmptyTap = true
    public static let ollamaBaseURL = "http://localhost:11434"
    public static let macOSSelectedTranscriptionLanguage = "en"
    public static let showMenuBarIcon = false
    public static let isMenuBarOnly = true
    public static let enableAnnouncements = true
    public static let didApplyLaunchAtLoginDefault = false
}

public enum VoiceInkPreferenceList {
    public static func changedElements<Element: Equatable>(
        from currentElements: [Element],
        to proposedElements: [Element]
    ) -> [Element]? {
        currentElements == proposedElements ? nil : proposedElements
    }

    public static func removing<Element>(at offsets: IndexSet, from elements: [Element]) -> [Element] {
        var updatedElements = elements

        for index in offsets.sorted(by: >) where updatedElements.indices.contains(index) {
            updatedElements.remove(at: index)
        }

        return updatedElements
    }
}

public enum VoiceInkStartupPreferenceMigrationPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

public enum VoiceInkStartupPreferenceMigration {
    public static func migrateLegacyPreferences(
        for platform: VoiceInkStartupPreferenceMigrationPlatform,
        in defaults: UserDefaults = .standard
    ) {
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded(in: defaults)

        switch platform {
        case .iOS:
            break
        case .macOS:
            VoiceInkPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)
        }
    }
}

public enum VoiceInkMacOSLaunchAtLoginDefaultPolicy {
    public static let didApplyDefaultKey = VoiceInkUserDefaultsKey.didApplyLaunchAtLoginDefault
    public static let defaultDidApplyDefault = VoiceInkPreferenceDefault.didApplyLaunchAtLoginDefault

    public static var registeredDefaults: [String: Any] {
        [didApplyDefaultKey: defaultDidApplyDefault]
    }

    public static func shouldEnableByDefaultBeforeRegisteringDefaults(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        !VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults)
            && defaults.object(forKey: didApplyDefaultKey) == nil
    }

    public static func markDefaultApplied(to defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: didApplyDefaultKey)
    }
}

public struct VoiceInkDefaultSettings: Equatable, Sendable {
    public let audioSessionTimeoutSeconds: Int
    public let punctuationCleanupMode: PunctuationCleanupMode
    public let isTextFormattingEnabled: Bool
    public let isVADEnabled: Bool
    public let lowercaseTranscription: Bool
    public let removeFillerWords: Bool
    public let fillerWords: [String]
    public let selectedTranscriptionLanguage: String
    public let isTranscriptionCleanupEnabled: Bool
    public let transcriptionRetentionMinutes: Int
    public let isAudioCleanupEnabled: Bool
    public let audioRetentionDays: Int
    public let skipShortEnhancement: Bool
    public let shortEnhancementWordThreshold: Int
    public let enhancementTimeoutSeconds: Int
    public let enhancementRetryOnTimeout: Bool

    public init(
        audioSessionTimeoutSeconds: Int = VoiceInkPreferenceDefault.audioSessionTimeoutSeconds,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        isTextFormattingEnabled: Bool = VoiceInkPreferenceDefault.isTextFormattingEnabled,
        isVADEnabled: Bool = VoiceInkPreferenceDefault.isVADEnabled,
        lowercaseTranscription: Bool = VoiceInkPreferenceDefault.lowercaseTranscription,
        removeFillerWords: Bool = VoiceInkPreferenceDefault.removeFillerWords,
        fillerWords: [String] = VoiceInkFillerWords.defaultWords,
        selectedTranscriptionLanguage: String = VoiceInkLanguageCatalog.autoDetectCode,
        isTranscriptionCleanupEnabled: Bool = false,
        transcriptionRetentionMinutes: Int = VoiceInkPreferenceDefault.transcriptionRetentionMinutes,
        isAudioCleanupEnabled: Bool = false,
        audioRetentionDays: Int = VoiceInkPreferenceDefault.audioRetentionDays,
        skipShortEnhancement: Bool = VoiceInkPreferenceDefault.skipShortEnhancement,
        shortEnhancementWordThreshold: Int = VoiceInkPreferenceDefault.shortEnhancementWordThreshold,
        enhancementTimeoutSeconds: Int = VoiceInkPreferenceDefault.enhancementTimeoutSeconds,
        enhancementRetryOnTimeout: Bool = VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    ) {
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.punctuationCleanupMode = punctuationCleanupMode
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.isVADEnabled = isVADEnabled
        self.lowercaseTranscription = lowercaseTranscription
        self.removeFillerWords = removeFillerWords
        self.fillerWords = fillerWords
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.isTranscriptionCleanupEnabled = isTranscriptionCleanupEnabled
        self.transcriptionRetentionMinutes = transcriptionRetentionMinutes
        self.isAudioCleanupEnabled = isAudioCleanupEnabled
        self.audioRetentionDays = audioRetentionDays
        self.skipShortEnhancement = skipShortEnhancement
        self.shortEnhancementWordThreshold = shortEnhancementWordThreshold
        self.enhancementTimeoutSeconds = enhancementTimeoutSeconds
        self.enhancementRetryOnTimeout = enhancementRetryOnTimeout
    }

    public static let iOS = VoiceInkDefaultSettings()
    public static let macOS = VoiceInkDefaultSettings(
        selectedTranscriptionLanguage: VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
    )

    public var transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings {
        VoiceInkTranscriptionCleanupSettings(
            punctuationMode: punctuationCleanupMode,
            isTextFormattingEnabled: isTextFormattingEnabled,
            lowercaseTranscription: lowercaseTranscription,
            removeFillerWords: removeFillerWords
        )
    }

    public func registeredUserDefaults(
        hasCompletedOnboarding: Bool = false,
        currentTranscriptionModel: String? = nil
    ) -> [String: Any] {
        var defaults: [String: Any] = [
            VoiceInkUserDefaultsKey.hasCompletedOnboarding: hasCompletedOnboarding,
            VoiceInkUserDefaultsKey.isTextFormattingEnabled: isTextFormattingEnabled,
            VoiceInkUserDefaultsKey.isVADEnabled: isVADEnabled,
            VoiceInkUserDefaultsKey.removeFillerWords: removeFillerWords,
            PunctuationCleanupMode.legacyRemovePunctuationKey: punctuationCleanupMode == .removeAll,
            VoiceInkUserDefaultsKey.lowercaseTranscription: lowercaseTranscription,
            VoiceInkUserDefaultsKey.selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled: isTranscriptionCleanupEnabled,
            VoiceInkUserDefaultsKey.transcriptionRetentionMinutes: transcriptionRetentionMinutes,
            VoiceInkUserDefaultsKey.isAudioCleanupEnabled: isAudioCleanupEnabled,
            VoiceInkUserDefaultsKey.audioRetentionPeriodDays: audioRetentionDays,
            VoiceInkUserDefaultsKey.skipShortEnhancement: skipShortEnhancement,
            VoiceInkUserDefaultsKey.shortEnhancementWordThreshold: shortEnhancementWordThreshold,
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds: enhancementTimeoutSeconds,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout: enhancementRetryOnTimeout
        ]

        if let currentTranscriptionModel {
            defaults[VoiceInkUserDefaultsKey.currentTranscriptionModel] = currentTranscriptionModel
        }

        return defaults
    }

    public func registerUserDefaults(
        to defaults: UserDefaults = .standard,
        hasCompletedOnboarding: Bool = false,
        currentTranscriptionModel: String? = nil
    ) {
        defaults.register(defaults: registeredUserDefaults(
            hasCompletedOnboarding: hasCompletedOnboarding,
            currentTranscriptionModel: currentTranscriptionModel
        ))
    }
}

public struct VoiceInkAppSettingsResetState {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let apiKeyState: VoiceInkProviderAPIKeyState
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings
    public let fillerWords: [String]
    public let wordReplacements: [VoiceInkWordReplacementRule]
    public let customVocabularyTerms: [String]
    public let selectedTranscriptionLanguage: String
    public let apiKeyProvidersToDelete: [VoiceInkProviderKind]

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        apiKeyState: VoiceInkProviderAPIKeyState,
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings,
        fillerWords: [String],
        wordReplacements: [VoiceInkWordReplacementRule],
        customVocabularyTerms: [String],
        selectedTranscriptionLanguage: String,
        apiKeyProvidersToDelete: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.apiKeyState = apiKeyState
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = transcriptionCleanupSettings
        self.fillerWords = fillerWords
        self.wordReplacements = wordReplacements
        self.customVocabularyTerms = customVocabularyTerms
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.apiKeyProvidersToDelete = apiKeyProvidersToDelete
    }
}

public struct VoiceInkIOSAppSettingsStartupState {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let apiKeyState: VoiceInkProviderAPIKeyState
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings
    public let fillerWords: [String]
    public let wordReplacements: [VoiceInkWordReplacementRule]
    public let customVocabularyTerms: [String]
    public let selectedTranscriptionLanguage: String

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        apiKeyState: VoiceInkProviderAPIKeyState,
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings,
        fillerWords: [String],
        wordReplacements: [VoiceInkWordReplacementRule],
        customVocabularyTerms: [String],
        selectedTranscriptionLanguage: String
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.apiKeyState = apiKeyState
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = transcriptionCleanupSettings
        self.fillerWords = fillerWords
        self.wordReplacements = wordReplacements
        self.customVocabularyTerms = customVocabularyTerms
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
    }
}

public enum VoiceInkIOSAppSettingsStartupPolicy {
    public static func state(
        from defaults: UserDefaults = .standard,
        verifiedProviders: Set<VoiceInkProviderKind>,
        loadStoredAPIKey: (VoiceInkProviderKind) -> String
    ) -> VoiceInkIOSAppSettingsStartupState {
        VoiceInkIOSAppSettingsStartupState(
            modes: VoiceInkModeStorage.loadModes(from: defaults),
            selectedModeId: VoiceInkModeStorage.loadSelectedModeId(from: defaults),
            apiKeyState: VoiceInkProviderAPIKeyState.loadingStoredKeys(
                verifiedProviders: verifiedProviders,
                loadStoredAPIKey: loadStoredAPIKey
            ),
            audioSessionTimeoutSeconds: VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
            transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings.current(in: defaults),
            fillerWords: VoiceInkFillerWordPreference.words(from: defaults),
            wordReplacements: VoiceInkWordReplacementPreference.rules(from: defaults),
            customVocabularyTerms: VoiceInkCustomVocabularyPreference.terms(from: defaults),
            selectedTranscriptionLanguage: VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults)
        )
    }
}

public struct VoiceInkIOSFirstTimeSetupPlan {
    public let modeSettingsRepairPlan: VoiceInkModeSettingsRepairPlan
    public let shouldSaveHasCompletedOnboarding: Bool

    public init(
        modeSettingsRepairPlan: VoiceInkModeSettingsRepairPlan,
        shouldSaveHasCompletedOnboarding: Bool
    ) {
        self.modeSettingsRepairPlan = modeSettingsRepairPlan
        self.shouldSaveHasCompletedOnboarding = shouldSaveHasCompletedOnboarding
    }

    public var applicationActions: [VoiceInkIOSFirstTimeSetupAction] {
        var actions: [VoiceInkIOSFirstTimeSetupAction] = [
            .applyModeSettingsRepair(modeSettingsRepairPlan)
        ]
        if shouldSaveHasCompletedOnboarding {
            actions.append(.saveHasCompletedOnboarding)
        }
        return actions
    }
}

public enum VoiceInkIOSFirstTimeSetupAction {
    case applyModeSettingsRepair(VoiceInkModeSettingsRepairPlan)
    case saveHasCompletedOnboarding
}

public enum VoiceInkIOSFirstTimeSetupPolicy {
    public static func plan(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String
    ) -> VoiceInkIOSFirstTimeSetupPlan {
        VoiceInkIOSFirstTimeSetupPlan(
            modeSettingsRepairPlan: VoiceInkModeSettingsPolicy.defaultModeRepairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            ),
            shouldSaveHasCompletedOnboarding: true
        )
    }
}

public extension VoiceInkDefaultSettings {
    var appSettingsResetState: VoiceInkAppSettingsResetState {
        VoiceInkAppSettingsResetState(
            modes: [],
            selectedModeId: nil,
            apiKeyState: VoiceInkProviderAPIKeyState(),
            audioSessionTimeoutSeconds: audioSessionTimeoutSeconds,
            transcriptionCleanupSettings: transcriptionCleanupSettings,
            fillerWords: fillerWords,
            wordReplacements: [],
            customVocabularyTerms: [],
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            apiKeyProvidersToDelete: VoiceInkProviderKind.userAPIKeyProviders
        )
    }
}

public enum VoiceInkOnboardingPreference {
    public static func hasStoredCompletionState(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding) != nil
    }

    public static func hasCompletedOnboarding(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func saveHasCompletedOnboarding(
        _ completed: Bool = true,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(completed, forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }
}

public struct VoiceInkAudioSessionTimeoutPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let timeoutTitle: String
    public let detailText: String

    public static let iOS = VoiceInkAudioSessionTimeoutPresentation(
        sectionTitle: "Audio Settings",
        timeoutTitle: "Session Timeout",
        detailText: "How long to keep the microphone session active after recording stops. Longer timeouts prevent 'session activation failed' errors when recording frequently, but may use more battery."
    )
}

public enum VoiceInkAudioSessionDeactivationPlan: Equatable, Sendable {
    case immediate
    case delayed(TimeInterval)

    public var executionPlan: VoiceInkAudioSessionDeactivationExecutionPlan {
        switch self {
        case .immediate:
            return .deactivateSession
        case .delayed:
            return .runCountdownTimer
        }
    }
}

public struct VoiceInkAudioSessionDeactivationExecutionPlan: Equatable, Sendable {
    public let shouldDeactivateSession: Bool
    public let shouldRunCountdownTimer: Bool

    public static let deactivateSession = Self(
        shouldDeactivateSession: true,
        shouldRunCountdownTimer: false
    )

    public static let runCountdownTimer = Self(
        shouldDeactivateSession: false,
        shouldRunCountdownTimer: true
    )
}

public enum VoiceInkMenuBarPreference {
    public static let showMenuBarIconKey = VoiceInkUserDefaultsKey.showMenuBarIcon
    public static let isMenuBarOnlyKey = VoiceInkUserDefaultsKey.isMenuBarOnly
    public static let defaultShowMenuBarIcon = VoiceInkPreferenceDefault.showMenuBarIcon
    public static let defaultIsMenuBarOnly = VoiceInkPreferenceDefault.isMenuBarOnly

    public static var registeredDefaults: [String: Any] {
        [
            showMenuBarIconKey: defaultShowMenuBarIcon,
            isMenuBarOnlyKey: defaultIsMenuBarOnly
        ]
    }

    public static func shouldShowMenuBarIcon(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showMenuBarIconKey)
    }

    public static func saveShowMenuBarIcon(_ shouldShow: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(shouldShow, forKey: showMenuBarIconKey)
    }

    public static func isMenuBarOnly(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: isMenuBarOnlyKey)
    }

    public static func saveIsMenuBarOnly(_ isMenuBarOnly: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isMenuBarOnly, forKey: isMenuBarOnlyKey)
    }
}

public enum VoiceInkMacOSMenuBarPresentation {
    public static let toggleRecorderTitle = "Toggle Recorder"
    public static let manageModelsTitle = "Manage Models"
    public static let aiEnhancementToggleTitle = "AI Enhancement"
    public static let noProvidersConnectedText = "No providers connected"
    public static let noModelsAvailableText = "No models available"
    public static let audioInputTitle = "Audio Input"
    public static let noDevicesAvailableText = "No devices available"
    public static let additionalMenuTitle = "Additional"
    public static let clipboardContextTitle = VoiceInkEnhancementSettingsPresentation.macOS.clipboardContextTitle
    public static let contextAwarenessTitle = VoiceInkPowerModePresentation.contextAwarenessDisplayText
    public static let retryLastTranscriptionTitle = VoiceInkRecordingShortcutPreference.macOSSettingsPresentation.retryLastTranscriptionLabel
    public static let copyLastTranscriptionTitle = "Copy Last Transcription"
    public static let historyTitle = VoiceInkMacOSNavigationDestination.history.rawValue
    public static let permissionsTitle = VoiceInkMacOSNavigationDestination.permissions.rawValue
    public static let settingsTitle = VoiceInkMacOSNavigationDestination.settings.rawValue
    public static let showDockIconTitle = "Show Dock Icon"
    public static let hideDockIconTitle = "Hide Dock Icon"
    public static let hideMenuBarIconTitle = "Hide Menu Bar Icon"
    public static let launchAtLoginTitle = "Launch at Login"
    public static let checkForUpdatesTitle = "Check for Updates"
    public static let helpAndSupportTitle = "Help and Support"
    public static let selectionCheckmarkSystemImageName = "checkmark"
    public static let pickerSystemImageName = "chevron.up.chevron.down"

    public static var quitTitle: String {
        "Quit \(VoiceInkAppIdentity.compactDisplayName)"
    }

    public static func transcriptionModelTitle(currentDisplayName: String?) -> String {
        "Transcription Model: \(currentDisplayName ?? noneDisplayText)"
    }

    public static func promptTitle(activePromptTitle: String?) -> String {
        "Prompt: \(activePromptTitle ?? noneDisplayText)"
    }

    public static func aiProviderTitle(selectedProviderName: String) -> String {
        "AI Provider: \(selectedProviderName)"
    }

    public static func aiModelTitle(currentModelName: String) -> String {
        "AI Model: \(currentModelName)"
    }

    public static func dockIconTitle(isMenuBarOnly: Bool) -> String {
        isMenuBarOnly ? showDockIconTitle : hideDockIconTitle
    }

    private static let noneDisplayText = "None"
}

public struct VoiceInkMacOSShellBackupPreferences: Codable, Equatable, Sendable {
    public let launchAtLoginEnabled: Bool?
    public let isMenuBarOnly: Bool?
    public let recorderType: String?

    public init(
        launchAtLoginEnabled: Bool?,
        isMenuBarOnly: Bool?,
        recorderType: String?
    ) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.isMenuBarOnly = isMenuBarOnly
        self.recorderType = recorderType
    }
}

public struct VoiceInkMacOSShellBackupImportPlan: Equatable, Sendable {
    public let launchAtLoginEnabled: Bool?
    public let isMenuBarOnly: Bool?
    public let recorderType: String?

    public init(
        launchAtLoginEnabled: Bool?,
        isMenuBarOnly: Bool?,
        recorderType: String?
    ) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.isMenuBarOnly = isMenuBarOnly
        self.recorderType = recorderType
    }
}

public enum VoiceInkMacOSShellBackupPreference {
    public static func backupPreferences(
        launchAtLoginEnabled: Bool,
        isMenuBarOnly: Bool,
        recorderType: String
    ) -> VoiceInkMacOSShellBackupPreferences {
        VoiceInkMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            isMenuBarOnly: isMenuBarOnly,
            recorderType: recorderType
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkMacOSShellBackupPreferences
    ) -> VoiceInkMacOSShellBackupImportPlan {
        VoiceInkMacOSShellBackupImportPlan(
            launchAtLoginEnabled: preferences.launchAtLoginEnabled,
            isMenuBarOnly: preferences.isMenuBarOnly,
            recorderType: preferences.recorderType
        )
    }
}

public enum VoiceInkAudioSessionTimeoutPreference {
    public static let minimumSeconds = 0
    public static let maximumSeconds = 300
    public static let stepSeconds = 15
    public static let countdownUpdateInterval: TimeInterval = 1.0
    public static let settingsPresentation = VoiceInkAudioSessionTimeoutPresentation.iOS

    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds) as? Int
            ?? VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
    }

    public static func displayText(for seconds: Int) -> String {
        "\(seconds)s"
    }

    public static func deactivationPlan(for seconds: Int) -> VoiceInkAudioSessionDeactivationPlan {
        seconds <= 0 ? .immediate : .delayed(TimeInterval(seconds))
    }

    public static func remainingTimeAfterCountdownTick(_ remainingTime: TimeInterval) -> TimeInterval {
        remainingTime - countdownUpdateInterval
    }

    public static func saveTimeoutSeconds(_ seconds: Int, to defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)
    }
}

public struct VoiceInkSettingsTogglePresentation: Equatable, Sendable {
    public let title: String
    public let helpText: String
}

public struct VoiceInkMacOSAdvancedTranscriptionSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let vad: VoiceInkSettingsTogglePresentation
    public let modelPrewarm: VoiceInkSettingsTogglePresentation
    public let liveTextPreview: VoiceInkSettingsTogglePresentation

    public static let macOS = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation(
        sectionTitle: "Advanced",
        vad: VoiceInkSettingsTogglePresentation(
            title: "Voice Activity Detection (VAD)",
            helpText: "Use VAD inside batch/final transcription when supported. Buffer preload has its own VAD model in Rolling Buffer settings."
        ),
        modelPrewarm: VoiceInkSettingsTogglePresentation(
            title: "Prewarm model (Experimental)",
            helpText: "Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization."
        ),
        liveTextPreview: VoiceInkSettingsTogglePresentation(
            title: "Show Transcript Preview",
            helpText: "Displays in-progress transcript text when a model or buffer preload can provide it."
        )
    )
}

public enum VoiceInkVADPreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.isVADEnabled
    public static let defaultIsEnabled = VoiceInkPreferenceDefault.isVADEnabled
    public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.vad

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkTranscriptionPromptPreference {
    public static func storedPrompt(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }

    public static func localWhisperPrompt(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        storedPrompt(from: defaults) ?? fallback
    }

    public static func localWhisperPromptForSelectedLanguage(
        from defaults: UserDefaults = .standard
    ) -> String {
        localWhisperPrompt(
            from: defaults,
            fallback: VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults)
        )
    }

    @discardableResult
    public static func saveLocalWhisperPromptForSelectedLanguage(
        from defaults: UserDefaults = .standard,
        customPrompts: [String: String]? = nil,
        fallbackLanguage: String = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    ) -> String {
        let prompt = VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(
            from: defaults,
            customPrompts: customPrompts,
            fallbackLanguage: fallbackLanguage
        )
        savePrompt(prompt, to: defaults)
        return prompt
    }

    public static func requestPrompt(from defaults: UserDefaults = .standard) -> String? {
        requestPrompt(storedPrompt(from: defaults))
    }

    public static func requestPrompt(_ prompt: String?) -> String? {
        VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(prompt)
    }

    public static func savePrompt(_ prompt: String, to defaults: UserDefaults = .standard) {
        defaults.set(prompt, forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }

    public static func clearPrompt(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }
}

public enum VoiceInkTranscriptionLanguagePreference {
    public static func storedLanguage(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func selectedLanguage(
        from defaults: UserDefaults = .standard,
        fallback: String = VoiceInkLanguageCatalog.autoDetectCode
    ) -> String {
        storedLanguage(from: defaults) ?? fallback
    }

    public static func selectedMacOSLanguage(from defaults: UserDefaults = .standard) -> String {
        selectedLanguage(
            from: defaults,
            fallback: VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
        )
    }

    public static func selectedLanguage(
        source: VoiceInkTranscriptionLanguageSource,
        from defaults: UserDefaults = .standard,
        isMultilingual: Bool = true,
        assemblyAIUsesRealtime: Bool = false
    ) -> String {
        VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            storedLanguage(from: defaults),
            source: source,
            isMultilingual: isMultilingual,
            assemblyAIUsesRealtime: assemblyAIUsesRealtime
        )
    }

    public static func saveSelectedLanguage(
        _ language: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(language, forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    @discardableResult
    public static func saveCompatibleLanguage(
        _ language: String?,
        languages: [String: String],
        to defaults: UserDefaults = .standard,
        prefersNativeAppleEnglish: Bool = false
    ) -> String {
        let compatibleLanguage = VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            language,
            languages: languages,
            prefersNativeAppleEnglish: prefersNativeAppleEnglish
        )
        saveSelectedLanguage(compatibleLanguage, to: defaults)
        return compatibleLanguage
    }

    public static func clearSelectedLanguage(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func requestLanguage(from defaults: UserDefaults = .standard) -> String? {
        VoiceInkTranscriptionLanguageSupport.requestLanguage(selectedLanguage(from: defaults))
    }
}

public enum VoiceInkCurrentTranscriptionModelPreference {
    static let legacyModelNameKey = "CurrentModel"

    public static func modelName(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }

    public static func saveModelName(_ modelName: String, to defaults: UserDefaults = .standard) {
        defaults.set(modelName, forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }

    public static func clearModelName(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
        defaults.removeObject(forKey: legacyModelNameKey)
    }

    public static func loadPlan(
        savedModelName: String?,
        candidateModelExists: Bool,
        isCandidateAvailableOnCurrentOS: Bool
    ) -> VoiceInkCurrentTranscriptionModelLoadPlan {
        VoiceInkCurrentTranscriptionModelLoadPlan(
            savedModelName: savedModelName,
            candidateModelExists: candidateModelExists,
            isCandidateAvailableOnCurrentOS: isCandidateAvailableOnCurrentOS
        )
    }
}

public enum VoiceInkCurrentTranscriptionModelLoadAction: Equatable, Sendable {
    case none
    case restoreSavedModel
    case clearStoredModelName
}

public struct VoiceInkCurrentTranscriptionModelLoadPlan: Equatable, Sendable {
    public let action: VoiceInkCurrentTranscriptionModelLoadAction

    public init(
        savedModelName: String?,
        candidateModelExists: Bool,
        isCandidateAvailableOnCurrentOS: Bool
    ) {
        guard savedModelName != nil, candidateModelExists else {
            self.action = .none
            return
        }

        self.action = isCandidateAvailableOnCurrentOS
            ? .restoreSavedModel
            : .clearStoredModelName
    }

    public var shouldRestoreSavedModel: Bool {
        action == .restoreSavedModel
    }

    public var shouldClearStoredModelName: Bool {
        action == .clearStoredModelName
    }
}

public enum VoiceInkAIEnhancementPreference {
    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
    }

    public static func statusDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        isEnabled(from: defaults) ? "Enabled" : "Disabled"
    }
}

public enum VoiceInkAIEnhancementContextPreference {
    public static func useClipboardContext(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.useClipboardContext)
    }

    public static func saveUseClipboardContext(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.useClipboardContext)
    }

    public static func useScreenCaptureContext(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
    }

    public static func saveUseScreenCaptureContext(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.useClipboardContext)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
    }
}

public enum VoiceInkAIEnhancementProviderPreference {
    public static let defaultSelectedProvider = VoiceInkAIEnhancementProviderKind.gemini

    public static func selectedProviderRawValue(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
    }

    public static func selectedProviderDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        selectedProviderRawValue(from: defaults) ?? "None selected"
    }

    public static func saveSelectedProviderRawValue(_ rawValue: String, to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
    }

    public static func saveSelectedProvider(
        _ provider: VoiceInkAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) {
        saveSelectedProviderRawValue(provider.rawValue, to: defaults)
    }

    @discardableResult
    public static func applyProviderSelectionPlan(
        _ plan: VoiceInkAIEnhancementProviderSelectionPlan,
        to defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementProviderKind {
        saveSelectedProvider(plan.selectedProviderToSave, to: defaults)
        return plan.selectedProviderToSave
    }

    public static func selectedProvider(
        default defaultProvider: VoiceInkAIEnhancementProviderKind = VoiceInkAIEnhancementProviderPreference.defaultSelectedProvider,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementProviderKind {
        guard let storedProvider = selectedProviderRawValue(from: defaults),
              let provider = VoiceInkAIEnhancementProviderKind(storedValue: storedProvider)
        else {
            return defaultProvider
        }

        if storedProvider != provider.rawValue {
            saveSelectedProviderRawValue(provider.rawValue, to: defaults)
        }

        return provider
    }

    public static func selectedModels(
        for providers: [VoiceInkAIEnhancementProviderKind] = VoiceInkAIEnhancementProviderKind.allCases,
        from defaults: UserDefaults = .standard
    ) -> [VoiceInkAIEnhancementProviderKind: String] {
        providers.reduce(into: [:]) { models, provider in
            if let model = selectedModel(for: provider.rawValue, from: defaults) {
                models[provider] = model
            }
        }
    }

    public static func selectedModel(
        for providerRawValue: String,
        from defaults: UserDefaults = .standard
    ) -> String? {
        let savedModel = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(providerRawValue))
        return savedModel?.isEmpty == false ? savedModel : nil
    }

    public static func selectedModelDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        guard let providerRawValue = selectedProviderRawValue(from: defaults) else {
            return "None selected"
        }

        return selectedModel(for: providerRawValue, from: defaults) ?? "Default (\(providerRawValue))"
    }

    public static func saveSelectedModel(
        _ model: String,
        for providerRawValue: String,
        to defaults: UserDefaults = .standard
    ) {
        guard !model.isEmpty else { return }
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(providerRawValue))
    }

    public static func saveSelectedModel(
        _ model: String,
        for provider: VoiceInkAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) {
        saveSelectedModel(model, for: provider.rawValue, to: defaults)
    }

    @discardableResult
    public static func applyModelSelectionPlan(
        _ plan: VoiceInkAIEnhancementModelSelectionPlan,
        to defaults: UserDefaults = .standard
    ) -> String {
        saveSelectedModel(plan.selectedModelToSave, for: plan.provider, to: defaults)
        return plan.selectedModelToSave
    }

    @discardableResult
    public static func applyModelRefreshPlan(
        _ plan: VoiceInkAIEnhancementModelRefreshPlan,
        for provider: VoiceInkAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) -> String? {
        guard let selectedModel = plan.selectedModelToSave else {
            return nil
        }

        saveSelectedModel(selectedModel, for: provider, to: defaults)
        return selectedModel
    }

    public static func clear(
        from defaults: UserDefaults = .standard,
        providers: [VoiceInkAIEnhancementProviderKind] = VoiceInkAIEnhancementProviderKind.allCases
    ) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        providers.forEach {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel($0.rawValue))
        }
    }
}

public enum VoiceInkDynamicAIProviderPreference {
    public static let defaultOllamaBaseURL = VoiceInkPreferenceDefault.ollamaBaseURL
    public static let defaultOllamaRuntimeSelectedModel = VoiceInkAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback

    public static func ollamaBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = defaultOllamaBaseURL
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.ollamaBaseURL) ?? fallback
    }

    public static func saveOllamaBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
    }

    public static func ollamaSelectedModel(
        from defaults: UserDefaults = .standard,
        fallback: String
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel) ?? fallback
    }

    public static func ollamaRuntimeSelectedModel(from defaults: UserDefaults = .standard) -> String {
        ollamaSelectedModel(from: defaults, fallback: defaultOllamaRuntimeSelectedModel)
    }

    public static func saveOllamaSelectedModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel)
    }

    @discardableResult
    public static func applyOllamaModelRefreshPlan(
        _ plan: VoiceInkAIEnhancementModelRefreshPlan,
        to defaults: UserDefaults = .standard
    ) -> String? {
        guard let selectedModel = plan.selectedModelToSave else {
            return nil
        }

        saveOllamaSelectedModel(selectedModel, to: defaults)
        return selectedModel
    }

    public static func customProviderBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.customProviderBaseURL) ?? fallback
    }

    public static func saveCustomProviderBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: VoiceInkUserDefaultsKey.customProviderBaseURL)
    }

    public static func customProviderModel(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.customProviderModel) ?? fallback
    }

    public static func saveCustomProviderModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.customProviderModel)
    }

    public static func openRouterModels(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.openRouterModels) ?? []
    }

    public static func saveOpenRouterModels(_ models: [String], to defaults: UserDefaults = .standard) {
        defaults.set(models, forKey: VoiceInkUserDefaultsKey.openRouterModels)
    }

    @discardableResult
    public static func applyOpenRouterModelRefreshPlan(
        _ plan: VoiceInkAIEnhancementModelRefreshPlan,
        to defaults: UserDefaults = .standard
    ) -> String? {
        saveOpenRouterModels(plan.refreshedModelNames, to: defaults)
        return VoiceInkAIEnhancementProviderPreference.applyModelRefreshPlan(
            plan,
            for: .openRouter,
            to: defaults
        )
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customProviderBaseURL)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customProviderModel)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.openRouterModels)
    }
}

public enum VoiceInkFillerWordPreference {
    public static func words(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.fillerWords) ?? VoiceInkFillerWords.defaultWords
    }

    public static func saveWords(_ words: [String], to defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: VoiceInkUserDefaultsKey.fillerWords)
    }

    public static func clearWords(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.fillerWords)
    }
}

public enum VoiceInkWordReplacementPreference {
    public static func rules(from defaults: UserDefaults = .standard) -> [VoiceInkWordReplacementRule] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.wordReplacements) else {
            return []
        }

        return (try? JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data)) ?? []
    }

    public static func saveRules(_ rules: [VoiceInkWordReplacementRule], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }

        defaults.set(data, forKey: VoiceInkUserDefaultsKey.wordReplacements)
    }

    public static func clearRules(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.wordReplacements)
    }
}

public enum VoiceInkCustomVocabularyPreference {
    public static func terms(from defaults: UserDefaults = .standard) -> [String] {
        VoiceInkCustomVocabularyTerms.normalized(
            defaults.stringArray(forKey: VoiceInkUserDefaultsKey.customVocabularyTerms) ?? []
        )
    }

    public static func saveTerms(_ terms: [String], to defaults: UserDefaults = .standard) {
        defaults.set(
            VoiceInkCustomVocabularyTerms.normalized(terms),
            forKey: VoiceInkUserDefaultsKey.customVocabularyTerms
        )
    }

    public static func clearTerms(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customVocabularyTerms)
    }
}

public enum VoiceInkAIEnhancementRequestPreference {
    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.integer(forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        return stored > 0
            ? TimeInterval(stored)
            : TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
    }

    public static func shouldRetryOnTimeout(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout) as? Bool
            ?? VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
    }
}

public struct VoiceInkTranscriptionAutoCleanupConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionMinutes: Int

    public init(isEnabled: Bool, retentionMinutes: Int) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }

    public var effectiveRetentionMinutes: Int {
        max(retentionMinutes, 0)
    }

    public var shouldDeleteCompletedTranscriptionImmediately: Bool {
        retentionMinutes <= 0
    }

    public func cutoffDate(from referenceDate: Date = Date()) -> Date {
        referenceDate.addingTimeInterval(TimeInterval(-effectiveRetentionMinutes * 60))
    }

    public var completionAction: VoiceInkTranscriptionAutoCleanupCompletionAction {
        guard isEnabled else { return .ignore }
        return shouldDeleteCompletedTranscriptionImmediately
            ? .deleteCompletedTranscription
            : .sweepOldTranscriptions
    }
}

public enum VoiceInkTranscriptionAutoCleanupCompletionAction: Equatable, Sendable {
    case ignore
    case sweepOldTranscriptions
    case deleteCompletedTranscription
}

public struct VoiceInkTranscriptionAutoCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionMinutes: Int?

    public init(isEnabled: Bool?, retentionMinutes: Int?) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }
}

public struct VoiceInkTranscriptionAutoCleanupBackupImportPlan: Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionMinutes: Int?

    public init(isEnabled: Bool?, retentionMinutes: Int?) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }
}

public enum VoiceInkTranscriptionAutoCleanupPreference {
    public static func current(from defaults: UserDefaults = .standard) -> VoiceInkTranscriptionAutoCleanupConfiguration {
        VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionMinutes: retentionMinutes(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func retentionMinutes(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes) as? Int
            ?? VoiceInkPreferenceDefault.transcriptionRetentionMinutes
    }

    public static func saveRetentionMinutes(_ minutes: Int, to defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func backupPreferences(
        from configuration: VoiceInkTranscriptionAutoCleanupConfiguration
    ) -> VoiceInkTranscriptionAutoCleanupBackupPreferences {
        VoiceInkTranscriptionAutoCleanupBackupPreferences(
            isEnabled: configuration.isEnabled,
            retentionMinutes: configuration.retentionMinutes
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkTranscriptionAutoCleanupBackupPreferences
    ) -> VoiceInkTranscriptionAutoCleanupBackupImportPlan {
        VoiceInkTranscriptionAutoCleanupBackupImportPlan(
            isEnabled: preferences.isEnabled,
            retentionMinutes: preferences.retentionMinutes
        )
    }
}

public struct VoiceInkAudioCleanupConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionDays: Int

    public init(isEnabled: Bool, retentionDays: Int) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }

    public var effectiveRetentionDays: Int {
        max(retentionDays, 0)
    }

    public func cutoffDate(
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: referenceDate) ?? referenceDate
    }
}

public struct VoiceInkAudioCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionDays: Int?

    public init(isEnabled: Bool?, retentionDays: Int?) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }
}

public struct VoiceInkAudioCleanupBackupImportPlan: Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionDays: Int?

    public init(isEnabled: Bool?, retentionDays: Int?) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }
}

public enum VoiceInkAudioCleanupPreference {
    public static let cleanupCheckInterval: TimeInterval = 86_400

    public static func current(from defaults: UserDefaults = .standard) -> VoiceInkAudioCleanupConfiguration {
        VoiceInkAudioCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionDays: retentionDays(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func retentionDays(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays) as? Int
            ?? VoiceInkPreferenceDefault.audioRetentionDays
    }

    public static func saveRetentionDays(_ days: Int, to defaults: UserDefaults = .standard) {
        defaults.set(days, forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func backupPreferences(
        from configuration: VoiceInkAudioCleanupConfiguration
    ) -> VoiceInkAudioCleanupBackupPreferences {
        VoiceInkAudioCleanupBackupPreferences(
            isEnabled: configuration.isEnabled,
            retentionDays: configuration.retentionDays
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkAudioCleanupBackupPreferences
    ) -> VoiceInkAudioCleanupBackupImportPlan {
        VoiceInkAudioCleanupBackupImportPlan(
            isEnabled: preferences.isEnabled,
            retentionDays: preferences.retentionDays
        )
    }
}

public enum VoiceInkModelRuntimePreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.prewarmModelOnWake
    public static let defaultShouldPrewarmModelOnWake = VoiceInkPreferenceDefault.prewarmModelOnWake
    public static let prewarmScheduleDelay: Duration = .seconds(3)
    public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.modelPrewarm

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultShouldPrewarmModelOnWake
        ]
    }

    public static func shouldPrewarmModelOnWake(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultShouldPrewarmModelOnWake
    }

    public static func saveShouldPrewarmModelOnWake(
        _ shouldPrewarm: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPrewarm, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkRecorderPreviewPreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.showLiveTextPreview
    public static let defaultIsLiveTextPreviewEnabled = VoiceInkPreferenceDefault.showLiveTextPreview
    public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.liveTextPreview

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultIsLiveTextPreviewEnabled
        ]
    }

    public static func isLiveTextPreviewEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsLiveTextPreviewEnabled
    }

    public static func saveIsLiveTextPreviewEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkRecordingShortcutSlot: Sendable {
    case primary
    case secondary
}

public enum VoiceInkRecordingShortcutSelection: String, CaseIterable, Sendable {
    case none = "none"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .custom:
            return "Custom"
        }
    }
}

public enum VoiceInkRecordingShortcutMode: String, CaseIterable, Sendable {
    case special = "special"
    case toggle = "toggle"
    case pushToTalk = "pushToTalk"
    case hybrid = "hybrid"

    public var displayName: String {
        switch self {
        case .special:
            return "Special"
        case .toggle:
            return "Toggle"
        case .pushToTalk:
            return "Push to Talk"
        case .hybrid:
            return "Hybrid"
        }
    }

    public var tracksKeyUpEvidence: Bool {
        self == .special
    }

    public var allowsShortcutInterruption: Bool {
        !tracksKeyUpEvidence
    }
}

public enum VoiceInkShortcutActionIdentifier: Hashable, Sendable {
    case primaryRecording
    case secondaryRecording
    case pasteLastTranscription
    case pasteLastEnhancement
    case retryLastTranscription
    case cancelRecorder
    case openHistoryWindow
    case quickAddToDictionary
    case toggleEnhancement
    case powerMode(UUID)
    case miniRecorderEscape
    case miniRecorderPrompt(Int)
    case miniRecorderPowerMode(Int)

    public var storageName: String {
        switch self {
        case .primaryRecording:
            return "primaryRecording"
        case .secondaryRecording:
            return "secondaryRecording"
        case .pasteLastTranscription:
            return "pasteLastTranscription"
        case .pasteLastEnhancement:
            return "pasteLastEnhancement"
        case .retryLastTranscription:
            return "retryLastTranscription"
        case .cancelRecorder:
            return "cancelRecorder"
        case .openHistoryWindow:
            return "openHistoryWindow"
        case .quickAddToDictionary:
            return "quickAddToDictionary"
        case .toggleEnhancement:
            return "toggleEnhancement"
        case .powerMode(let id):
            return "powerMode_\(id.uuidString)"
        case .miniRecorderEscape:
            return "miniRecorderEscape"
        case .miniRecorderPrompt(let index):
            return "miniRecorderPrompt_\(index)"
        case .miniRecorderPowerMode(let index):
            return "miniRecorderPowerMode_\(index)"
        }
    }

    public var shortcutStorageKey: String {
        "Shortcut_\(storageName)"
    }

    public var isStoredShortcut: Bool {
        switch self {
        case .miniRecorderEscape, .miniRecorderPrompt, .miniRecorderPowerMode:
            return false
        default:
            return true
        }
    }

    public var recordingShortcutSlot: VoiceInkRecordingShortcutSlot? {
        switch self {
        case .primaryRecording:
            return .primary
        case .secondaryRecording:
            return .secondary
        default:
            return nil
        }
    }

    public var selectionKey: String {
        recordingShortcutSlot.map(VoiceInkRecordingShortcutPreference.selectionKey(for:)) ?? shortcutStorageKey
    }

    public var legacySelectionKey: String {
        switch self {
        case .primaryRecording:
            return "selectedHotkey1"
        case .secondaryRecording:
            return "selectedHotkey2"
        default:
            return shortcutStorageKey
        }
    }

    public var modeKey: String {
        recordingShortcutSlot.map(VoiceInkRecordingShortcutPreference.modeKey(for:)) ?? shortcutStorageKey
    }

    public var legacyModeKey: String {
        switch self {
        case .primaryRecording:
            return "hotkeyMode1"
        case .secondaryRecording:
            return "hotkeyMode2"
        default:
            return shortcutStorageKey
        }
    }

    public var legacyCustomRecordingShortcutKey: String {
        switch self {
        case .primaryRecording:
            return "CustomRecordingShortcut_primary"
        case .secondaryRecording:
            return "CustomRecordingShortcut_secondary"
        default:
            return "CustomRecordingShortcut_\(storageName)"
        }
    }

    public var legacyKeyboardShortcutName: String? {
        switch self {
        case .primaryRecording:
            return "toggleMiniRecorder"
        case .secondaryRecording:
            return "toggleMiniRecorder2"
        case .pasteLastTranscription:
            return "pasteLastTranscription"
        case .pasteLastEnhancement:
            return "pasteLastEnhancement"
        case .retryLastTranscription:
            return "retryLastTranscription"
        case .cancelRecorder:
            return "cancelRecorder"
        case .openHistoryWindow:
            return "openHistoryWindow"
        case .quickAddToDictionary:
            return "quickAddToDictionary"
        case .toggleEnhancement:
            return "toggleEnhancement"
        case .powerMode(let id):
            return "powerMode_\(id.uuidString)"
        case .miniRecorderEscape, .miniRecorderPrompt, .miniRecorderPowerMode:
            return nil
        }
    }

    public var legacyKeyboardShortcutStorageKey: String? {
        legacyKeyboardShortcutName.map { "KeyboardShortcuts_\($0)" }
    }

    public static let legacyKeyboardShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary,
        .toggleEnhancement
    ]

    public static let legacyCustomRecordingShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording
    ]
}

public enum VoiceInkShortcutActionPresentation {
    public static let primaryRecordingDisplayName = "Primary Shortcut"
    public static let secondaryRecordingDisplayName = "Secondary Shortcut"
    public static let pasteLastTranscriptionDisplayName = "Paste Last Transcription"
    public static let pasteLastEnhancementDisplayName = "Paste Last Enhanced Transcription"
    public static let retryLastTranscriptionDisplayName = "Retry Last Transcription"
    public static let cancelRecorderDisplayName = "Cancel Recording"
    public static let openHistoryWindowDisplayName = VoiceInkHistoryPresentation.macOSShortcutTip.shortcutLabel
    public static let quickAddToDictionaryDisplayName = "Quick Add to Dictionary"
    public static let toggleEnhancementDisplayName = "Toggle Enhancement"
    public static let fallbackPowerModeDisplayName = "Power Mode"
    public static let miniRecorderEscapeDisplayName = "Mini Recorder Cancel"

    public static func displayName(
        for identifier: VoiceInkShortcutActionIdentifier,
        powerModeName: String? = nil
    ) -> String {
        switch identifier {
        case .primaryRecording:
            return primaryRecordingDisplayName
        case .secondaryRecording:
            return secondaryRecordingDisplayName
        case .pasteLastTranscription:
            return pasteLastTranscriptionDisplayName
        case .pasteLastEnhancement:
            return pasteLastEnhancementDisplayName
        case .retryLastTranscription:
            return retryLastTranscriptionDisplayName
        case .cancelRecorder:
            return cancelRecorderDisplayName
        case .openHistoryWindow:
            return openHistoryWindowDisplayName
        case .quickAddToDictionary:
            return quickAddToDictionaryDisplayName
        case .toggleEnhancement:
            return toggleEnhancementDisplayName
        case .powerMode:
            guard let powerModeName else {
                return fallbackPowerModeDisplayName
            }
            return "\(powerModeName) Power Mode"
        case .miniRecorderEscape:
            return miniRecorderEscapeDisplayName
        case .miniRecorderPrompt(let index):
            return "Select Prompt \(displayNumber(forMiniRecorderIndex: index))"
        case .miniRecorderPowerMode(let index):
            return "Select Power Mode \(displayNumber(forMiniRecorderIndex: index))"
        }
    }

    public static func displayNumber(forMiniRecorderIndex index: Int) -> String {
        index == 9 ? "10" : "\(index + 1)"
    }
}

public enum VoiceInkShortcutValidationIssue: Equatable, Sendable {
    case plainKeyRequiresModifier
    case shiftTypingKeyRequiresAdditionalModifier
    case reservedBySystem
    case alreadyUsedBy(String)
}

public enum VoiceInkShortcutValidationPresentation {
    public static func notificationTitle(
        for issue: VoiceInkShortcutValidationIssue,
        shortcutDisplayString: String
    ) -> String {
        switch issue {
        case .plainKeyRequiresModifier, .shiftTypingKeyRequiresAdditionalModifier:
            return "Shortcut not allowed: \(shortcutDisplayString)"
        case .reservedBySystem:
            return "Shortcut reserved by macOS: \(shortcutDisplayString)"
        case .alreadyUsedBy(let actionName):
            return "Shortcut already used by \(actionName)"
        }
    }
}

public struct VoiceInkMacOSShortcutNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let duration: TimeInterval
    public let actionButtonLabel: String?

    public init(title: String, duration: TimeInterval, actionButtonLabel: String? = nil) {
        self.title = title
        self.duration = duration
        self.actionButtonLabel = actionButtonLabel
    }

    public static let inputMonitoringPermissionRequired = Self(
        title: "Enable Input Monitoring for shortcuts",
        duration: 6,
        actionButtonLabel: "Open Settings"
    )

    public static let accessibilityPermissionRequired = Self(
        title: "Enable Accessibility for shortcuts",
        duration: 6,
        actionButtonLabel: "Open Settings"
    )

    public static let monitorStartFailed = Self(
        title: "Keyboard shortcut monitor could not start",
        duration: 6
    )

    public static func miniRecorderEscapeConfirmation(duration: TimeInterval) -> Self {
        Self(
            title: "Press ESC again to cancel recording",
            duration: duration
        )
    }
}

public enum VoiceInkMiniRecorderEscapeShortcutPolicy {
    public static let doublePressThreshold: TimeInterval = 1.5

    public static var confirmationPresentation: VoiceInkMacOSShortcutNotificationPresentation {
        VoiceInkMacOSShortcutNotificationPresentation.miniRecorderEscapeConfirmation(
            duration: doublePressThreshold
        )
    }

    public static func isSecondPress(
        firstPressTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let firstPressTime else { return false }
        return now.timeIntervalSince(firstPressTime) <= doublePressThreshold
    }

    public static func timeoutNanoseconds(threshold: TimeInterval = doublePressThreshold) -> UInt64 {
        VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: threshold)
    }
}

public enum VoiceInkLegacyRecordingShortcutPreset: String, CaseIterable, Sendable {
    case rightOption
    case leftOption
    case leftControl
    case rightControl
    case fn
    case rightCommand
    case rightShift
    case leftShift
}

public struct VoiceInkMacOSRecordingShortcutSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let primaryShortcutLabel: String
    public let secondaryShortcutLabel: String
    public let addSecondaryShortcutButtonTitle: String
    public let emptyTapPasteLastTranscriptLabel: String
    public let additionalSectionTitle: String
    public let pasteLastTranscriptionOriginalLabel: String
    public let pasteLastTranscriptionEnhancedLabel: String
    public let retryLastTranscriptionLabel: String
    public let cancelRecordingLabel: String
    public let resetToDefaultHelp: String
    public let middleClickRecordingLabel: String
    public let activationDelayLabel: String
    public let activationDelayUnitLabel: String

    public static let macOS = VoiceInkMacOSRecordingShortcutSettingsPresentation(
        sectionTitle: "Shortcuts",
        primaryShortcutLabel: "Primary Shortcut",
        secondaryShortcutLabel: "Secondary Shortcut",
        addSecondaryShortcutButtonTitle: "Add Second Shortcut",
        emptyTapPasteLastTranscriptLabel: "Empty Tap Pastes Last",
        additionalSectionTitle: "Additional Shortcuts",
        pasteLastTranscriptionOriginalLabel: "Paste Last Transcription (Original)",
        pasteLastTranscriptionEnhancedLabel: "Paste Last Transcription (Enhanced)",
        retryLastTranscriptionLabel: "Retry Last Transcription",
        cancelRecordingLabel: "Cancel Recording",
        resetToDefaultHelp: "Reset to default",
        middleClickRecordingLabel: "Middle-Click Recording",
        activationDelayLabel: "Activation Delay",
        activationDelayUnitLabel: "ms"
    )
}

public struct VoiceInkMacOSShortcutRecorderPresentation: Equatable, Sendable {
    public let recordingPlaceholderText: String
    public let idleAccessibilityLabel: String
    public let idleButtonText: String

    public static let macOS = VoiceInkMacOSShortcutRecorderPresentation(
        recordingPlaceholderText: "Press shortcut",
        idleAccessibilityLabel: "Record shortcut",
        idleButtonText: "Record"
    )
}

public struct VoiceInkRecordingShortcutBackupPreferences: Codable, Equatable, Sendable {
    public let primaryRecordingShortcutRawValue: String?
    public let secondaryRecordingShortcutRawValue: String?
    public let primaryRecordingShortcutModeRawValue: String?
    public let secondaryRecordingShortcutModeRawValue: String?
    public let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    public let isMiddleClickToggleEnabled: Bool?
    public let middleClickActivationDelay: Int?

    public init(
        primaryRecordingShortcutRawValue: String?,
        secondaryRecordingShortcutRawValue: String?,
        primaryRecordingShortcutModeRawValue: String?,
        secondaryRecordingShortcutModeRawValue: String?,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool?,
        isMiddleClickToggleEnabled: Bool?,
        middleClickActivationDelay: Int?
    ) {
        self.primaryRecordingShortcutRawValue = primaryRecordingShortcutRawValue
        self.secondaryRecordingShortcutRawValue = secondaryRecordingShortcutRawValue
        self.primaryRecordingShortcutModeRawValue = primaryRecordingShortcutModeRawValue
        self.secondaryRecordingShortcutModeRawValue = secondaryRecordingShortcutModeRawValue
        self.specialShortcutPasteLastTranscriptOnEmptyTap = specialShortcutPasteLastTranscriptOnEmptyTap
        self.isMiddleClickToggleEnabled = isMiddleClickToggleEnabled
        self.middleClickActivationDelay = middleClickActivationDelay
    }
}

public struct VoiceInkRecordingShortcutBackupImportPlan: Equatable, Sendable {
    public let primaryRecordingShortcut: VoiceInkRecordingShortcutSelection?
    public let secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection?
    public let primaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?
    public let secondaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?
    public let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    public let isMiddleClickToggleEnabled: Bool?
    public let middleClickActivationDelay: Int?

    public init(
        primaryRecordingShortcut: VoiceInkRecordingShortcutSelection?,
        secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection?,
        primaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?,
        secondaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool?,
        isMiddleClickToggleEnabled: Bool?,
        middleClickActivationDelay: Int?
    ) {
        self.primaryRecordingShortcut = primaryRecordingShortcut
        self.secondaryRecordingShortcut = secondaryRecordingShortcut
        self.primaryRecordingShortcutMode = primaryRecordingShortcutMode
        self.secondaryRecordingShortcutMode = secondaryRecordingShortcutMode
        self.specialShortcutPasteLastTranscriptOnEmptyTap = specialShortcutPasteLastTranscriptOnEmptyTap
        self.isMiddleClickToggleEnabled = isMiddleClickToggleEnabled
        self.middleClickActivationDelay = middleClickActivationDelay
    }
}

public struct VoiceInkShortcutBackupImport: Equatable, Sendable {
    public let actionIdentifier: VoiceInkShortcutActionIdentifier
    public let recordingShortcutSlot: VoiceInkRecordingShortcutSlot?
    public let recordingShortcutSelection: VoiceInkRecordingShortcutSelection?

    public init(
        actionIdentifier: VoiceInkShortcutActionIdentifier,
        recordingShortcutSlot: VoiceInkRecordingShortcutSlot?,
        recordingShortcutSelection: VoiceInkRecordingShortcutSelection?
    ) {
        self.actionIdentifier = actionIdentifier
        self.recordingShortcutSlot = recordingShortcutSlot
        self.recordingShortcutSelection = recordingShortcutSelection
    }
}

public enum VoiceInkShortcutBackupPolicy {
    public static let generalBackupShortcutActionIdentifiers: [VoiceInkShortcutActionIdentifier] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary,
        .toggleEnhancement
    ]

    public static func generalBackupShortcutExportPlan(
        availableActionIdentifiers: Set<VoiceInkShortcutActionIdentifier>
    ) -> [VoiceInkShortcutActionIdentifier] {
        generalBackupShortcutActionIdentifiers.filter(availableActionIdentifiers.contains)
    }

    public static func generalBackupShortcutImportPlan(
        importedActionIdentifiers: Set<VoiceInkShortcutActionIdentifier>
    ) -> [VoiceInkShortcutBackupImport] {
        generalBackupShortcutActionIdentifiers.compactMap { actionIdentifier in
            guard importedActionIdentifiers.contains(actionIdentifier) else {
                return nil
            }

            let slot = actionIdentifier.recordingShortcutSlot
            return VoiceInkShortcutBackupImport(
                actionIdentifier: actionIdentifier,
                recordingShortcutSlot: slot,
                recordingShortcutSelection: slot == nil ? nil : .custom
            )
        }
    }
}

public struct VoiceInkShortcutStorageState: Equatable, Sendable {
    public let shortcutData: Data?
    public let clearedValue: Bool?

    public init(shortcutData: Data?, clearedValue: Bool?) {
        self.shortcutData = shortcutData
        self.clearedValue = clearedValue
    }
}

public struct VoiceInkRecordingShortcutSelectionMigrationPlan: Equatable, Sendable {
    public let selection: VoiceInkRecordingShortcutSelection
    public let destinationKey: String?
    public let legacyKeyToRemove: String?
    public let presetToStore: VoiceInkLegacyRecordingShortcutPreset?
    public let defaultPresetToStore: VoiceInkLegacyRecordingShortcutPreset?

    public init(
        selection: VoiceInkRecordingShortcutSelection,
        destinationKey: String?,
        legacyKeyToRemove: String?,
        presetToStore: VoiceInkLegacyRecordingShortcutPreset?,
        defaultPresetToStore: VoiceInkLegacyRecordingShortcutPreset?
    ) {
        self.selection = selection
        self.destinationKey = destinationKey
        self.legacyKeyToRemove = legacyKeyToRemove
        self.presetToStore = presetToStore
        self.defaultPresetToStore = defaultPresetToStore
    }
}

public enum VoiceInkShortcutStoragePreference {
    public static func clearedKey(for shortcutKey: String) -> String {
        "\(shortcutKey)_cleared"
    }

    public static func shortcutData(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) -> Data? {
        defaults.data(forKey: shortcutKey)
    }

    public static func isShortcutCleared(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: clearedKey(for: shortcutKey))
    }

    public static func saveShortcutData(
        _ data: Data,
        for shortcutKey: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(data, forKey: shortcutKey)
        defaults.removeObject(forKey: clearedKey(for: shortcutKey))
    }

    public static func markShortcutCleared(
        for shortcutKey: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: shortcutKey)
        defaults.set(true, forKey: clearedKey(for: shortcutKey))
    }

    public static func removeShortcutStorage(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: shortcutKey)
        defaults.removeObject(forKey: clearedKey(for: shortcutKey))
    }

    public static func storedState(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkShortcutStorageState {
        let clearedKey = clearedKey(for: shortcutKey)
        return VoiceInkShortcutStorageState(
            shortcutData: shortcutData(for: shortcutKey, from: defaults),
            clearedValue: defaults.object(forKey: clearedKey) == nil ? nil : defaults.bool(forKey: clearedKey)
        )
    }

    public static func restoreStoredState(
        _ state: VoiceInkShortcutStorageState,
        for shortcutKey: String,
        to defaults: UserDefaults = .standard
    ) {
        if let shortcutData = state.shortcutData {
            defaults.set(shortcutData, forKey: shortcutKey)
        } else {
            defaults.removeObject(forKey: shortcutKey)
        }

        let clearedKey = clearedKey(for: shortcutKey)
        if let clearedValue = state.clearedValue {
            defaults.set(clearedValue, forKey: clearedKey)
        } else {
            defaults.removeObject(forKey: clearedKey)
        }
    }
}

public enum VoiceInkRecordingShortcutPreference {
    public static let legacyKeyboardShortcutsMigrationKey = "Shortcut_LegacyKeyboardShortcutsMigrated"
    public static let legacyCustomRecordingShortcutsMigrationKey = "Shortcut_LegacyCustomRecordingShortcutsMigrated"
    public static let minimumMiddleClickActivationDelay = 0
    public static let shortcutDidChangeNotificationName = Notification.Name("ShortcutStoreShortcutDidChange")
    public static let shortcutRecordingDidStartNotificationName = Notification.Name("ShortcutRecorderRecordingDidStart")

    public static let macOSSettingsPresentation = VoiceInkMacOSRecordingShortcutSettingsPresentation.macOS
    public static let macOSRecorderPresentation = VoiceInkMacOSShortcutRecorderPresentation.macOS

    public static var registeredDefaults: [String: Any] {
        [
            VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled: VoiceInkPreferenceDefault.isMiddleClickToggleEnabled,
            VoiceInkUserDefaultsKey.middleClickActivationDelay: VoiceInkPreferenceDefault.middleClickActivationDelay,
            VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap: VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
        ]
    }

    public static func isLegacyKeyboardShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: legacyKeyboardShortcutsMigrationKey)
    }

    public static func markLegacyKeyboardShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: legacyKeyboardShortcutsMigrationKey)
    }

    public static func isLegacyCustomRecordingShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: legacyCustomRecordingShortcutsMigrationKey)
    }

    public static func markLegacyCustomRecordingShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: legacyCustomRecordingShortcutsMigrationKey)
    }

    public static func shortcutSelectionMigrationPlan(
        for action: VoiceInkShortcutActionIdentifier,
        allowsNone: Bool,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutSelectionMigrationPlan {
        let destinationKey = action.selectionKey
        let legacyKey = action.legacySelectionKey
        let legacyKeyToRemove = legacyKey == destinationKey ? nil : legacyKey

        if let storedValue = nonEmptyString(forKey: destinationKey, from: defaults) {
            return shortcutSelectionMigrationPlan(
                from: storedValue,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                allowsNone: allowsNone
            )
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey, from: defaults) {
            return shortcutSelectionMigrationPlan(
                from: legacyValue,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                allowsNone: allowsNone
            )
        }

        guard !allowsNone else {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: .none,
                destinationKey: nil,
                legacyKeyToRemove: nil,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        let slot = action.recordingShortcutSlot ?? .primary
        return VoiceInkRecordingShortcutSelectionMigrationPlan(
            selection: defaultSelection(for: slot),
            destinationKey: destinationKey,
            legacyKeyToRemove: nil,
            presetToStore: nil,
            defaultPresetToStore: action == .primaryRecording ? .leftShift : nil
        )
    }

    public static func applyShortcutSelectionMigrationPlan(
        _ plan: VoiceInkRecordingShortcutSelectionMigrationPlan,
        to defaults: UserDefaults = .standard
    ) {
        if let destinationKey = plan.destinationKey {
            defaults.set(plan.selection.rawValue, forKey: destinationKey)
        }

        if let legacyKeyToRemove = plan.legacyKeyToRemove {
            defaults.removeObject(forKey: legacyKeyToRemove)
        }
    }

    public static func migrateShortcutMode(
        for action: VoiceInkShortcutActionIdentifier,
        in defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutMode {
        let destinationKey = action.modeKey
        let legacyKey = action.legacyModeKey
        let legacyKeyToRemove = legacyKey == destinationKey ? nil : legacyKey

        if let storedValue = nonEmptyString(forKey: destinationKey, from: defaults),
           let mode = VoiceInkRecordingShortcutMode(rawValue: storedValue) {
            if let legacyKeyToRemove {
                defaults.removeObject(forKey: legacyKeyToRemove)
            }
            return mode
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey, from: defaults),
           let mode = VoiceInkRecordingShortcutMode(rawValue: legacyValue) {
            defaults.set(mode.rawValue, forKey: destinationKey)
            if let legacyKeyToRemove {
                defaults.removeObject(forKey: legacyKeyToRemove)
            }
            return mode
        }

        let slot = action.recordingShortcutSlot ?? .secondary
        return defaultMode(for: slot)
    }

    public static func removeLegacyCustomRecordingShortcut(
        for action: VoiceInkShortcutActionIdentifier,
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: action.legacyCustomRecordingShortcutKey)
    }

    public static func removeLegacyKeyboardShortcut(
        for action: VoiceInkShortcutActionIdentifier,
        from defaults: UserDefaults = .standard
    ) {
        guard let key = action.legacyKeyboardShortcutStorageKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func selectionKey(for slot: VoiceInkRecordingShortcutSlot) -> String {
        switch slot {
        case .primary:
            return VoiceInkUserDefaultsKey.primaryRecordingShortcut
        case .secondary:
            return VoiceInkUserDefaultsKey.secondaryRecordingShortcut
        }
    }

    public static func modeKey(for slot: VoiceInkRecordingShortcutSlot) -> String {
        switch slot {
        case .primary:
            return VoiceInkUserDefaultsKey.primaryRecordingShortcutMode
        case .secondary:
            return VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode
        }
    }

    public static func defaultSelection(for slot: VoiceInkRecordingShortcutSlot) -> VoiceInkRecordingShortcutSelection {
        switch slot {
        case .primary:
            return .custom
        case .secondary:
            return .none
        }
    }

    public static func defaultMode(for slot: VoiceInkRecordingShortcutSlot) -> VoiceInkRecordingShortcutMode {
        switch slot {
        case .primary:
            return .special
        case .secondary:
            return .hybrid
        }
    }

    public static func backupPreferences(
        primaryRecordingShortcut: VoiceInkRecordingShortcutSelection,
        secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection,
        primaryRecordingShortcutMode: VoiceInkRecordingShortcutMode,
        secondaryRecordingShortcutMode: VoiceInkRecordingShortcutMode,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool,
        isMiddleClickToggleEnabled: Bool,
        middleClickActivationDelay: Int
    ) -> VoiceInkRecordingShortcutBackupPreferences {
        VoiceInkRecordingShortcutBackupPreferences(
            primaryRecordingShortcutRawValue: primaryRecordingShortcut.rawValue,
            secondaryRecordingShortcutRawValue: secondaryRecordingShortcut.rawValue,
            primaryRecordingShortcutModeRawValue: primaryRecordingShortcutMode.rawValue,
            secondaryRecordingShortcutModeRawValue: secondaryRecordingShortcutMode.rawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: isMiddleClickToggleEnabled,
            middleClickActivationDelay: middleClickActivationDelay
        )
    }

    public static func backupImportPlan(
        from backup: VoiceInkRecordingShortcutBackupPreferences
    ) -> VoiceInkRecordingShortcutBackupImportPlan {
        VoiceInkRecordingShortcutBackupImportPlan(
            primaryRecordingShortcut: backup.primaryRecordingShortcutRawValue.flatMap(VoiceInkRecordingShortcutSelection.init(rawValue:)),
            secondaryRecordingShortcut: backup.secondaryRecordingShortcutRawValue.flatMap(VoiceInkRecordingShortcutSelection.init(rawValue:)),
            primaryRecordingShortcutMode: backup.primaryRecordingShortcutModeRawValue.flatMap(VoiceInkRecordingShortcutMode.init(rawValue:)),
            secondaryRecordingShortcutMode: backup.secondaryRecordingShortcutModeRawValue.flatMap(VoiceInkRecordingShortcutMode.init(rawValue:)),
            specialShortcutPasteLastTranscriptOnEmptyTap: backup.specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: backup.isMiddleClickToggleEnabled,
            middleClickActivationDelay: backup.middleClickActivationDelay.map(Self.normalizedMiddleClickActivationDelay)
        )
    }

    public static func selection(
        for slot: VoiceInkRecordingShortcutSlot,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutSelection? {
        defaults.string(forKey: selectionKey(for: slot)).flatMap(VoiceInkRecordingShortcutSelection.init(rawValue:))
    }

    public static func saveSelection(
        _ selection: VoiceInkRecordingShortcutSelection,
        for slot: VoiceInkRecordingShortcutSlot,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(selection.rawValue, forKey: selectionKey(for: slot))
    }

    public static func mode(
        for slot: VoiceInkRecordingShortcutSlot,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutMode {
        defaults.string(forKey: modeKey(for: slot)).flatMap(VoiceInkRecordingShortcutMode.init(rawValue:))
            ?? defaultMode(for: slot)
    }

    public static func saveMode(
        _ mode: VoiceInkRecordingShortcutMode,
        for slot: VoiceInkRecordingShortcutSlot,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: modeKey(for: slot))
    }

    public static func isMiddleClickToggleEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled) as? Bool
            ?? VoiceInkPreferenceDefault.isMiddleClickToggleEnabled
    }

    public static func saveMiddleClickToggleEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled)
    }

    public static func middleClickActivationDelay(from defaults: UserDefaults = .standard) -> Int {
        normalizedMiddleClickActivationDelay(
            defaults.object(forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay) as? Int
                ?? VoiceInkPreferenceDefault.middleClickActivationDelay
        )
    }

    public static func saveMiddleClickActivationDelay(
        _ delay: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(
            normalizedMiddleClickActivationDelay(delay),
            forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay
        )
    }

    public static func normalizedMiddleClickActivationDelay(_ delay: Int) -> Int {
        max(delay, minimumMiddleClickActivationDelay)
    }

    public static func shouldPasteLastTranscriptOnEmptyTap(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap) as? Bool
            ?? VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
    }

    public static func saveShouldPasteLastTranscriptOnEmptyTap(
        _ shouldPaste: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPaste, forKey: VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcut)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.secondaryRecordingShortcut)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcutMode)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap)
    }

    private static func shortcutSelectionMigrationPlan(
        from rawValue: String,
        destinationKey: String,
        legacyKeyToRemove: String?,
        allowsNone: Bool
    ) -> VoiceInkRecordingShortcutSelectionMigrationPlan {
        if rawValue == VoiceInkRecordingShortcutSelection.custom.rawValue {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        if rawValue == VoiceInkRecordingShortcutSelection.none.rawValue {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: allowsNone ? .none : .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        if let preset = VoiceInkLegacyRecordingShortcutPreset(rawValue: rawValue) {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: preset,
                defaultPresetToStore: nil
            )
        }

        return VoiceInkRecordingShortcutSelectionMigrationPlan(
            selection: allowsNone ? .none : .custom,
            destinationKey: destinationKey,
            legacyKeyToRemove: legacyKeyToRemove,
            presetToStore: nil,
            defaultPresetToStore: nil
        )
    }

    private static func nonEmptyString(
        forKey key: String,
        from defaults: UserDefaults
    ) -> String? {
        guard
            let value = defaults.string(forKey: key),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }
}

public enum VoiceInkSharedPreferenceReset {
    public static func clearCoreUserSettings(
        from defaults: UserDefaults = .standard,
        providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders
    ) {
        VoiceInkModeStorage.clear(from: defaults)
        VoiceInkOnboardingPreference.clear(from: defaults)
        VoiceInkProviderAPIKeyVerificationState.clearAll(from: providers, in: defaults)
        VoiceInkAudioSessionTimeoutPreference.clear(from: defaults)
        VoiceInkVADPreference.clear(from: defaults)
        VoiceInkTranscriptionPromptPreference.clearPrompt(from: defaults)
        PunctuationCleanupMode.clearCurrent(in: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)
        VoiceInkFillerWordPreference.clearWords(from: defaults)
        VoiceInkWordReplacementPreference.clearRules(from: defaults)
        VoiceInkCustomVocabularyPreference.clearTerms(from: defaults)
        VoiceInkDictionaryListSortPreference.clear(from: defaults)
        VoiceInkTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)
        VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)
        VoiceInkAIEnhancementProviderPreference.clear(from: defaults)
        VoiceInkDynamicAIProviderPreference.clear(from: defaults)
        VoiceInkLocalCLIPreference.clear(from: defaults)
        VoiceInkAIEnhancementRequestPreference.clear(from: defaults)
        VoiceInkTranscriptionAutoCleanupPreference.clear(from: defaults)
        VoiceInkAudioCleanupPreference.clear(from: defaults)
        VoiceInkAudioPlaybackRate.clear(from: defaults)
        VoiceInkCustomPromptStorage.clear(from: defaults)
        VoiceInkAIEnhancementContextPreference.clear(from: defaults)
        VoiceInkPowerModePreference.clear(from: defaults)
        VoiceInkPowerModeConfigurationPreference.clear(from: defaults)
        VoiceInkPowerModeSessionPreference.clear(from: defaults)
        VoiceInkModelRuntimePreference.clear(from: defaults)
        VoiceInkRecorderPreviewPreference.clear(from: defaults)
        VoiceInkRecordingShortcutPreference.clear(from: defaults)
        VoiceInkAudioInputPreference.clearLastUsedMicrophoneDeviceID(from: defaults)
    }
}

public enum VoiceInkModeStorage {
    public static func saveModes(
        _ modes: [Mode],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(modes) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.modes)
        }
    }

    public static func loadModes(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [Mode] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.modes),
              let modes = try? decoder.decode([Mode].self, from: data) else {
            return []
        }

        return modes.map { mode in
            var repairedMode = mode
            repairedMode.repairModelSelection()
            return repairedMode
        }
    }

    public static func saveSelectedModeId(_ selectedModeId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedModeId {
            defaults.set(selectedModeId.uuidString, forKey: VoiceInkUserDefaultsKey.selectedModeId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedModeId)
        }
    }

    public static func loadSelectedModeId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedModeId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.modes)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedModeId)
    }
}

public enum VoiceInkPowerModeConfigurationPreference {
    public static func saveConfigurations(
        _ configurations: [PowerModeConfig],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(configurations) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.powerModeConfigurations)
        }
    }

    public static func loadConfigurations(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [PowerModeConfig] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations),
              let configurations = try? decoder.decode([PowerModeConfig].self, from: data) else {
            return []
        }

        return configurations
    }

    public static func saveActiveConfigurationId(
        _ id: UUID?,
        to defaults: UserDefaults = .standard
    ) {
        if let id {
            defaults.set(id.uuidString, forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
        }
    }

    public static func loadActiveConfigurationId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
    }
}

public enum VoiceInkPowerModePreference {
    public static var registeredDefaults: [String: Any] {
        [
            VoiceInkUserDefaultsKey.powerModePersistConfig: VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences
        ]
    }

    public static func isUIEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag) != nil else {
            return VoiceInkPreferenceDefault.powerModeUIEnabled
        }

        return defaults.bool(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag)
    }

    public static func saveIsUIEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.powerModeUIFlag)
    }

    public static func initializeUIFlagIfNeeded(
        hasEnabledConfigurations: Bool,
        in defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag) == nil else {
            return
        }

        saveIsUIEnabled(hasEnabledConfigurations, to: defaults)
    }

    public static func shouldPersistConfiguredPreferences(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: VoiceInkUserDefaultsKey.powerModePersistConfig) != nil else {
            return VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences
        }

        return defaults.bool(forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
    }

    public static func saveShouldPersistConfiguredPreferences(
        _ shouldPersist: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPersist, forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
    }

    public static func canUseShortcuts(
        hasEnabledConfigurations: Bool,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        isUIEnabled(from: defaults) && hasEnabledConfigurations
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
    }
}

public enum VoiceInkPowerModeSessionPreference {
    public static func saveActiveSession(
        _ session: VoiceInkPowerModeSession,
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(session)
        defaults.set(data, forKey: VoiceInkUserDefaultsKey.activePowerModeSession)
    }

    public static func loadActiveSession(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> VoiceInkPowerModeSession? {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.activePowerModeSession) else {
            return nil
        }

        return try decoder.decode(VoiceInkPowerModeSession.self, from: data)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.activePowerModeSession)
    }
}

public enum VoiceInkCustomPromptStorage {
    public static func savePrompts(
        _ prompts: [VoiceInkCustomPrompt],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(prompts) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.customPrompts)
        }
    }

    public static func loadPrompts(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [VoiceInkCustomPrompt] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.customPrompts),
              let prompts = try? decoder.decode([VoiceInkCustomPrompt].self, from: data) else {
            return []
        }

        return prompts
    }

    public static func saveSelectedPromptId(_ selectedPromptId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedPromptId {
            defaults.set(selectedPromptId.uuidString, forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        }
    }

    public static func loadSelectedPromptId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedPromptId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
    }
}

public enum VoiceInkProviderAPIKeyVerificationState {
    public static func verifiedProviders(
        from providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) -> Set<VoiceInkProviderKind> {
        Set(providers.filter { isVerified($0, in: defaults) })
    }

    public static func isVerified(
        _ provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = provider.apiKeyVerificationStateKey else {
            return false
        }

        return defaults.bool(forKey: key)
    }

    public static func setVerified(
        _ verified: Bool,
        for provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.set(verified, forKey: key)
    }

    public static func clear(
        for provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func clearAll(
        from providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) {
        providers.forEach { clear(for: $0, in: defaults) }
    }
}
