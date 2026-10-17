import Foundation

public enum RomaUserDefaultsKey {
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
    public static let legacyIsMenuBarOnly = "IsMenuBarOnly"
    public static let didApplyLaunchAtLoginDefault = "DidApplyLaunchAtLoginDefault"

    public static func selectedAIProviderModel(_ providerRawValue: String) -> String {
        "\(providerRawValue)SelectedModel"
    }
}

public enum RomaPreferenceDefault {
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
    public static let showDockIcon = false
    public static let didApplyLaunchAtLoginDefault = false
}

public enum RomaSystemMuteMode: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case always = "always"
    case never = "never"

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .automatic:
            return "Auto"
        case .always:
            return "On"
        case .never:
            return "Off"
        }
    }
}

public struct RomaRecordingFeedbackDelayOption: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: TimeInterval

    public var id: TimeInterval { value }

    public init(label: String, value: TimeInterval) {
        self.label = label
        self.value = value
    }
}

public struct RomaMacOSRecordingFeedbackSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let soundFeedbackLabel: String
    public let systemMuteModeLabel: String
    public let audioResumptionDelayLabel: String
    public let audioResumptionDelayOptions: [RomaRecordingFeedbackDelayOption]
    public let experimentalSectionTitle: String
    public let pauseMediaLabel: String
    public let pauseMediaInfoMessage: String
    public let pauseMediaResumeDelayLabel: String

    public init(
        sectionTitle: String,
        soundFeedbackLabel: String,
        systemMuteModeLabel: String,
        audioResumptionDelayLabel: String,
        audioResumptionDelayOptions: [RomaRecordingFeedbackDelayOption],
        experimentalSectionTitle: String,
        pauseMediaLabel: String,
        pauseMediaInfoMessage: String,
        pauseMediaResumeDelayLabel: String
    ) {
        self.sectionTitle = sectionTitle
        self.soundFeedbackLabel = soundFeedbackLabel
        self.systemMuteModeLabel = systemMuteModeLabel
        self.audioResumptionDelayLabel = audioResumptionDelayLabel
        self.audioResumptionDelayOptions = audioResumptionDelayOptions
        self.experimentalSectionTitle = experimentalSectionTitle
        self.pauseMediaLabel = pauseMediaLabel
        self.pauseMediaInfoMessage = pauseMediaInfoMessage
        self.pauseMediaResumeDelayLabel = pauseMediaResumeDelayLabel
    }
}

public struct RomaRecordingFeedbackBackupPreferences: Codable, Equatable, Sendable {
    public let isSoundFeedbackEnabled: Bool?
    public let isSystemMuteEnabled: Bool?
    public let isPauseMediaEnabled: Bool?
    public let audioResumptionDelay: Double?
    public let isExperimentalFeaturesEnabled: Bool?

    public init(
        isSoundFeedbackEnabled: Bool?,
        isSystemMuteEnabled: Bool?,
        isPauseMediaEnabled: Bool?,
        audioResumptionDelay: Double?,
        isExperimentalFeaturesEnabled: Bool? = nil
    ) {
        self.isSoundFeedbackEnabled = isSoundFeedbackEnabled
        self.isSystemMuteEnabled = isSystemMuteEnabled
        self.isPauseMediaEnabled = isPauseMediaEnabled
        self.audioResumptionDelay = audioResumptionDelay
        self.isExperimentalFeaturesEnabled = isExperimentalFeaturesEnabled
    }
}

public struct RomaRecordingFeedbackBackupImportPlan: Equatable, Sendable {
    private let isSoundFeedbackEnabled: Bool?
    private let systemMuteMode: RomaSystemMuteMode?
    private let isPauseMediaEnabled: Bool?
    private let audioResumptionDelay: Double?
    private let isExperimentalFeaturesEnabled: Bool?

    public var shouldDisablePauseMediaForExperimentalImport: Bool {
        isExperimentalFeaturesEnabled == false
    }

    public init(
        isSoundFeedbackEnabled: Bool?,
        systemMuteMode: RomaSystemMuteMode?,
        isPauseMediaEnabled: Bool?,
        audioResumptionDelay: Double?,
        isExperimentalFeaturesEnabled: Bool? = nil
    ) {
        self.isSoundFeedbackEnabled = isSoundFeedbackEnabled
        self.systemMuteMode = systemMuteMode
        self.isPauseMediaEnabled = isPauseMediaEnabled
        self.audioResumptionDelay = audioResumptionDelay
        self.isExperimentalFeaturesEnabled = isExperimentalFeaturesEnabled
    }

    public func applyRuntimeState(
        setSoundFeedbackEnabled: (Bool) -> Void,
        setSystemMuteMode: (RomaSystemMuteMode) -> Void,
        setPauseMediaEnabled: (Bool) -> Void,
        setAudioResumptionDelay: (Double) -> Void,
        disablePauseMediaForExperimentalImport: () -> Void
    ) {
        if let isSoundFeedbackEnabled {
            setSoundFeedbackEnabled(isSoundFeedbackEnabled)
        }
        if let systemMuteMode {
            setSystemMuteMode(systemMuteMode)
        }
        if let isPauseMediaEnabled {
            setPauseMediaEnabled(isPauseMediaEnabled)
        }
        if let audioResumptionDelay {
            setAudioResumptionDelay(audioResumptionDelay)
        }
        if shouldDisablePauseMediaForExperimentalImport {
            disablePauseMediaForExperimentalImport()
        }
    }

    public func applyCorePreferenceState(
        setExperimentalFeaturesEnabled: (Bool) -> Void
    ) {
        if let isExperimentalFeaturesEnabled {
            setExperimentalFeaturesEnabled(isExperimentalFeaturesEnabled)
        }
    }
}

public enum RomaBuiltInRecordingSound: String, CaseIterable, Identifiable, Sendable {
    case sound1
    case sound2
    case sound3
    case sound4
    case sound5
    case sound6
    case sound7

    public var id: String { rawValue }

    public var displayName: String {
        "Sound \(number)"
    }

    public var fileExtension: String {
        switch self {
        case .sound1, .sound2, .sound3, .sound4, .sound7:
            return "wav"
        case .sound5, .sound6:
            return "mp3"
        }
    }

    private var number: Int {
        Int(rawValue.replacingOccurrences(of: "sound", with: "")) ?? 0
    }
}

public enum RomaCustomSoundType: String, CaseIterable, Sendable {
    case start
    case stop

    public var displayName: String {
        switch self {
        case .start:
            return "Start"
        case .stop:
            return "Stop"
        }
    }

    public var isUsingKey: String {
        "isUsingCustom\(capitalizedRawValue)Sound"
    }

    public var filenameKey: String {
        "custom\(capitalizedRawValue)SoundFilename"
    }

    public var builtInSoundKey: String {
        "selected\(capitalizedRawValue)BuiltInSound"
    }

    public var standardName: String {
        "Custom\(capitalizedRawValue)Sound"
    }

    public var defaultBuiltInSound: RomaBuiltInRecordingSound {
        switch self {
        case .start:
            return .sound1
        case .stop:
            return .sound2
        }
    }

    public var recordingSoundCue: RomaRecordingSoundCue {
        switch self {
        case .start:
            return .start
        case .stop:
            return .stop
        }
    }

    private var capitalizedRawValue: String {
        rawValue.capitalized
    }
}

public enum RomaCustomSoundMenuSelection: Hashable, Sendable {
    case builtIn(RomaBuiltInRecordingSound)
    case custom
}

public struct RomaCustomSoundSelectionState: Equatable, Sendable {
    public let type: RomaCustomSoundType
    public let isUsingCustomSound: Bool
    public let selectedBuiltInSound: RomaBuiltInRecordingSound
    public let customFilename: String?

    public init(
        type: RomaCustomSoundType,
        isUsingCustomSound: Bool,
        selectedBuiltInSound: RomaBuiltInRecordingSound,
        customFilename: String?
    ) {
        self.type = type
        self.isUsingCustomSound = isUsingCustomSound
        self.selectedBuiltInSound = selectedBuiltInSound
        self.customFilename = customFilename
    }

    public var menuSelection: RomaCustomSoundMenuSelection {
        isUsingCustomSound ? .custom : .builtIn(selectedBuiltInSound)
    }

    public var isDefaultSelection: Bool {
        RomaCustomSoundPreference.isDefaultSelection(
            for: type,
            isUsingCustomSound: isUsingCustomSound,
            selectedBuiltInSound: selectedBuiltInSound
        )
    }

    public func customSoundURL(in customSoundsDirectory: URL?) -> URL? {
        RomaCustomSoundPreference.customSoundURL(
            isUsingCustomSound: isUsingCustomSound,
            filename: customFilename,
            in: customSoundsDirectory
        )
    }

    public func storedCustomSoundURL(in customSoundsDirectory: URL?) -> URL? {
        RomaCustomSoundPreference.storedCustomSoundURL(
            filename: customFilename,
            in: customSoundsDirectory
        )
    }

    public func selectingBuiltInSound(
        _ sound: RomaBuiltInRecordingSound
    ) -> RomaCustomSoundSelectionState {
        RomaCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: false,
            selectedBuiltInSound: sound,
            customFilename: customFilename
        )
    }

    public func usingExistingCustomSound() -> RomaCustomSoundSelectionState? {
        guard customFilename != nil else { return nil }
        return RomaCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: true,
            selectedBuiltInSound: selectedBuiltInSound,
            customFilename: customFilename
        )
    }

    public func settingCustomFilename(_ filename: String) -> RomaCustomSoundSelectionState {
        RomaCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: true,
            selectedBuiltInSound: selectedBuiltInSound,
            customFilename: filename
        )
    }

    public func resettingToDefault() -> RomaCustomSoundSelectionState {
        RomaCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: false,
            selectedBuiltInSound: type.defaultBuiltInSound,
            customFilename: nil
        )
    }
}

public enum RomaCustomSoundSettingsPresentation {
    public static let pickerTitle = "Sound"
    public static let customFallbackTitle = "Custom"
    public static let selectSoundHelpText = "Select sound"
    public static let testButtonHelpText = "Test"
    public static let chooseButtonHelpText = "Choose"
    public static let resetButtonHelpText = "Reset"
    public static let testButtonSystemImageName = "play.fill"
    public static let chooseButtonSystemImageName = "folder"
    public static let resetButtonSystemImageName = "arrow.uturn.backward"
    public static let openPanelMessage = "Select an audio file"
    public static let invalidAudioAlertTitle = "Invalid Audio File"
    public static let alertDismissButtonTitle = "OK"

    public static func label(for type: RomaCustomSoundType) -> String {
        "\(type.displayName) Sound"
    }

    public static func customMenuTitle(filename: String?) -> String {
        "Custom: \(filename ?? customFallbackTitle)"
    }

    public static func openPanelTitle(for type: RomaCustomSoundType) -> String {
        "Choose \(type.displayName) Sound"
    }
}

public enum RomaRecordingSoundCue: CaseIterable, Sendable {
    case start
    case stop
    case esc
}

public enum RomaRecordingSoundPlayerSlot: CaseIterable, Hashable, Sendable {
    case defaultStart
    case defaultStop
    case defaultEsc
    case customStart
    case customStop

    public var volume: Float {
        switch self {
        case .defaultStart, .defaultStop, .customStart, .customStop:
            return 0.4
        case .defaultEsc:
            return 0.3
        }
    }
}

public enum RomaRecordingSoundPlaybackPolicy {
    public static let setupSlots: [RomaRecordingSoundPlayerSlot] = [
        .defaultStart,
        .defaultStop,
        .defaultEsc,
        .customStart,
        .customStop
    ]

    public static func playbackSlots(
        for cue: RomaRecordingSoundCue
    ) -> [RomaRecordingSoundPlayerSlot] {
        switch cue {
        case .start:
            return [.customStart, .defaultStart]
        case .stop:
            return [.customStop, .defaultStop]
        case .esc:
            return [.defaultEsc]
        }
    }
}

public enum RomaRecordingSoundPlaybackDiagnostics {
    public static func loadFailedMessage(localizedDescription: String) -> String {
        "Failed to load sound: \(localizedDescription)"
    }
}

public enum RomaCustomSoundError: LocalizedError, Equatable, Sendable {
    case fileNotFound
    case invalidAudioFile
    case durationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case directoryCreationFailed
    case fileCopyFailed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .durationTooLong(let duration, let maxDuration):
            return String(
                format: "Audio file is %.1f seconds long. Please use an audio file that is %.0f seconds or shorter for start and stop sounds.",
                duration,
                maxDuration
            )
        case .directoryCreationFailed:
            return "Failed to create custom sounds directory"
        case .fileCopyFailed:
            return "Failed to copy audio file"
        }
    }
}

fileprivate enum RomaCustomSoundCopyAction: Equatable, Sendable {
    case useExistingDestination
    case copy
    case replaceExistingDestinationAndCopy
}

public struct RomaCustomSoundCopyPlan: Equatable, Sendable {
    public let filename: String
    public let destinationURL: URL
    private let action: RomaCustomSoundCopyAction

    fileprivate init(
        filename: String,
        destinationURL: URL,
        action: RomaCustomSoundCopyAction
    ) {
        self.filename = filename
        self.destinationURL = destinationURL
        self.action = action
    }

    public func applyRuntimeState(
        removeExistingDestination: (URL) throws -> Void,
        copyToDestination: (URL) throws -> Void
    ) -> Result<String, RomaCustomSoundError> {
        switch action {
        case .useExistingDestination:
            return .success(filename)
        case .replaceExistingDestinationAndCopy:
            try? removeExistingDestination(destinationURL)
        case .copy:
            break
        }

        do {
            try copyToDestination(destinationURL)
            return .success(filename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }
}

public enum RomaCustomSoundPreference {
    public static let customSoundsRelativeDirectory = "VoiceInk/CustomSounds"
    public static let changedNotificationName = "CustomSoundsChanged"
    public static let maxDuration: TimeInterval = 3.0

    public static var registeredDefaults: [String: Any] {
        [
            RomaCustomSoundType.start.builtInSoundKey: RomaCustomSoundType.start.defaultBuiltInSound.rawValue,
            RomaCustomSoundType.stop.builtInSoundKey: RomaCustomSoundType.stop.defaultBuiltInSound.rawValue
        ]
    }

    public static func selectionState(
        for type: RomaCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> RomaCustomSoundSelectionState {
        RomaCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: isUsingCustomSound(for: type, from: defaults),
            selectedBuiltInSound: selectedBuiltInSound(for: type, from: defaults),
            customFilename: customFilename(for: type, from: defaults)
        )
    }

    public static func isUsingCustomSound(
        for type: RomaCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: type.isUsingKey)
    }

    public static func saveIsUsingCustomSound(
        _ isUsingCustomSound: Bool,
        for type: RomaCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isUsingCustomSound, forKey: type.isUsingKey)
    }

    public static func customFilename(
        for type: RomaCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: type.filenameKey)
    }

    public static func saveCustomFilename(
        _ filename: String?,
        for type: RomaCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        if let filename {
            defaults.set(filename, forKey: type.filenameKey)
        } else {
            defaults.removeObject(forKey: type.filenameKey)
        }
    }

    public static func selectedBuiltInSound(
        for type: RomaCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> RomaBuiltInRecordingSound {
        if let rawValue = defaults.string(forKey: type.builtInSoundKey),
           let sound = RomaBuiltInRecordingSound(rawValue: rawValue) {
            return sound
        }

        return type.defaultBuiltInSound
    }

    public static func saveSelectedBuiltInSound(
        _ sound: RomaBuiltInRecordingSound,
        for type: RomaCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(sound.rawValue, forKey: type.builtInSoundKey)
    }

    public static func isDefaultSelection(
        for type: RomaCustomSoundType,
        isUsingCustomSound: Bool,
        selectedBuiltInSound: RomaBuiltInRecordingSound
    ) -> Bool {
        !isUsingCustomSound && selectedBuiltInSound == type.defaultBuiltInSound
    }

    public static func copiedFilename(
        sourceExtension: String,
        for type: RomaCustomSoundType
    ) -> String {
        "\(type.standardName).\(sourceExtension)"
    }

    public static func customSoundURL(
        isUsingCustomSound: Bool,
        filename: String?,
        in customSoundsDirectory: URL?
    ) -> URL? {
        guard isUsingCustomSound else { return nil }
        return storedCustomSoundURL(filename: filename, in: customSoundsDirectory)
    }

    public static func storedCustomSoundURL(
        filename: String?,
        in customSoundsDirectory: URL?
    ) -> URL? {
        guard let filename, let customSoundsDirectory else { return nil }
        return customSoundsDirectory.appendingPathComponent(filename)
    }

    public static func copyPlan(
        sourceURL: URL,
        customSoundsDirectory: URL,
        for type: RomaCustomSoundType,
        fileManager: FileManager = .default
    ) -> RomaCustomSoundCopyPlan {
        let filename = copiedFilename(sourceExtension: sourceURL.pathExtension, for: type)
        let destinationURL = customSoundsDirectory.appendingPathComponent(filename)

        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return RomaCustomSoundCopyPlan(
                filename: filename,
                destinationURL: destinationURL,
                action: .useExistingDestination
            )
        }

        return RomaCustomSoundCopyPlan(
            filename: filename,
            destinationURL: destinationURL,
            action: fileManager.fileExists(atPath: destinationURL.path) ? .replaceExistingDestinationAndCopy : .copy
        )
    }

    public static func preflightValidationError(
        fileExists: Bool,
        duration: TimeInterval
    ) -> RomaCustomSoundError? {
        guard fileExists else { return .fileNotFound }
        guard duration.isFinite && duration > 0 else { return .invalidAudioFile }

        if duration > maxDuration {
            return .durationTooLong(duration: duration, maxDuration: maxDuration)
        }

        return nil
    }
}

public enum RomaRecordingFeedbackPreference {
    public static let systemMuteModeKey = "systemMuteMode"
    public static let legacyIsSystemMuteEnabledKey = "isSystemMuteEnabled"
    public static let audioResumptionDelayKey = "audioResumptionDelay"
    public static let isPauseMediaEnabledKey = "isPauseMediaEnabled"
    public static let isSoundFeedbackEnabledKey = "isSoundFeedbackEnabled"
    public static let experimentalFeaturesEnabledKey = "isExperimentalFeaturesEnabled"

    public static let defaultSystemMuteMode = RomaSystemMuteMode.automatic
    public static let defaultAudioResumptionDelay: TimeInterval = 0.0
    public static let defaultSystemMuteScheduleDelayNanoseconds: UInt64 = 250_000_000
    public static let defaultPauseMediaCommandDelayNanoseconds: UInt64 = 50_000_000
    public static let defaultIsPauseMediaEnabled = false
    public static let defaultIsSoundFeedbackEnabled = false

    public static var registeredDefaults: [String: Any] {
        [
            systemMuteModeKey: defaultSystemMuteMode.rawValue,
            legacyIsSystemMuteEnabledKey: true,
            audioResumptionDelayKey: defaultAudioResumptionDelay,
            isPauseMediaEnabledKey: defaultIsPauseMediaEnabled,
            isSoundFeedbackEnabledKey: defaultIsSoundFeedbackEnabled
        ]
    }

    public static let macOSSettingsPresentation = RomaMacOSRecordingFeedbackSettingsPresentation(
        sectionTitle: "Recording Feedback",
        soundFeedbackLabel: "Sound Feedback",
        systemMuteModeLabel: "Mute Audio While Recording",
        audioResumptionDelayLabel: "Audio Resume Delay",
        audioResumptionDelayOptions: [
            RomaRecordingFeedbackDelayOption(label: "0s", value: 0.0),
            RomaRecordingFeedbackDelayOption(label: "1s", value: 1.0),
            RomaRecordingFeedbackDelayOption(label: "2s", value: 2.0),
            RomaRecordingFeedbackDelayOption(label: "3s", value: 3.0),
            RomaRecordingFeedbackDelayOption(label: "4s", value: 4.0),
            RomaRecordingFeedbackDelayOption(label: "5s", value: 5.0)
        ],
        experimentalSectionTitle: "Experimental",
        pauseMediaLabel: "Pause Media While Recording",
        pauseMediaInfoMessage: "Pauses playing media when recording starts and resumes when done.",
        pauseMediaResumeDelayLabel: "Resume Delay"
    )

    public static func systemMuteMode(from defaults: UserDefaults = .standard) -> RomaSystemMuteMode {
        if let rawValue = defaults.string(forKey: systemMuteModeKey),
           let mode = RomaSystemMuteMode(rawValue: rawValue) {
            return mode
        }

        if let legacyEnabled = defaults.object(forKey: legacyIsSystemMuteEnabledKey) as? Bool,
           legacyEnabled == false {
            return .never
        }

        return defaultSystemMuteMode
    }

    public static func saveSystemMuteMode(
        _ mode: RomaSystemMuteMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: systemMuteModeKey)
        defaults.set(mode != .never, forKey: legacyIsSystemMuteEnabledKey)
    }

    public static func isSystemMuteEnabled(from defaults: UserDefaults = .standard) -> Bool {
        systemMuteMode(from: defaults) != .never
    }

    public static func saveSystemMuteEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        saveSystemMuteMode(isEnabled ? .always : .never, to: defaults)
    }

    public static func audioResumptionDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: audioResumptionDelayKey) != nil else {
            return defaultAudioResumptionDelay
        }

        return defaults.double(forKey: audioResumptionDelayKey)
    }

    public static func saveAudioResumptionDelay(
        _ delay: TimeInterval,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(delay, forKey: audioResumptionDelayKey)
    }

    public static func isPauseMediaEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isPauseMediaEnabledKey) != nil else {
            return defaultIsPauseMediaEnabled
        }

        return defaults.bool(forKey: isPauseMediaEnabledKey)
    }

    public static func savePauseMediaEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: isPauseMediaEnabledKey)
    }

    public static func isSoundFeedbackEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isSoundFeedbackEnabledKey) != nil else {
            return defaultIsSoundFeedbackEnabled
        }

        return defaults.bool(forKey: isSoundFeedbackEnabledKey)
    }

    public static func saveSoundFeedbackEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: isSoundFeedbackEnabledKey)
    }

    public static func isExperimentalFeaturesEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: experimentalFeaturesEnabledKey)
    }

    public static func saveExperimentalFeaturesEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: experimentalFeaturesEnabledKey)
    }

    public static func backupPreferences(
        isSoundFeedbackEnabled: Bool,
        isSystemMuteEnabled: Bool,
        isPauseMediaEnabled: Bool,
        audioResumptionDelay: Double,
        isExperimentalFeaturesEnabled: Bool
    ) -> RomaRecordingFeedbackBackupPreferences {
        RomaRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    public static func backupImportPlan(
        from preferences: RomaRecordingFeedbackBackupPreferences
    ) -> RomaRecordingFeedbackBackupImportPlan {
        RomaRecordingFeedbackBackupImportPlan(
            isSoundFeedbackEnabled: preferences.isSoundFeedbackEnabled,
            systemMuteMode: preferences.isSystemMuteEnabled.map { $0 ? .always : .never },
            isPauseMediaEnabled: preferences.isPauseMediaEnabled,
            audioResumptionDelay: preferences.audioResumptionDelay,
            isExperimentalFeaturesEnabled: preferences.isExperimentalFeaturesEnabled
        )
    }
}

public enum RomaPasteMethod: String, CaseIterable, Identifiable, Sendable {
    case standard = "default"
    case appleScript = "appleScript"

    public static let userDefaultsKey = "pasteMethod"
    public static let legacyAppleScriptPasteKey = "useAppleScriptPaste"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard:
            return "Default"
        case .appleScript:
            return "AppleScript"
        }
    }

    public static func current(in defaults: UserDefaults = .standard) -> RomaPasteMethod {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let method = RomaPasteMethod(rawValue: rawValue) {
            return method
        }

        return defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard
    }

    public static func selection(
        fromStoredRawValue storedRawValue: String?,
        in defaults: UserDefaults = .standard
    ) -> RomaPasteMethod {
        if let storedRawValue, let method = RomaPasteMethod(rawValue: storedRawValue) {
            return method
        }

        return current(in: defaults)
    }

    public static func setCurrent(_ method: RomaPasteMethod, in defaults: UserDefaults = .standard) {
        defaults.set(method.rawValue, forKey: userDefaultsKey)
        defaults.set(method == .appleScript, forKey: legacyAppleScriptPasteKey)
    }

    public static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           RomaPasteMethod(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard, in: defaults)
    }
}

public struct RomaPasteDelayOption: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: TimeInterval

    public var id: TimeInterval { value }

    public init(label: String, value: TimeInterval) {
        self.label = label
        self.value = value
    }
}

public struct RomaMacOSPasteSettingsPresentation: Equatable, Sendable {
    public let keepClipboardContentLabel: String
    public let keepClipboardContentInfoMessage: String
    public let restoreDelayLabel: String
    public let restoreDelayOptions: [RomaPasteDelayOption]
    public let pasteMethodLabel: String
    public let pasteMethodHelpMessage: String

    public init(
        keepClipboardContentLabel: String,
        keepClipboardContentInfoMessage: String,
        restoreDelayLabel: String,
        restoreDelayOptions: [RomaPasteDelayOption],
        pasteMethodLabel: String,
        pasteMethodHelpMessage: String
    ) {
        self.keepClipboardContentLabel = keepClipboardContentLabel
        self.keepClipboardContentInfoMessage = keepClipboardContentInfoMessage
        self.restoreDelayLabel = restoreDelayLabel
        self.restoreDelayOptions = restoreDelayOptions
        self.pasteMethodLabel = pasteMethodLabel
        self.pasteMethodHelpMessage = pasteMethodHelpMessage
    }
}

public struct RomaPasteBackupPreferences: Codable, Equatable, Sendable {
    public let shouldRestoreClipboardAfterPaste: Bool?
    public let clipboardRestoreDelay: Double?

    public init(
        shouldRestoreClipboardAfterPaste: Bool?,
        clipboardRestoreDelay: Double?
    ) {
        self.shouldRestoreClipboardAfterPaste = shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }
}

public struct RomaPasteBackupImportPlan: Equatable, Sendable {
    public let shouldRestoreClipboardAfterPaste: Bool?
    public let clipboardRestoreDelay: Double?

    public init(
        shouldRestoreClipboardAfterPaste: Bool?,
        clipboardRestoreDelay: Double?
    ) {
        self.shouldRestoreClipboardAfterPaste = shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }
}

public enum RomaPastePreference {
    public static let restoreClipboardAfterPasteKey = "restoreClipboardAfterPaste"
    public static let clipboardRestoreDelayKey = "clipboardRestoreDelay"
    public static let defaultRestoreClipboardAfterPaste = true
    public static let defaultClipboardRestoreDelay: TimeInterval = 2.0
    public static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    public static var registeredDefaults: [String: Any] {
        [
            restoreClipboardAfterPasteKey: defaultRestoreClipboardAfterPaste,
            clipboardRestoreDelayKey: defaultClipboardRestoreDelay,
            RomaPasteMethod.legacyAppleScriptPasteKey: false
        ]
    }

    public static let macOSSettingsPresentation = RomaMacOSPasteSettingsPresentation(
        keepClipboardContentLabel: "Keep Clipboard Content",
        keepClipboardContentInfoMessage: "Roma Just Talk temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard.",
        restoreDelayLabel: "Restore Delay",
        restoreDelayOptions: [
            RomaPasteDelayOption(label: "250ms", value: 0.25),
            RomaPasteDelayOption(label: "500ms", value: 0.5),
            RomaPasteDelayOption(label: "1s", value: 1.0),
            RomaPasteDelayOption(label: "2s", value: 2.0),
            RomaPasteDelayOption(label: "3s", value: 3.0),
            RomaPasteDelayOption(label: "4s", value: 4.0),
            RomaPasteDelayOption(label: "5s", value: 5.0)
        ],
        pasteMethodLabel: "Paste Method",
        pasteMethodHelpMessage: "Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly."
    )

    public static func shouldRestoreClipboardAfterPaste(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: restoreClipboardAfterPasteKey)
    }

    public static func clipboardRestoreDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        defaults.double(forKey: clipboardRestoreDelayKey)
    }

    public static func boundedClipboardRestoreDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        max(clipboardRestoreDelay(from: defaults), minimumClipboardRestoreDelay)
    }

    public static func saveShouldRestoreClipboardAfterPaste(
        _ value: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: restoreClipboardAfterPasteKey)
    }

    public static func saveClipboardRestoreDelay(
        _ value: TimeInterval,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: clipboardRestoreDelayKey)
    }

    public static func backupPreferences(
        shouldRestoreClipboardAfterPaste: Bool,
        clipboardRestoreDelay: Double
    ) -> RomaPasteBackupPreferences {
        RomaPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    public static func backupImportPlan(
        from preferences: RomaPasteBackupPreferences
    ) -> RomaPasteBackupImportPlan {
        RomaPasteBackupImportPlan(
            shouldRestoreClipboardAfterPaste: preferences.shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: preferences.clipboardRestoreDelay
        )
    }
}

public enum RomaPasteDiagnostics {
    public static let failedToPrepareClipboardMessage = "Failed to prepare clipboard for paste"
    public static let skippedClipboardRestoreCommandNotPostedMessage = "Skipping clipboard restore because paste command was not posted"
    public static let appleScriptPasteScriptUnavailableMessage = "AppleScript paste script is unavailable"
    public static let accessibilityPermissionRequiredForSimulatedPasteMessage = "Accessibility permission is required to paste with simulated key events"
    public static let failedToCreateCommandVPasteEventsMessage = "Failed to create Cmd+V keyboard events"

    public static func appleScriptPasteFailedMessage(errorDescription: String) -> String {
        "AppleScript paste failed: \(errorDescription)"
    }
}

public struct RomaMacOSAppendTrailingSpaceSettingsPresentation: Equatable, Sendable {
    public let toggleTitle: String
    public let helpText: String

    public static let macOS = RomaMacOSAppendTrailingSpaceSettingsPresentation(
        toggleTitle: "Add Space After Paste",
        helpText: "Add a trailing space after pasted transcription output."
    )
}

public enum RomaAppendTrailingSpacePreference {
    public static let userDefaultsKey = RomaUserDefaultsKey.appendTrailingSpace
    public static let defaultIsEnabled = RomaPreferenceDefault.appendTrailingSpace
    public static let settingsPresentation = RomaMacOSAppendTrailingSpaceSettingsPresentation.macOS
    public static let macOSSettingsPresentation = settingsPresentation

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultIsEnabled
        ]
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum RomaContextualCapitalizationFormatter {
    public static func needsCursorContext(_ text: String) -> Bool {
        guard let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return false
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return false }

        return shouldUppercaseFirstCasedCharacter(in: firstWord) ||
            shouldLowercaseFirstCasedCharacter(in: firstWord)
    }

    public static func format(_ text: String, beforeCursor: String?) -> String {
        guard let beforeCursor,
              let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return text
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return text }

        switch boundary(beforeCursor) {
        case .sentenceStart:
            guard shouldUppercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).uppercased())
        case .midSentence:
            guard shouldLowercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).lowercased())
        }
    }

    private enum Boundary {
        case sentenceStart
        case midSentence
    }

    private static let sentenceTerminators = Set<Character>([".", "!", "?", "。", "！", "？"])
    private static let wordInternalCharacters = Set<Character>(["'", "’", "‘", "ʼ", "＇", "-"])

    private static func boundary(_ beforeCursor: String) -> Boundary {
        var index = beforeCursor.endIndex
        var sawTrailingNewline = false

        while index > beforeCursor.startIndex {
            let previousIndex = beforeCursor.index(before: index)
            let character = beforeCursor[previousIndex]

            if isWhitespace(character) {
                if containsNewline(character) {
                    sawTrailingNewline = true
                }
                index = previousIndex
                continue
            }

            if sawTrailingNewline || sentenceTerminators.contains(character) {
                return .sentenceStart
            }

            return .midSentence
        }

        return .sentenceStart
    }

    private static func firstCasedCharacterRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            if isCasedLetter(text[index]) {
                return index..<nextIndex
            }
            index = nextIndex
        }
        return nil
    }

    private static func word(in text: String, startingAt startIndex: String.Index) -> String {
        var index = startIndex
        var result = ""

        while index < text.endIndex {
            let character = text[index]
            guard isWordCharacter(character) else { break }
            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func shouldUppercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard let first = letters.first,
              isLowercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func shouldLowercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard letters.count > 1,
              let first = letters.first,
              isUppercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func casedLetters(in word: String) -> [Character] {
        word.filter { isCasedLetter($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        isCasedLetter(character) ||
            wordInternalCharacters.contains(character) ||
            character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isCasedLetter(_ character: Character) -> Bool {
        let value = String(character)
        return value.lowercased() != value.uppercased()
    }

    private static func isLowercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.lowercased() && value != value.uppercased()
    }

    private static func isUppercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.uppercased() && value != value.lowercased()
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func containsNewline(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    private static func replacing(_ text: String, range: Range<String.Index>, with replacement: String) -> String {
        var result = text
        result.replaceSubrange(range, with: replacement)
        return result
    }
}

public enum RomaTranscriptionPasteOutputPolicy {
    public struct PasteDecision: Equatable, Sendable {
        public let textToPaste: String?
        public let shouldPlayCompletionSoundWithoutPaste: Bool
    }

    public static func shouldPaste(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func decision(
        text: String?,
        transcriptionCompleted: Bool
    ) -> PasteDecision {
        guard transcriptionCompleted, let text else {
            return PasteDecision(
                textToPaste: nil,
                shouldPlayCompletionSoundWithoutPaste: false
            )
        }
        guard shouldPaste(text) else {
            return PasteDecision(
                textToPaste: nil,
                shouldPlayCompletionSoundWithoutPaste: true
            )
        }
        return PasteDecision(
            textToPaste: text,
            shouldPlayCompletionSoundWithoutPaste: false
        )
    }

    public struct CursorPasteTextPlan: Equatable, Sendable {
        public let text: String
        public let shouldReadCursorContext: Bool

        public init(text: String, shouldReadCursorContext: Bool) {
            self.text = text
            self.shouldReadCursorContext = shouldReadCursorContext
        }

        public func text(beforeCursor: String?) -> String {
            guard shouldReadCursorContext else { return text }
            return RomaContextualCapitalizationFormatter.format(
                text,
                beforeCursor: beforeCursor
            )
        }
    }

    public static func cursorPasteTextPlan(
        _ text: String,
        shouldLowercase: Bool
    ) -> CursorPasteTextPlan {
        CursorPasteTextPlan(
            text: text,
            shouldReadCursorContext: !shouldLowercase
                && RomaContextualCapitalizationFormatter.needsCursorContext(text)
        )
    }

    public static func cursorPasteTextPlan(
        _ text: String,
        from defaults: UserDefaults = .standard
    ) -> CursorPasteTextPlan {
        cursorPasteTextPlan(
            text,
            shouldLowercase: RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults)
        )
    }

    public static func finalPastedText(
        _ text: String,
        appendTrailingSpace: Bool
    ) -> String {
        text + (appendTrailingSpace ? " " : "")
    }
}

public enum RomaCursorTextContextPolicy {
    public static let defaultMaximumLength = 240
    public static let parentTraversalLimit = 4
    public static let textInputRoleNames: Set<String> = [
        "AXComboBox",
        "AXTextArea",
        "AXTextField"
    ]

    public static func shouldAttemptRead(maximumLength: Int = defaultMaximumLength) -> Bool {
        maximumLength > 0
    }

    public static func prefixLength(
        cursorLocation: Int,
        maximumLength: Int = defaultMaximumLength
    ) -> Int? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              cursorLocation >= 0 else {
            return nil
        }

        return min(maximumLength, cursorLocation)
    }

    public static func isTextInputRole(_ role: String?) -> Bool {
        guard let role else { return false }
        return textInputRoleNames.contains(role)
    }

    public static func valueSuffix(
        from text: String,
        role: String?,
        maximumLength: Int = defaultMaximumLength
    ) -> String? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              isTextInputRole(role) else {
            return nil
        }

        guard text.count > maximumLength else {
            return text
        }

        return String(text.suffix(maximumLength))
    }

    public static func boundedSuffix(
        _ text: String?,
        maximumLength: Int = defaultMaximumLength
    ) -> String? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              let text,
              !text.isEmpty else {
            return nil
        }

        return String(text.suffix(maximumLength))
    }
}

public enum RomaPreferenceList {
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

public struct RomaSettingsPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let modesSectionTitle: String
    public let addModeButtonTitle: String
    public let addActionSystemImageName: String

    public static let iOS = RomaSettingsPresentation(
        navigationTitle: "Settings",
        modesSectionTitle: "Modes",
        addModeButtonTitle: "Add New Mode",
        addActionSystemImageName: "plus.circle.fill"
    )
}

public struct RomaMacOSSettingsPresentation: Equatable, Sendable {
    public let generalSectionTitle: String
    public let menuBarTitle: String
    public let dockIconTitle: String
    public let showVisibilityValueTitle: String
    public let hideVisibilityValueTitle: String
    public let launchAtLoginTitle: String
    public let autoCheckUpdatesTitle: String
    public let checkForUpdatesButtonTitle: String
    public let privacySectionTitle: String
    public let privacyFooterText: String
    public let backupSectionTitle: String
    public let backupFooterText: String
    public let exportSettingsLabel: String
    public let exportButtonTitle: String
    public let importSettingsLabel: String
    public let importButtonTitle: String
    public let diagnosticsSectionTitle: String

    public static let macOS = RomaMacOSSettingsPresentation(
        generalSectionTitle: "General",
        menuBarTitle: "Menu Bar",
        dockIconTitle: "Dock Icon",
        showVisibilityValueTitle: "Show",
        hideVisibilityValueTitle: "Hide",
        launchAtLoginTitle: "Launch at Login",
        autoCheckUpdatesTitle: "Auto-check Updates",
        checkForUpdatesButtonTitle: "Check for Updates",
        privacySectionTitle: "Privacy",
        privacyFooterText: "Control how Roma Just Talk handles your transcription data and audio recordings.",
        backupSectionTitle: "Backup",
        backupFooterText: "Export all settings, or choose specific categories when importing a backup.",
        exportSettingsLabel: "Export Settings",
        exportButtonTitle: "Export",
        importSettingsLabel: "Import Settings",
        importButtonTitle: "Import",
        diagnosticsSectionTitle: "Diagnostics"
    )

    public func visibilityValueTitle(isVisible: Bool) -> String {
        isVisible ? showVisibilityValueTitle : hideVisibilityValueTitle
    }
}

public enum RomaSettingsBackupCategory: String, CaseIterable, Hashable, Sendable {
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

public enum RomaSettingsBackupImportPolicy {
    public static let fallbackVersion = "0.0.0"

    public static func currentVersion(bundleShortVersion: String?) -> String {
        bundleShortVersion ?? fallbackVersion
    }

    public static func categorySummary(for categories: Set<RomaSettingsBackupCategory>) -> String {
        if categories == Set(RomaSettingsBackupCategory.allCases) {
            return "All settings"
        }

        return RomaSettingsBackupCategory.allCases
            .filter { categories.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    public static func needsAPIKeyReminder(for categories: Set<RomaSettingsBackupCategory>) -> Bool {
        !categories.isDisjoint(with: [.prompts, .powerMode, .customModels])
    }

    public static func versionReview(
        importedVersion: String,
        currentVersion: String
    ) -> RomaSettingsBackupVersionReview {
        RomaSettingsBackupVersionReview(
            importedVersion: importedVersion,
            currentVersion: currentVersion
        )
    }

    public static func importSelectionReview(
        selectedCategories: Set<RomaSettingsBackupCategory>?
    ) -> RomaSettingsBackupImportSelectionReview {
        RomaSettingsBackupImportSelectionReview(
            selectedCategories: selectedCategories
        )
    }

    public static func importSuccessPlan(
        categories: Set<RomaSettingsBackupCategory>
    ) -> RomaSettingsBackupImportSuccessPlan {
        RomaSettingsBackupImportSuccessPlan(categories: categories)
    }
}

public struct RomaSettingsBackupVersionReview: Equatable, Sendable {
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

public enum RomaSettingsBackupImportSelectionReview: Equatable, Sendable {
    case canceled
    case emptySelection
    case selected(Set<RomaSettingsBackupCategory>)

    public init(selectedCategories: Set<RomaSettingsBackupCategory>?) {
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
        importSelectedCategories: (Set<RomaSettingsBackupCategory>) throws -> Void
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

public struct RomaSettingsBackupImportSuccessPlan: Equatable, Sendable {
    public let categories: Set<RomaSettingsBackupCategory>

    public var isConfigureAPIKeysActionVisible: Bool {
        RomaSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories)
    }

    public init(categories: Set<RomaSettingsBackupCategory>) {
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

public enum RomaSettingsBackupImportDiagnostics {
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

public enum RomaSettingsBackupImportError: LocalizedError, Sendable {
    case saveFailed(item: String, localizedDescription: String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let localizedDescription):
            RomaSettingsBackupImportDiagnostics.saveFailedDescription(
                item: item,
                localizedDescription: localizedDescription
            )
        }
    }
}

public struct RomaSettingsBackupFile<ShortcutBackup: Codable>: Codable {
    public let version: String
    public let customPrompts: [RomaCustomPrompt]
    public let powerModeConfigs: [PowerModeConfig]
    public let powerModeShortcuts: [String: ShortcutBackup]?
    public let vocabularyWords: [RomaVocabularyWordBackup]?
    public let wordReplacements: [String: String]?
    public let generalSettings: RomaGeneralSettingsBackupPayload<ShortcutBackup>?
    public let customEmojis: [String]?
    public let customCloudModels: [RomaCustomCloudModelBackup]?

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
        customPrompts: [RomaCustomPrompt],
        powerModeConfigs: [PowerModeConfig],
        powerModeShortcuts: [String: ShortcutBackup]?,
        vocabularyWords: [RomaVocabularyWordBackup]?,
        wordReplacements: [String: String]?,
        generalSettings: RomaGeneralSettingsBackupPayload<ShortcutBackup>?,
        customEmojis: [String]?,
        customCloudModels: [RomaCustomCloudModelBackup]?
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
        customPrompts = try container.decodeIfPresent([RomaCustomPrompt].self, forKey: .customPrompts) ?? []
        powerModeConfigs = try container.decodeIfPresent([PowerModeConfig].self, forKey: .powerModeConfigs) ?? []
        powerModeShortcuts = try container.decodeIfPresent([String: ShortcutBackup].self, forKey: .powerModeShortcuts)
        vocabularyWords = try container.decodeIfPresent([RomaVocabularyWordBackup].self, forKey: .vocabularyWords)
        wordReplacements = try container.decodeIfPresent([String: String].self, forKey: .wordReplacements)
        generalSettings = try container.decodeIfPresent(RomaGeneralSettingsBackupPayload<ShortcutBackup>.self, forKey: .generalSettings)
        customEmojis = try container.decodeIfPresent([String].self, forKey: .customEmojis)
        customCloudModels = try container.decodeIfPresent([RomaCustomCloudModelBackup].self, forKey: .customCloudModels)
    }
}

public enum RomaSettingsBackupFileCodec {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }

    public static func encode<ShortcutBackup: Codable>(
        _ backupFile: RomaSettingsBackupFile<ShortcutBackup>,
        encoder: JSONEncoder = makeEncoder()
    ) throws -> Data {
        try encoder.encode(backupFile)
    }

    public static func decode<ShortcutBackup: Codable>(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> RomaSettingsBackupFile<ShortcutBackup> {
        try decoder.decode(RomaSettingsBackupFile<ShortcutBackup>.self, from: data)
    }
}

public struct RomaGeneralSettingsBackupPayload<ShortcutBackup: Codable>: Codable {
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
    // Legacy backup wire field. Keep its inverted meaning so existing backup files round-trip.
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

    public init(
        shortcutBackupRecords: [RomaShortcutActionIdentifier: ShortcutBackup],
        preferences: RomaGeneralSettingsBackupPreferences
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
    }

    public var shortcutBackupRecords: [RomaShortcutActionIdentifier: ShortcutBackup] {
        var records: [RomaShortcutActionIdentifier: ShortcutBackup] = [:]
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

    public var generalSettingsBackupPreferences: RomaGeneralSettingsBackupPreferences {
        RomaGeneralSettingsBackupPolicy.backupPreferences(
            recordingShortcut: recordingShortcutBackupPreferences,
            macOSShell: macOSShellBackupPreferences,
            transcriptionAutoCleanup: transcriptionAutoCleanupBackupPreferences,
            audioCleanup: audioCleanupBackupPreferences,
            recordingFeedback: recordingFeedbackBackupPreferences,
            transcriptionCleanup: transcriptionCleanupBackupPreferences,
            paste: pasteBackupPreferences
        )
    }

    private var recordingShortcutBackupPreferences: RomaRecordingShortcutBackupPreferences {
        RomaRecordingShortcutBackupPreferences(
            primaryRecordingShortcutRawValue: primaryRecordingShortcutRawValue,
            secondaryRecordingShortcutRawValue: secondaryRecordingShortcutRawValue,
            primaryRecordingShortcutModeRawValue: primaryRecordingShortcutModeRawValue,
            secondaryRecordingShortcutModeRawValue: secondaryRecordingShortcutModeRawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: isMiddleClickToggleEnabled,
            middleClickActivationDelay: middleClickActivationDelay
        )
    }

    private var recordingFeedbackBackupPreferences: RomaRecordingFeedbackBackupPreferences {
        RomaRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    private var macOSShellBackupPreferences: RomaMacOSShellBackupPreferences {
        RomaMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            showDockIcon: isMenuBarOnly.map { !$0 },
            recorderType: recorderType
        )
    }

    private var pasteBackupPreferences: RomaPasteBackupPreferences {
        RomaPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: restoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    private var transcriptionAutoCleanupBackupPreferences: RomaTranscriptionAutoCleanupBackupPreferences {
        RomaTranscriptionAutoCleanupBackupPreferences(
            isEnabled: isTranscriptionCleanupEnabled,
            retentionMinutes: transcriptionRetentionMinutes
        )
    }

    private var audioCleanupBackupPreferences: RomaAudioCleanupBackupPreferences {
        RomaAudioCleanupBackupPreferences(
            isEnabled: isAudioCleanupEnabled,
            retentionDays: audioRetentionPeriod
        )
    }

    private var transcriptionCleanupBackupPreferences: RomaTranscriptionCleanupBackupPreferences {
        RomaTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationCleanupMode: punctuationCleanupMode,
            removePunctuation: removePunctuation,
            lowercaseTranscription: lowercaseTranscription
        )
    }

}

public struct RomaGeneralSettingsBackupPreferences: Equatable, Sendable {
    public let recordingShortcut: RomaRecordingShortcutBackupPreferences
    public let macOSShell: RomaMacOSShellBackupPreferences
    public let transcriptionAutoCleanup: RomaTranscriptionAutoCleanupBackupPreferences
    public let audioCleanup: RomaAudioCleanupBackupPreferences
    public let recordingFeedback: RomaRecordingFeedbackBackupPreferences
    public let transcriptionCleanup: RomaTranscriptionCleanupBackupPreferences
    public let paste: RomaPasteBackupPreferences

    public init(
        recordingShortcut: RomaRecordingShortcutBackupPreferences,
        macOSShell: RomaMacOSShellBackupPreferences,
        transcriptionAutoCleanup: RomaTranscriptionAutoCleanupBackupPreferences,
        audioCleanup: RomaAudioCleanupBackupPreferences,
        recordingFeedback: RomaRecordingFeedbackBackupPreferences,
        transcriptionCleanup: RomaTranscriptionCleanupBackupPreferences,
        paste: RomaPasteBackupPreferences
    ) {
        self.recordingShortcut = recordingShortcut
        self.macOSShell = macOSShell
        self.transcriptionAutoCleanup = transcriptionAutoCleanup
        self.audioCleanup = audioCleanup
        self.recordingFeedback = recordingFeedback
        self.transcriptionCleanup = transcriptionCleanup
        self.paste = paste
    }
}

public struct RomaGeneralSettingsBackupImportPlans: Equatable, Sendable {
    fileprivate let recordingShortcut: RomaRecordingShortcutBackupImportPlan
    fileprivate let macOSShell: RomaMacOSShellBackupImportPlan
    fileprivate let transcriptionAutoCleanup: RomaTranscriptionAutoCleanupBackupImportPlan
    fileprivate let audioCleanup: RomaAudioCleanupBackupImportPlan
    fileprivate let recordingFeedback: RomaRecordingFeedbackBackupImportPlan
    fileprivate let transcriptionCleanup: RomaTranscriptionCleanupBackupImportPlan
    fileprivate let paste: RomaPasteBackupImportPlan

    public init(
        recordingShortcut: RomaRecordingShortcutBackupImportPlan,
        macOSShell: RomaMacOSShellBackupImportPlan,
        transcriptionAutoCleanup: RomaTranscriptionAutoCleanupBackupImportPlan,
        audioCleanup: RomaAudioCleanupBackupImportPlan,
        recordingFeedback: RomaRecordingFeedbackBackupImportPlan,
        transcriptionCleanup: RomaTranscriptionCleanupBackupImportPlan,
        paste: RomaPasteBackupImportPlan
    ) {
        self.recordingShortcut = recordingShortcut
        self.macOSShell = macOSShell
        self.transcriptionAutoCleanup = transcriptionAutoCleanup
        self.audioCleanup = audioCleanup
        self.recordingFeedback = recordingFeedback
        self.transcriptionCleanup = transcriptionCleanup
        self.paste = paste
    }

    public func applyRuntimeState(
        to defaults: UserDefaults = .standard,
        applyRecordingShortcutImportPlan: (RomaRecordingShortcutBackupImportPlan) -> Void,
        applyMacOSShellImportPlan: (RomaMacOSShellBackupImportPlan) -> Void,
        applyRecordingFeedbackImportPlan: (RomaRecordingFeedbackBackupImportPlan) -> Void,
        reportImportedGeneralSettings: () -> Void
    ) {
        applyRecordingShortcutImportPlan(recordingShortcut)
        applyMacOSShellImportPlan(macOSShell)
        applyRecordingFeedbackImportPlan(recordingFeedback)

        RomaGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
            self,
            to: defaults
        )
        reportImportedGeneralSettings()
    }
}

public enum RomaGeneralSettingsBackupPolicy {
    public static func backupPreferences(
        recordingShortcut: RomaRecordingShortcutBackupPreferences,
        macOSShell: RomaMacOSShellBackupPreferences,
        transcriptionAutoCleanup: RomaTranscriptionAutoCleanupBackupPreferences,
        audioCleanup: RomaAudioCleanupBackupPreferences,
        recordingFeedback: RomaRecordingFeedbackBackupPreferences,
        transcriptionCleanup: RomaTranscriptionCleanupBackupPreferences,
        paste: RomaPasteBackupPreferences
    ) -> RomaGeneralSettingsBackupPreferences {
        RomaGeneralSettingsBackupPreferences(
            recordingShortcut: recordingShortcut,
            macOSShell: macOSShell,
            transcriptionAutoCleanup: transcriptionAutoCleanup,
            audioCleanup: audioCleanup,
            recordingFeedback: recordingFeedback,
            transcriptionCleanup: transcriptionCleanup,
            paste: paste
        )
    }

    public static func importPlans(
        from preferences: RomaGeneralSettingsBackupPreferences
    ) -> RomaGeneralSettingsBackupImportPlans {
        RomaGeneralSettingsBackupImportPlans(
            recordingShortcut: RomaRecordingShortcutPreference.backupImportPlan(
                from: preferences.recordingShortcut
            ),
            macOSShell: RomaMacOSShellBackupPreference.backupImportPlan(
                from: preferences.macOSShell
            ),
            transcriptionAutoCleanup: RomaTranscriptionAutoCleanupPreference.backupImportPlan(
                from: preferences.transcriptionAutoCleanup
            ),
            audioCleanup: RomaAudioCleanupPreference.backupImportPlan(
                from: preferences.audioCleanup
            ),
            recordingFeedback: RomaRecordingFeedbackPreference.backupImportPlan(
                from: preferences.recordingFeedback
            ),
            transcriptionCleanup: RomaTranscriptionCleanupSettings.backupImportPlan(
                from: preferences.transcriptionCleanup
            ),
            paste: RomaPastePreference.backupImportPlan(
                from: preferences.paste
            )
        )
    }

    public static func applyCorePreferenceImportPlans(
        _ importPlans: RomaGeneralSettingsBackupImportPlans,
        to defaults: UserDefaults = .standard
    ) {
        applyTranscriptionAutoCleanupImportPlan(importPlans.transcriptionAutoCleanup, to: defaults)
        applyAudioCleanupImportPlan(importPlans.audioCleanup, to: defaults)
        applyRecordingFeedbackCorePreferenceImportPlan(importPlans.recordingFeedback, to: defaults)
        applyTranscriptionCleanupImportPlan(importPlans.transcriptionCleanup, to: defaults)
        applyPasteImportPlan(importPlans.paste, to: defaults)
    }

    private static func applyTranscriptionAutoCleanupImportPlan(
        _ importPlan: RomaTranscriptionAutoCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isEnabled = importPlan.isEnabled {
            RomaTranscriptionAutoCleanupPreference.saveIsEnabled(isEnabled, to: defaults)
        }
        if let retentionMinutes = importPlan.retentionMinutes {
            RomaTranscriptionAutoCleanupPreference.saveRetentionMinutes(retentionMinutes, to: defaults)
        }
    }

    private static func applyAudioCleanupImportPlan(
        _ importPlan: RomaAudioCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isEnabled = importPlan.isEnabled {
            RomaAudioCleanupPreference.saveIsEnabled(isEnabled, to: defaults)
        }
        if let retentionDays = importPlan.retentionDays {
            RomaAudioCleanupPreference.saveRetentionDays(retentionDays, to: defaults)
        }
    }

    private static func applyRecordingFeedbackCorePreferenceImportPlan(
        _ importPlan: RomaRecordingFeedbackBackupImportPlan,
        to defaults: UserDefaults
    ) {
        importPlan.applyCorePreferenceState { isExperimentalFeaturesEnabled in
            RomaRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(
                isExperimentalFeaturesEnabled,
                to: defaults
            )
        }
    }

    private static func applyTranscriptionCleanupImportPlan(
        _ importPlan: RomaTranscriptionCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isTextFormattingEnabled = importPlan.isTextFormattingEnabled {
            RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(
                isTextFormattingEnabled,
                to: defaults
            )
        }
        if let punctuationCleanupMode = importPlan.punctuationCleanupMode {
            PunctuationCleanupMode.setCurrent(punctuationCleanupMode, in: defaults)
        }
        if let lowercaseTranscription = importPlan.lowercaseTranscription {
            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(
                lowercaseTranscription,
                to: defaults
            )
        }
    }

    private static func applyPasteImportPlan(
        _ importPlan: RomaPasteBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let shouldRestoreClipboardAfterPaste = importPlan.shouldRestoreClipboardAfterPaste {
            RomaPastePreference.saveShouldRestoreClipboardAfterPaste(
                shouldRestoreClipboardAfterPaste,
                to: defaults
            )
        }
        if let clipboardRestoreDelay = importPlan.clipboardRestoreDelay {
            RomaPastePreference.saveClipboardRestoreDelay(clipboardRestoreDelay, to: defaults)
        }
    }
}

public struct RomaSettingsBackupPresentation: Equatable, Sendable {
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

    public static let macOS = RomaSettingsBackupPresentation(
        defaultFileName: "Roma_Just_Talk_Settings_Backup.json",
        exportPanelTitle: "Export Roma Just Talk Settings",
        exportPanelMessage: "Choose a location to save your settings.",
        importPanelTitle: "Import Roma Just Talk Settings",
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
        restartRecommendationText: "It is recommended to restart Roma Just Talk for all changes to take full effect."
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
        categories: Set<RomaSettingsBackupCategory>
    ) -> String {
        "Settings imported successfully from \(fileName).\n\nImported: \(RomaSettingsBackupImportPolicy.categorySummary(for: categories))."
    }

    public func importFailureMessage(localizedDescription: String) -> String {
        "Error importing settings: \(localizedDescription). The file might be corrupted or not in the correct format."
    }

    public func importSuccessInformativeText(
        fileName: String,
        categories: Set<RomaSettingsBackupCategory>
    ) -> String {
        var informativeText = importSuccessMessage(fileName: fileName, categories: categories)
        if RomaSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories) {
            informativeText += "\n\n\(apiKeyReminderText)"
        }
        informativeText += "\n\n\(restartRecommendationText)"
        return informativeText
    }
}

public struct RomaEnhancementIntegerOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Int

    public var id: Int { value }
}

public struct RomaEnhancementRetryOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Bool

    public var id: Bool { value }
}

public struct RomaEnhancementSettingsPresentation: Equatable, Sendable {
    public let title: String
    public let closeButtonHelp: String
    public let generalSectionTitle: String
    public let enableEnhancementTitle: String
    public let enableEnhancementHelp: String
    public let enableEnhancementLearnMoreURLString: String
    public let settingsButtonSystemImageName: String
    public let settingsButtonHelp: String
    public let promptsSectionTitle: String
    public let contextSectionTitle: String
    public let clipboardContextTitle: String
    public let clipboardContextHelp: String
    public let screenContextTitle: String
    public let screenContextHelp: String
    public let skipShortEnhancementTitle: String
    public let skipShortEnhancementHelp: String
    public let disclosureSystemImageName: String
    public let minimumWordsPickerTitle: String
    public let shortEnhancementWordOptions: [RomaEnhancementIntegerOption]
    public let timeoutPickerTitle: String
    public let timeoutOptions: [RomaEnhancementIntegerOption]
    public let timeoutRetryPickerTitle: String
    public let timeoutRetryOptions: [RomaEnhancementRetryOption]
    public let requestTimeoutSectionTitle: String
    public let requestTimeoutHelp: String
    public let shortcutsSectionTitle: String
    public let toggleEnhancementShortcutTitle: String
    public let toggleEnhancementShortcutHelp: String
    public let switchPromptShortcutTitle: String
    public let switchPromptShortcutHelp: String
    public let shortcutLearnMoreURLString: String
    public let switchPromptKeyChipTitles: [String]

    public static let macOS = RomaEnhancementSettingsPresentation(
        title: "Enhancement Settings",
        closeButtonHelp: "Close",
        generalSectionTitle: "General",
        enableEnhancementTitle: "Enable Enhancement",
        enableEnhancementHelp: "AI enhancement lets you pass the transcribed audio through LLMs to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc.",
        enableEnhancementLearnMoreURLString: "https://roma-just-talk.com/readme",
        settingsButtonSystemImageName: "gear",
        settingsButtonHelp: "Enhancement settings",
        promptsSectionTitle: "Enhancement Prompts",
        contextSectionTitle: "Context",
        clipboardContextTitle: "Clipboard Context",
        clipboardContextHelp: "Use clipboard text to understand context for better enhancement.",
        screenContextTitle: "Screen Context",
        screenContextHelp: "Capture on-screen text to understand context for better enhancement.",
        skipShortEnhancementTitle: "Skip short transcriptions",
        skipShortEnhancementHelp: "Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement.",
        disclosureSystemImageName: "chevron.right",
        minimumWordsPickerTitle: "Minimum words",
        shortEnhancementWordOptions: (1...15).map {
            RomaEnhancementIntegerOption(title: "\($0) \($0 == 1 ? "word" : "words")", value: $0)
        },
        timeoutPickerTitle: "Timeout duration",
        timeoutOptions: [3, 5, 7, 10, 15, 20, 30, 40, 50, 60].map {
            RomaEnhancementIntegerOption(title: "\($0) seconds", value: $0)
        },
        timeoutRetryPickerTitle: "On timeout",
        timeoutRetryOptions: [
            RomaEnhancementRetryOption(title: "Fail immediately", value: false),
            RomaEnhancementRetryOption(title: "Retry", value: true)
        ],
        requestTimeoutSectionTitle: "Request Timeout",
        requestTimeoutHelp: "Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts).",
        shortcutsSectionTitle: "Shortcuts",
        toggleEnhancementShortcutTitle: "Toggle AI Enhancement",
        toggleEnhancementShortcutHelp: "Quickly enable or disable AI enhancement while recording. Available only when Roma Just Talk is running and the recorder is visible.",
        switchPromptShortcutTitle: "Switch Enhancement Prompt",
        switchPromptShortcutHelp: "Switch between your saved prompts using ⌘1 through ⌘0 to activate the corresponding prompt in the order they are saved. Available only when Roma Just Talk is running and the recorder is visible.",
        shortcutLearnMoreURLString: "https://roma-just-talk.com/readme",
        switchPromptKeyChipTitles: ["⌘", "1 – 0"]
    )
}

public enum RomaStartupPreferenceMigrationPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

public enum RomaStartupPreferenceMigration {
    public static func migrateLegacyPreferences(
        for platform: RomaStartupPreferenceMigrationPlatform,
        in defaults: UserDefaults = .standard
    ) {
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded(in: defaults)

        switch platform {
        case .iOS:
            break
        case .macOS:
            RomaPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)
        }
    }
}

public enum RomaMacOSLaunchAtLoginDefaultPolicy {
    public static let didApplyDefaultKey = RomaUserDefaultsKey.didApplyLaunchAtLoginDefault
    public static let defaultDidApplyDefault = RomaPreferenceDefault.didApplyLaunchAtLoginDefault

    public static var registeredDefaults: [String: Any] {
        [didApplyDefaultKey: defaultDidApplyDefault]
    }

    public static func shouldEnableByDefaultBeforeRegisteringDefaults(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        !RomaOnboardingPreference.hasStoredCompletionState(from: defaults)
            && defaults.object(forKey: didApplyDefaultKey) == nil
    }

    public static func markDefaultApplied(to defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: didApplyDefaultKey)
    }
}

public struct RomaDefaultSettings: Equatable, Sendable {
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
        audioSessionTimeoutSeconds: Int = RomaPreferenceDefault.audioSessionTimeoutSeconds,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        isTextFormattingEnabled: Bool = RomaPreferenceDefault.isTextFormattingEnabled,
        isVADEnabled: Bool = RomaPreferenceDefault.isVADEnabled,
        lowercaseTranscription: Bool = RomaPreferenceDefault.lowercaseTranscription,
        removeFillerWords: Bool = RomaPreferenceDefault.removeFillerWords,
        fillerWords: [String] = RomaFillerWords.defaultWords,
        selectedTranscriptionLanguage: String = RomaLanguageCatalog.autoDetectCode,
        isTranscriptionCleanupEnabled: Bool = false,
        transcriptionRetentionMinutes: Int = RomaPreferenceDefault.transcriptionRetentionMinutes,
        isAudioCleanupEnabled: Bool = false,
        audioRetentionDays: Int = RomaPreferenceDefault.audioRetentionDays,
        skipShortEnhancement: Bool = RomaPreferenceDefault.skipShortEnhancement,
        shortEnhancementWordThreshold: Int = RomaPreferenceDefault.shortEnhancementWordThreshold,
        enhancementTimeoutSeconds: Int = RomaPreferenceDefault.enhancementTimeoutSeconds,
        enhancementRetryOnTimeout: Bool = RomaPreferenceDefault.enhancementRetryOnTimeout
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

    public static let iOS = RomaDefaultSettings()
    public static let macOS = RomaDefaultSettings(
        selectedTranscriptionLanguage: RomaPreferenceDefault.macOSSelectedTranscriptionLanguage
    )

    public var transcriptionCleanupSettings: RomaTranscriptionCleanupSettings {
        RomaTranscriptionCleanupSettings(
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
            RomaUserDefaultsKey.hasCompletedOnboarding: hasCompletedOnboarding,
            RomaUserDefaultsKey.isTextFormattingEnabled: isTextFormattingEnabled,
            RomaUserDefaultsKey.isVADEnabled: isVADEnabled,
            RomaUserDefaultsKey.removeFillerWords: removeFillerWords,
            PunctuationCleanupMode.legacyRemovePunctuationKey: punctuationCleanupMode == .removeAll,
            RomaUserDefaultsKey.lowercaseTranscription: lowercaseTranscription,
            RomaUserDefaultsKey.selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            RomaUserDefaultsKey.isTranscriptionCleanupEnabled: isTranscriptionCleanupEnabled,
            RomaUserDefaultsKey.transcriptionRetentionMinutes: transcriptionRetentionMinutes,
            RomaUserDefaultsKey.isAudioCleanupEnabled: isAudioCleanupEnabled,
            RomaUserDefaultsKey.audioRetentionPeriodDays: audioRetentionDays,
            RomaUserDefaultsKey.skipShortEnhancement: skipShortEnhancement,
            RomaUserDefaultsKey.shortEnhancementWordThreshold: shortEnhancementWordThreshold,
            RomaUserDefaultsKey.enhancementTimeoutSeconds: enhancementTimeoutSeconds,
            RomaUserDefaultsKey.enhancementRetryOnTimeout: enhancementRetryOnTimeout
        ]

        if let currentTranscriptionModel {
            defaults[RomaUserDefaultsKey.currentTranscriptionModel] = currentTranscriptionModel
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

public struct RomaAppSettingsResetState {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let apiKeyState: RomaProviderAPIKeyState
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: RomaTranscriptionCleanupSettings
    public let fillerWords: [String]
    public let wordReplacements: [RomaWordReplacementRule]
    public let customVocabularyTerms: [String]
    public let selectedTranscriptionLanguage: String
    public let apiKeyProvidersToDelete: [RomaProviderKind]

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        apiKeyState: RomaProviderAPIKeyState,
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: RomaTranscriptionCleanupSettings,
        fillerWords: [String],
        wordReplacements: [RomaWordReplacementRule],
        customVocabularyTerms: [String],
        selectedTranscriptionLanguage: String,
        apiKeyProvidersToDelete: [RomaProviderKind] = RomaProviderKind.userAPIKeyProviders
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

    private var applicationActions: [RomaAppSettingsResetAction] {
        var actions: [RomaAppSettingsResetAction] = [
            .applyResetState(self),
            .clearCoreUserSettings
        ]
        if !apiKeyProvidersToDelete.isEmpty {
            actions.append(.deleteProviderAPIKeys(apiKeyProvidersToDelete))
        }
        return actions
    }
}

fileprivate enum RomaAppSettingsResetAction {
    case applyResetState(RomaAppSettingsResetState)
    case clearCoreUserSettings
    case deleteProviderAPIKeys([RomaProviderKind])
}

public extension RomaAppSettingsResetState {
    func applyRuntimeState(
        setModes: ([Mode]) -> Void,
        setSelectedModeId: (UUID?) -> Void,
        setAPIKeyState: (RomaProviderAPIKeyState) -> Void,
        setAudioSessionTimeoutSeconds: (Int) -> Void,
        setTranscriptionCleanupSettings: (RomaTranscriptionCleanupSettings) -> Void,
        setFillerWords: ([String]) -> Void,
        setWordReplacements: ([RomaWordReplacementRule]) -> Void,
        setCustomVocabularyTerms: ([String]) -> Void,
        setSelectedTranscriptionLanguage: (String) -> Void,
        clearCoreUserSettings: () -> Void,
        deleteProviderAPIKeys: ([RomaProviderKind]) -> Void
    ) {
        for action in applicationActions {
            switch action {
            case .applyResetState(let resetState):
                setModes(resetState.modes)
                setSelectedModeId(resetState.selectedModeId)
                setAPIKeyState(resetState.apiKeyState)
                setAudioSessionTimeoutSeconds(resetState.audioSessionTimeoutSeconds)
                setTranscriptionCleanupSettings(resetState.transcriptionCleanupSettings)
                setFillerWords(resetState.fillerWords)
                setWordReplacements(resetState.wordReplacements)
                setCustomVocabularyTerms(resetState.customVocabularyTerms)
                setSelectedTranscriptionLanguage(resetState.selectedTranscriptionLanguage)
            case .clearCoreUserSettings:
                clearCoreUserSettings()
            case .deleteProviderAPIKeys(let providers):
                deleteProviderAPIKeys(providers)
            }
        }
    }
}

public struct RomaIOSAppSettingsStartupState {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let apiKeyState: RomaProviderAPIKeyState
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: RomaTranscriptionCleanupSettings
    public let fillerWords: [String]
    public let wordReplacements: [RomaWordReplacementRule]
    public let customVocabularyTerms: [String]
    public let selectedTranscriptionLanguage: String

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        apiKeyState: RomaProviderAPIKeyState,
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: RomaTranscriptionCleanupSettings,
        fillerWords: [String],
        wordReplacements: [RomaWordReplacementRule],
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

public enum RomaIOSAppSettingsStartupPolicy {
    public static func state(
        from defaults: UserDefaults = .standard,
        verifiedProviders: Set<RomaProviderKind>,
        loadStoredAPIKey: (RomaProviderKind) -> String
    ) -> RomaIOSAppSettingsStartupState {
        RomaIOSAppSettingsStartupState(
            modes: RomaModeStorage.loadModes(from: defaults),
            selectedModeId: RomaModeStorage.loadSelectedModeId(from: defaults),
            apiKeyState: RomaProviderAPIKeyState.loadingStoredKeys(
                verifiedProviders: verifiedProviders,
                loadStoredAPIKey: loadStoredAPIKey
            ),
            audioSessionTimeoutSeconds: RomaAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
            transcriptionCleanupSettings: RomaTranscriptionCleanupSettings.current(in: defaults),
            fillerWords: RomaFillerWordPreference.words(from: defaults),
            wordReplacements: RomaWordReplacementPreference.rules(from: defaults),
            customVocabularyTerms: RomaCustomVocabularyPreference.terms(from: defaults),
            selectedTranscriptionLanguage: RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults)
        )
    }
}

public struct RomaIOSFirstTimeSetupPlan {
    private let modeSettingsRepairPlan: RomaModeSettingsRepairPlan
    private let shouldSaveHasCompletedOnboarding: Bool

    public init(
        modeSettingsRepairPlan: RomaModeSettingsRepairPlan,
        shouldSaveHasCompletedOnboarding: Bool
    ) {
        self.modeSettingsRepairPlan = modeSettingsRepairPlan
        self.shouldSaveHasCompletedOnboarding = shouldSaveHasCompletedOnboarding
    }

    private var applicationActions: [RomaIOSFirstTimeSetupAction] {
        var actions: [RomaIOSFirstTimeSetupAction] = [
            .applyModeSettingsRepair(modeSettingsRepairPlan)
        ]
        if shouldSaveHasCompletedOnboarding {
            actions.append(.saveHasCompletedOnboarding)
        }
        return actions
    }
}

fileprivate enum RomaIOSFirstTimeSetupAction {
    case applyModeSettingsRepair(RomaModeSettingsRepairPlan)
    case saveHasCompletedOnboarding
}

public extension RomaIOSFirstTimeSetupPlan {
    func applyRuntimeState(
        applyModeSettingsRepair: (RomaModeSettingsRepairPlan) -> Void,
        saveHasCompletedOnboarding: () -> Void
    ) {
        for action in applicationActions {
            switch action {
            case .applyModeSettingsRepair(let plan):
                applyModeSettingsRepair(plan)
            case .saveHasCompletedOnboarding:
                saveHasCompletedOnboarding()
            }
        }
    }
}

public enum RomaIOSFirstTimeSetupPolicy {
    public static func plan(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String
    ) -> RomaIOSFirstTimeSetupPlan {
        RomaIOSFirstTimeSetupPlan(
            modeSettingsRepairPlan: RomaModeSettingsPolicy.defaultModeRepairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            ),
            shouldSaveHasCompletedOnboarding: true
        )
    }
}

public extension RomaDefaultSettings {
    var appSettingsResetState: RomaAppSettingsResetState {
        RomaAppSettingsResetState(
            modes: [],
            selectedModeId: nil,
            apiKeyState: RomaProviderAPIKeyState(),
            audioSessionTimeoutSeconds: audioSessionTimeoutSeconds,
            transcriptionCleanupSettings: transcriptionCleanupSettings,
            fillerWords: fillerWords,
            wordReplacements: [],
            customVocabularyTerms: [],
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            apiKeyProvidersToDelete: RomaProviderKind.userAPIKeyProviders
        )
    }
}

public enum RomaOnboardingPreference {
    public static func hasStoredCompletionState(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: RomaUserDefaultsKey.hasCompletedOnboarding) != nil
    }

    public static func hasCompletedOnboarding(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RomaUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func saveHasCompletedOnboarding(
        _ completed: Bool = true,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(completed, forKey: RomaUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.hasCompletedOnboarding)
    }
}

public struct RomaAudioSessionTimeoutPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let timeoutTitle: String
    public let detailText: String

    public static let iOS = RomaAudioSessionTimeoutPresentation(
        sectionTitle: "Audio Settings",
        timeoutTitle: "Session Timeout",
        detailText: "How long to keep the microphone session active after recording stops. Longer timeouts prevent 'session activation failed' errors when recording frequently, but may use more battery."
    )
}

public enum RomaAudioSessionDeactivationPlan: Equatable, Sendable {
    case immediate
    case delayed(TimeInterval)

    public var executionPlan: RomaAudioSessionDeactivationExecutionPlan {
        switch self {
        case .immediate:
            return RomaAudioSessionDeactivationExecutionPlan(action: .deactivateSession)
        case .delayed:
            return RomaAudioSessionDeactivationExecutionPlan(action: .runCountdownTimer)
        }
    }
}

fileprivate enum RomaAudioSessionDeactivationExecutionAction: Equatable, Sendable {
    case deactivateSession
    case runCountdownTimer
}

public struct RomaAudioSessionDeactivationExecutionPlan: Equatable, Sendable {
    private let action: RomaAudioSessionDeactivationExecutionAction

    fileprivate init(action: RomaAudioSessionDeactivationExecutionAction) {
        self.action = action
    }

    public func applyRuntimeState(
        deactivateSession: () -> Void,
        runCountdownTimer: () -> Void,
        countdownTimerDidStart: () -> Void = {}
    ) {
        switch action {
        case .deactivateSession:
            deactivateSession()
        case .runCountdownTimer:
            runCountdownTimer()
            countdownTimerDidStart()
        }
    }
}

public enum RomaMenuBarPreference {
    public static let showMenuBarIconKey = RomaUserDefaultsKey.showMenuBarIcon
    public static let legacyIsMenuBarOnlyKey = RomaUserDefaultsKey.legacyIsMenuBarOnly
    public static let defaultShowMenuBarIcon = RomaPreferenceDefault.showMenuBarIcon
    public static let defaultShowDockIcon = RomaPreferenceDefault.showDockIcon

    public static var registeredDefaults: [String: Any] {
        [
            showMenuBarIconKey: defaultShowMenuBarIcon,
            legacyIsMenuBarOnlyKey: !defaultShowDockIcon
        ]
    }

    public static func shouldShowMenuBarIcon(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showMenuBarIconKey)
    }

    public static func saveShowMenuBarIcon(_ shouldShow: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(shouldShow, forKey: showMenuBarIconKey)
    }

    public static func shouldShowDockIcon(from defaults: UserDefaults = .standard) -> Bool {
        guard let isMenuBarOnly = defaults.object(forKey: legacyIsMenuBarOnlyKey) as? Bool else {
            return defaultShowDockIcon
        }
        return !isMenuBarOnly
    }

    public static func saveShowDockIcon(_ shouldShow: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(!shouldShow, forKey: legacyIsMenuBarOnlyKey)
    }
}

public enum RomaMacOSMenuBarPresentation {
    public static let toggleRecorderTitle = "Toggle Recorder"
    public static let manageModelsTitle = "Manage Models"
    public static let aiEnhancementToggleTitle = "AI Enhancement"
    public static let noProvidersConnectedText = "No providers connected"
    public static let noModelsAvailableText = "No models available"
    public static let audioInputTitle = "Audio Input"
    public static let noDevicesAvailableText = "No devices available"
    public static let additionalMenuTitle = "Additional"
    public static let clipboardContextTitle = RomaEnhancementSettingsPresentation.macOS.clipboardContextTitle
    public static let contextAwarenessTitle = RomaPowerModePresentation.contextAwarenessDisplayText
    public static let retryLastTranscriptionTitle = RomaRecordingShortcutPreference.macOSSettingsPresentation.retryLastTranscriptionLabel
    public static let copyLastTranscriptionTitle = "Copy Last Transcription"
    public static let historyTitle = RomaMacOSNavigationDestination.history.rawValue
    public static let permissionsTitle = RomaMacOSNavigationDestination.permissions.rawValue
    public static let settingsTitle = RomaMacOSNavigationDestination.settings.rawValue
    public static let showDockIconTitle = "Show Dock Icon"
    public static let hideDockIconTitle = "Hide Dock Icon"
    public static let hideMenuBarIconTitle = "Hide Menu Bar Icon"
    public static let launchAtLoginTitle = "Launch at Login"
    public static let checkForUpdatesTitle = "Check for Updates"
    public static let helpAndSupportTitle = "Help and Support"
    public static let selectionCheckmarkSystemImageName = "checkmark"
    public static let pickerSystemImageName = "chevron.up.chevron.down"

    public static var quitTitle: String {
        "Quit \(RomaAppIdentity.compactDisplayName)"
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

    public static func dockIconTitle(showDockIcon: Bool) -> String {
        showDockIcon ? hideDockIconTitle : showDockIconTitle
    }

    private static let noneDisplayText = "None"
}

public enum RomaMacOSMenuBarDiagnostics {
    public static let windowDidCloseAccessoryPolicyMessage = "windowDidClose: no visible windows, switching to .accessory policy"
    public static let focusMainWindowActivationPolicyMessage = "focusMainWindow: activation policy set to .regular"
    public static let focusMainWindowFailedMessage = "focusMainWindow: showMainWindow returned nil"
    public static let updateActivationPolicyAccessoryMessage = "updateAppActivationPolicy: switching to .accessory (dock icon hidden)"
    public static let updateActivationPolicyRegularMessage = "updateAppActivationPolicy: switching to .regular (dock icon visible)"
    public static let openMainWindowActivationPolicyMessage = "openMainWindowAndNavigate: activation policy set to .regular"
    public static let openHistoryWindowOpeningMessage = "openHistoryWindow: opening history window"
    public static let openHistoryWindowActivationPolicyMessage = "openHistoryWindow: activation policy set to .regular"

    public static func openMainWindowRequestedMessage(destination: String, showDockIcon: Bool) -> String {
        "openMainWindowAndNavigate: requested destination=\(destination), showDockIcon=\(showDockIcon)"
    }

    public static func openMainWindowFailedMessage(destination: String) -> String {
        "openMainWindowAndNavigate: showMainWindow returned nil — cannot navigate to \(destination)"
    }

    public static func openMainWindowPostingNavigationMessage(destination: String) -> String {
        "openMainWindowAndNavigate: window shown, posting navigation notification for \(destination)"
    }

    public static func openMainWindowNavigationPostedMessage(destination: String) -> String {
        "openMainWindowAndNavigate: navigation notification posted for \(destination)"
    }

    public static func openHistoryWindowDependenciesMissingMessage(
        hasModelContainer: Bool,
        hasEngine: Bool
    ) -> String {
        "openHistoryWindow: dependencies not configured (modelContainer=\(hasModelContainer), engine=\(hasEngine))"
    }
}

public struct RomaMacOSShellBackupPreferences: Codable, Equatable, Sendable {
    public let launchAtLoginEnabled: Bool?
    // Legacy backup wire field. Runtime callers use the positive showDockIcon view.
    public let isMenuBarOnly: Bool?
    public let recorderType: String?

    public var showDockIcon: Bool? {
        isMenuBarOnly.map { !$0 }
    }

    public init(
        launchAtLoginEnabled: Bool?,
        showDockIcon: Bool?,
        recorderType: String?
    ) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.isMenuBarOnly = showDockIcon.map { !$0 }
        self.recorderType = recorderType
    }
}

public struct RomaMacOSShellBackupImportPlan: Equatable, Sendable {
    private let launchAtLoginEnabled: Bool?
    private let showDockIcon: Bool?
    private let recorderType: String?

    public init(
        launchAtLoginEnabled: Bool?,
        showDockIcon: Bool?,
        recorderType: String?
    ) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.showDockIcon = showDockIcon
        self.recorderType = recorderType
    }

    public func applyRuntimeState(
        setLaunchAtLoginEnabled: (Bool) -> Void,
        setShowDockIcon: (Bool) -> Void,
        setRecorderType: (String) -> Void
    ) {
        if let launchAtLoginEnabled {
            setLaunchAtLoginEnabled(launchAtLoginEnabled)
        }
        if let showDockIcon {
            setShowDockIcon(showDockIcon)
        }
        if let recorderType {
            setRecorderType(recorderType)
        }
    }
}

public enum RomaMacOSShellBackupPreference {
    public static func backupPreferences(
        launchAtLoginEnabled: Bool,
        showDockIcon: Bool,
        recorderType: String
    ) -> RomaMacOSShellBackupPreferences {
        RomaMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            showDockIcon: showDockIcon,
            recorderType: recorderType
        )
    }

    public static func backupImportPlan(
        from preferences: RomaMacOSShellBackupPreferences
    ) -> RomaMacOSShellBackupImportPlan {
        RomaMacOSShellBackupImportPlan(
            launchAtLoginEnabled: preferences.launchAtLoginEnabled,
            showDockIcon: preferences.showDockIcon,
            recorderType: preferences.recorderType
        )
    }
}

public enum RomaAudioSessionTimeoutPreference {
    public static let minimumSeconds = 0
    public static let maximumSeconds = 300
    public static let stepSeconds = 15
    public static let countdownUpdateInterval: TimeInterval = 1.0
    public static let settingsPresentation = RomaAudioSessionTimeoutPresentation.iOS

    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: RomaUserDefaultsKey.audioSessionTimeoutSeconds) as? Int
            ?? RomaPreferenceDefault.audioSessionTimeoutSeconds
    }

    public static func displayText(for seconds: Int) -> String {
        "\(seconds)s"
    }

    public static func deactivationPlan(for seconds: Int) -> RomaAudioSessionDeactivationPlan {
        seconds <= 0 ? .immediate : .delayed(TimeInterval(seconds))
    }

    public static func remainingTimeAfterCountdownTick(_ remainingTime: TimeInterval) -> TimeInterval {
        remainingTime - countdownUpdateInterval
    }

    public static func saveTimeoutSeconds(_ seconds: Int, to defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: RomaUserDefaultsKey.audioSessionTimeoutSeconds)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.audioSessionTimeoutSeconds)
    }
}

public struct RomaSettingsTogglePresentation: Equatable, Sendable {
    public let title: String
    public let helpText: String
}

public struct RomaMacOSAdvancedTranscriptionSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let vad: RomaSettingsTogglePresentation
    public let modelPrewarm: RomaSettingsTogglePresentation
    public let liveTextPreview: RomaSettingsTogglePresentation

    public static let macOS = RomaMacOSAdvancedTranscriptionSettingsPresentation(
        sectionTitle: "Advanced",
        vad: RomaSettingsTogglePresentation(
            title: "Voice Activity Detection (VAD)",
            helpText: "Use VAD inside batch/final transcription when supported."
        ),
        modelPrewarm: RomaSettingsTogglePresentation(
            title: "Prewarm model (Experimental)",
            helpText: "Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization."
        ),
        liveTextPreview: RomaSettingsTogglePresentation(
            title: "Show Transcript Preview",
            helpText: "Displays in-progress transcript text when the active model provides it."
        )
    )
}

public enum RomaVADPreference {
    public static let userDefaultsKey = RomaUserDefaultsKey.isVADEnabled
    public static let defaultIsEnabled = RomaPreferenceDefault.isVADEnabled
    public static let settingsPresentation = RomaMacOSAdvancedTranscriptionSettingsPresentation.macOS.vad
    public static let macOSSettingsPresentation = settingsPresentation

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

public struct RomaMacOSLocalWhisperPromptSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let helpText: String
    public let learnMoreURLString: String
    public let saveButtonTitle: String
    public let editButtonTitle: String

    public static let macOS = RomaMacOSLocalWhisperPromptSettingsPresentation(
        sectionTitle: "Output Format",
        helpText: "Only supported for local Whisper models. Unlike GPT, Voice Models(whisper) follows the style of your prompt rather than instructions. Use examples of your desired output format instead of commands.",
        learnMoreURLString: "https://cookbook.openai.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting",
        saveButtonTitle: "Save",
        editButtonTitle: "Edit"
    )
}

public struct RomaLocalWhisperPromptDraftState: Equatable, Sendable {
    public var text: String
    public var isEditing: Bool

    public init(
        text: String = "",
        isEditing: Bool = false
    ) {
        self.text = text
        self.isEditing = isEditing
    }

    public func editing(prompt: String) -> RomaLocalWhisperPromptDraftState {
        RomaLocalWhisperPromptDraftState(text: prompt, isEditing: true)
    }

    public func saved() -> RomaLocalWhisperPromptDraftState {
        RomaLocalWhisperPromptDraftState(text: text, isEditing: false)
    }

    public func refreshingForSelectedLanguage(
        prompt: String
    ) -> RomaLocalWhisperPromptDraftState {
        guard isEditing else {
            return self
        }
        return RomaLocalWhisperPromptDraftState(text: prompt, isEditing: true)
    }
}

public enum RomaLocalWhisperPromptCatalog {
    public static let customLanguagePromptsKey = "CustomLanguagePrompts"
    public static let settingsPresentation = RomaMacOSLocalWhisperPromptSettingsPresentation.macOS
    public static let macOSSettingsPresentation = settingsPresentation

    public static func promptForSelectedLanguage(
        from defaults: UserDefaults = .standard,
        customPrompts: [String: String]? = nil,
        fallbackLanguage: String = "en"
    ) -> String {
        let language = RomaTranscriptionLanguagePreference.selectedLanguage(
            from: defaults,
            fallback: fallbackLanguage
        )
        return prompt(for: language, customPrompts: customPrompts ?? storedCustomPrompts(from: defaults))
    }

    public static func prompt(for language: String, customPrompts: [String: String] = [:]) -> String {
        if let customPrompt = customPrompts[language], !customPrompt.isEmpty {
            return customPrompt
        }

        return defaultPrompt(for: language)
    }

    public static func storedCustomPrompts(from defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: customLanguagePromptsKey) as? [String: String] ?? [:]
    }

    public static func saveCustomPrompts(_ prompts: [String: String], to defaults: UserDefaults = .standard) {
        defaults.set(prompts, forKey: customLanguagePromptsKey)
    }

    public static func saveCustomPrompt(
        _ prompt: String,
        for language: String,
        to defaults: UserDefaults = .standard
    ) {
        var prompts = storedCustomPrompts(from: defaults)
        prompts[language] = prompt
        saveCustomPrompts(prompts, to: defaults)
    }

    public static func defaultPrompt(for language: String) -> String {
        defaultPromptsByLanguage[language] ?? defaultPromptsByLanguage["default"] ?? ""
    }

    private static let defaultPromptsByLanguage: [String: String] = [
        "en": "Hello, how are you doing? Nice to meet you.",
        "hi": "नमस्ते, कैसे हैं आप? आपसे मिलकर अच्छा लगा।",
        "bn": "নমস্কার, কেমন আছেন? আপনার সাথে দেখা হয়ে ভালো লাগলো।",
        "ja": "こんにちは、お元気ですか？お会いできて嬉しいです。",
        "ko": "안녕하세요, 잘 지내시나요? 만나서 반갑습니다.",
        "zh": "你好，最近好吗？见到你很高兴。",
        "th": "สวัสดีครับ/ค่ะ, สบายดีไหม? ยินดีที่ได้พบคุณ",
        "vi": "Xin chào, bạn khỏe không? Rất vui được gặp bạn.",
        "yue": "你好，最近點呀？見到你好開心。",
        "es": "¡Hola, ¿cómo estás? Encantado de conocerte.",
        "fr": "Bonjour, comment allez-vous? Ravi de vous rencontrer.",
        "de": "Hallo, wie geht es dir? Schön dich kennenzulernen.",
        "it": "Ciao, come stai? Piacere di conoscerti.",
        "pt": "Olá, como você está? Prazer em conhecê-lo.",
        "ru": "Здравствуйте, как ваши дела? Приятно познакомиться.",
        "pl": "Cześć, jak się masz? Miło cię poznać.",
        "nl": "Hallo, hoe gaat het? Aangenaam kennis te maken.",
        "tr": "Merhaba, nasılsın? Tanıştığımıza memnun oldum.",
        "ar": "مرحباً، كيف حالك؟ سعيد بلقائك.",
        "fa": "سلام، حال شما چطور است؟ از آشنایی با شما خوشوقتم.",
        "he": ",שלום, מה שלומך? נעים להכיר",
        "ta": "வணக்கம், எப்படி இருக்கிறீர்கள்? உங்களை சந்தித்ததில் மகிழ்ச்சி.",
        "te": "నమస్కారం, ఎలా ఉన్నారు? కలవడం చాలా సంతోషం.",
        "ml": "നമസ്കാരം, സുഖമാണോ? കണ്ടതിൽ സന്തോഷം.",
        "kn": "ನಮಸ್ಕಾರ, ಹೇಗಿದ್ದೀರಾ? ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಿ ಸಂತೋಷವಾಗಿದೆ.",
        "ur": "السلام علیکم، کیسے ہیں آپ؟ آپ سے مل کر خوشی ہوئی۔",
        "default": ""
    ]
}

public enum RomaTranscriptionPromptPreference {
    public static func storedPrompt(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: RomaUserDefaultsKey.transcriptionPrompt)
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
            fallback: RomaLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults)
        )
    }

    @discardableResult
    public static func saveLocalWhisperPromptForSelectedLanguage(
        from defaults: UserDefaults = .standard,
        customPrompts: [String: String]? = nil,
        fallbackLanguage: String = RomaDefaultSettings.macOS.selectedTranscriptionLanguage
    ) -> String {
        let prompt = RomaLocalWhisperPromptCatalog.promptForSelectedLanguage(
            from: defaults,
            customPrompts: customPrompts,
            fallbackLanguage: fallbackLanguage
        )
        savePrompt(prompt, to: defaults)
        return prompt
    }

    public static func saveLocalWhisperCustomPrompt(
        _ prompt: String,
        for language: String,
        to defaults: UserDefaults = .standard
    ) {
        RomaLocalWhisperPromptCatalog.saveCustomPrompt(prompt, for: language, to: defaults)
        // Editing a model's fallback prompt must not replace the preferred language's prompt.
        if language == RomaTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults) {
            saveLocalWhisperPromptForSelectedLanguage(from: defaults)
        }
    }

    public static func requestPrompt(from defaults: UserDefaults = .standard) -> String? {
        requestPrompt(storedPrompt(from: defaults))
    }

    public static func requestPrompt(
        forEffectiveLanguage language: String,
        from defaults: UserDefaults = .standard
    ) -> String? {
        guard language != RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults) else {
            return requestPrompt(from: defaults)
        }
        return requestPrompt(RomaLocalWhisperPromptCatalog.prompt(
            for: language, customPrompts: RomaLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults)
        ))
    }

    public static func requestPrompt(_ prompt: String?) -> String? {
        RomaTranscriptionPromptUse.nonBlankRequestPrompt(prompt)
    }

    public static func savePrompt(_ prompt: String, to defaults: UserDefaults = .standard) {
        defaults.set(prompt, forKey: RomaUserDefaultsKey.transcriptionPrompt)
    }

    public static func clearPrompt(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.transcriptionPrompt)
    }
}

public enum RomaTranscriptionLanguagePreference {
    // SelectedLanguage stores user intent; model compatibility must never overwrite it.
    public static func storedLanguage(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func selectedLanguage(
        from defaults: UserDefaults = .standard,
        fallback: String = RomaLanguageCatalog.autoDetectCode
    ) -> String {
        storedLanguage(from: defaults) ?? fallback
    }

    public static func selectedMacOSLanguage(from defaults: UserDefaults = .standard) -> String {
        selectedLanguage(
            from: defaults,
            fallback: RomaDefaultSettings.macOS.selectedTranscriptionLanguage
        )
    }

    public static func selectedLanguage(
        source: RomaTranscriptionLanguageSource,
        from defaults: UserDefaults = .standard,
        isMultilingual: Bool = true,
        assemblyAIUsesRealtime: Bool = false
    ) -> String {
        RomaTranscriptionLanguageSupport.validLanguageOrFallback(
            storedLanguage(from: defaults),
            source: source,
            isMultilingual: isMultilingual,
            assemblyAIUsesRealtime: assemblyAIUsesRealtime
        )
    }

    public static func effectiveLanguage(
        for model: RomaTranscriptionLanguageSelectionFacts,
        from defaults: UserDefaults = .standard
    ) -> String {
        model.compatibleLanguage(storedLanguage(from: defaults))
    }

    public static func requestLanguage(
        for model: RomaTranscriptionLanguageSelectionFacts,
        from defaults: UserDefaults = .standard
    ) -> String? {
        RomaTranscriptionLanguageSupport.requestLanguage(effectiveLanguage(for: model, from: defaults))
    }

    public static func saveSelectedLanguage(
        _ language: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(language, forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func clearSelectedLanguage(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func requestLanguage(from defaults: UserDefaults = .standard) -> String? {
        RomaTranscriptionLanguageSupport.requestLanguage(selectedLanguage(from: defaults))
    }
}

public enum RomaCurrentTranscriptionModelPreference {
    static let legacyModelNameKey = "CurrentModel"

    public static func modelName(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: RomaUserDefaultsKey.currentTranscriptionModel)
    }

    public static func saveModelName(_ modelName: String, to defaults: UserDefaults = .standard) {
        defaults.set(modelName, forKey: RomaUserDefaultsKey.currentTranscriptionModel)
    }

    public static func clearModelName(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.currentTranscriptionModel)
        defaults.removeObject(forKey: legacyModelNameKey)
    }

    public static func loadPlan(
        savedModelName: String?,
        candidateModelExists: Bool,
        isCandidateAvailableOnCurrentOS: Bool
    ) -> RomaCurrentTranscriptionModelLoadPlan {
        RomaCurrentTranscriptionModelLoadPlan(
            savedModelName: savedModelName,
            candidateModelExists: candidateModelExists,
            isCandidateAvailableOnCurrentOS: isCandidateAvailableOnCurrentOS
        )
    }
}

fileprivate enum RomaCurrentTranscriptionModelLoadAction: Equatable, Sendable {
    case none
    case restoreSavedModel
    case clearStoredModelName
}

public struct RomaCurrentTranscriptionModelLoadPlan: Equatable, Sendable {
    private let action: RomaCurrentTranscriptionModelLoadAction

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

    public func applyRuntimeState(
        clearStoredModelName: () -> Void,
        restoreSavedModel: () -> Void
    ) {
        switch action {
        case .none:
            break
        case .restoreSavedModel:
            restoreSavedModel()
        case .clearStoredModelName:
            clearStoredModelName()
        }
    }
}

public enum RomaAIEnhancementPreference {
    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RomaUserDefaultsKey.isAIEnhancementEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.isAIEnhancementEnabled)
    }

    public static func statusDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        isEnabled(from: defaults) ? "Enabled" : "Disabled"
    }
}

public enum RomaAIEnhancementContextPreference {
    public static func useClipboardContext(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RomaUserDefaultsKey.useClipboardContext)
    }

    public static func saveUseClipboardContext(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.useClipboardContext)
    }

    public static func useScreenCaptureContext(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RomaUserDefaultsKey.useScreenCaptureContext)
    }

    public static func saveUseScreenCaptureContext(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.useScreenCaptureContext)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.useClipboardContext)
        defaults.removeObject(forKey: RomaUserDefaultsKey.useScreenCaptureContext)
    }
}

public enum RomaAIEnhancementProviderPreference {
    public static let defaultSelectedProvider = RomaAIEnhancementProviderKind.gemini

    public static func selectedProviderRawValue(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: RomaUserDefaultsKey.selectedAIProvider)
    }

    public static func selectedProviderDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        selectedProviderRawValue(from: defaults) ?? "None selected"
    }

    public static func saveSelectedProviderRawValue(_ rawValue: String, to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: RomaUserDefaultsKey.selectedAIProvider)
    }

    public static func saveSelectedProvider(
        _ provider: RomaAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) {
        saveSelectedProviderRawValue(provider.rawValue, to: defaults)
    }

    @discardableResult
    public static func applyProviderSelectionPlan(
        _ plan: RomaAIEnhancementProviderSelectionPlan,
        to defaults: UserDefaults = .standard
    ) -> RomaAIEnhancementProviderKind {
        saveSelectedProvider(plan.selectedProviderToSave, to: defaults)
        return plan.selectedProviderToSave
    }

    public static func selectedProvider(
        default defaultProvider: RomaAIEnhancementProviderKind = RomaAIEnhancementProviderPreference.defaultSelectedProvider,
        from defaults: UserDefaults = .standard
    ) -> RomaAIEnhancementProviderKind {
        guard let storedProvider = selectedProviderRawValue(from: defaults),
              let provider = RomaAIEnhancementProviderKind(storedValue: storedProvider)
        else {
            return defaultProvider
        }

        if storedProvider != provider.rawValue {
            saveSelectedProviderRawValue(provider.rawValue, to: defaults)
        }

        return provider
    }

    public static func selectedModels(
        for providers: [RomaAIEnhancementProviderKind] = RomaAIEnhancementProviderKind.allCases,
        from defaults: UserDefaults = .standard
    ) -> [RomaAIEnhancementProviderKind: String] {
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
        let savedModel = defaults.string(forKey: RomaUserDefaultsKey.selectedAIProviderModel(providerRawValue))
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
        defaults.set(model, forKey: RomaUserDefaultsKey.selectedAIProviderModel(providerRawValue))
    }

    public static func saveSelectedModel(
        _ model: String,
        for provider: RomaAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) {
        saveSelectedModel(model, for: provider.rawValue, to: defaults)
    }

    @discardableResult
    public static func applyModelSelectionPlan(
        _ plan: RomaAIEnhancementModelSelectionPlan,
        to defaults: UserDefaults = .standard
    ) -> String {
        saveSelectedModel(plan.selectedModelToSave, for: plan.provider, to: defaults)
        return plan.selectedModelToSave
    }

    @discardableResult
    public static func applyModelRefreshPlan(
        _ plan: RomaAIEnhancementModelRefreshPlan,
        for provider: RomaAIEnhancementProviderKind,
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
        providers: [RomaAIEnhancementProviderKind] = RomaAIEnhancementProviderKind.allCases
    ) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.selectedAIProvider)
        providers.forEach {
            defaults.removeObject(forKey: RomaUserDefaultsKey.selectedAIProviderModel($0.rawValue))
        }
    }
}

public enum RomaDynamicAIProviderPreference {
    public static let defaultOllamaBaseURL = RomaPreferenceDefault.ollamaBaseURL
    public static let defaultOllamaRuntimeSelectedModel = RomaAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback

    public static func ollamaBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = defaultOllamaBaseURL
    ) -> String {
        defaults.string(forKey: RomaUserDefaultsKey.ollamaBaseURL) ?? fallback
    }

    public static func saveOllamaBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: RomaUserDefaultsKey.ollamaBaseURL)
    }

    public static func ollamaSelectedModel(
        from defaults: UserDefaults = .standard,
        fallback: String
    ) -> String {
        defaults.string(forKey: RomaUserDefaultsKey.ollamaSelectedModel) ?? fallback
    }

    public static func ollamaRuntimeSelectedModel(from defaults: UserDefaults = .standard) -> String {
        ollamaSelectedModel(from: defaults, fallback: defaultOllamaRuntimeSelectedModel)
    }

    public static func saveOllamaSelectedModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: RomaUserDefaultsKey.ollamaSelectedModel)
    }

    @discardableResult
    public static func applyOllamaModelRefreshPlan(
        _ plan: RomaAIEnhancementModelRefreshPlan,
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
        defaults.string(forKey: RomaUserDefaultsKey.customProviderBaseURL) ?? fallback
    }

    public static func saveCustomProviderBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: RomaUserDefaultsKey.customProviderBaseURL)
    }

    public static func customProviderModel(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: RomaUserDefaultsKey.customProviderModel) ?? fallback
    }

    public static func saveCustomProviderModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: RomaUserDefaultsKey.customProviderModel)
    }

    public static func openRouterModels(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: RomaUserDefaultsKey.openRouterModels) ?? []
    }

    public static func saveOpenRouterModels(_ models: [String], to defaults: UserDefaults = .standard) {
        defaults.set(models, forKey: RomaUserDefaultsKey.openRouterModels)
    }

    @discardableResult
    public static func applyOpenRouterModelRefreshPlan(
        _ plan: RomaAIEnhancementModelRefreshPlan,
        to defaults: UserDefaults = .standard
    ) -> String? {
        saveOpenRouterModels(plan.refreshedModelNames, to: defaults)
        return RomaAIEnhancementProviderPreference.applyModelRefreshPlan(
            plan,
            for: .openRouter,
            to: defaults
        )
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.ollamaBaseURL)
        defaults.removeObject(forKey: RomaUserDefaultsKey.ollamaSelectedModel)
        defaults.removeObject(forKey: RomaUserDefaultsKey.customProviderBaseURL)
        defaults.removeObject(forKey: RomaUserDefaultsKey.customProviderModel)
        defaults.removeObject(forKey: RomaUserDefaultsKey.openRouterModels)
    }
}

public enum RomaFillerWordPreference {
    public static func words(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: RomaUserDefaultsKey.fillerWords) ?? RomaFillerWords.defaultWords
    }

    public static func saveWords(_ words: [String], to defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: RomaUserDefaultsKey.fillerWords)
    }

    public static func clearWords(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.fillerWords)
    }
}

public enum RomaWordReplacementPreference {
    public static func rules(from defaults: UserDefaults = .standard) -> [RomaWordReplacementRule] {
        guard let data = defaults.data(forKey: RomaUserDefaultsKey.wordReplacements) else {
            return []
        }

        return (try? JSONDecoder().decode([RomaWordReplacementRule].self, from: data)) ?? []
    }

    public static func saveRules(_ rules: [RomaWordReplacementRule], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }

        defaults.set(data, forKey: RomaUserDefaultsKey.wordReplacements)
    }

    public static func clearRules(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.wordReplacements)
    }
}

public enum RomaCustomVocabularyPreference {
    public static func terms(from defaults: UserDefaults = .standard) -> [String] {
        RomaCustomVocabularyTerms.normalized(
            defaults.stringArray(forKey: RomaUserDefaultsKey.customVocabularyTerms) ?? []
        )
    }

    public static func saveTerms(_ terms: [String], to defaults: UserDefaults = .standard) {
        defaults.set(
            RomaCustomVocabularyTerms.normalized(terms),
            forKey: RomaUserDefaultsKey.customVocabularyTerms
        )
    }

    public static func clearTerms(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.customVocabularyTerms)
    }
}

public enum RomaAIEnhancementRequestPreference {
    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.integer(forKey: RomaUserDefaultsKey.enhancementTimeoutSeconds)
        return stored > 0
            ? TimeInterval(stored)
            : TimeInterval(RomaPreferenceDefault.enhancementTimeoutSeconds)
    }

    public static func shouldRetryOnTimeout(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: RomaUserDefaultsKey.enhancementRetryOnTimeout) as? Bool
            ?? RomaPreferenceDefault.enhancementRetryOnTimeout
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.removeObject(forKey: RomaUserDefaultsKey.enhancementRetryOnTimeout)
    }
}

public struct RomaTranscriptionAutoCleanupConfiguration: Equatable, Sendable {
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

    private var completionAction: RomaTranscriptionAutoCleanupCompletionAction {
        guard isEnabled else { return .ignore }
        return shouldDeleteCompletedTranscriptionImmediately
            ? .deleteCompletedTranscription
            : .sweepOldTranscriptions
    }

    public func applyCompletionRuntimeState(
        ignore: () -> Void,
        sweepOldTranscriptions: () -> Void,
        deleteCompletedTranscription: () -> Void
    ) {
        switch completionAction {
        case .ignore:
            ignore()
        case .sweepOldTranscriptions:
            sweepOldTranscriptions()
        case .deleteCompletedTranscription:
            deleteCompletedTranscription()
        }
    }
}

fileprivate enum RomaTranscriptionAutoCleanupCompletionAction: Equatable, Sendable {
    case ignore
    case sweepOldTranscriptions
    case deleteCompletedTranscription
}

public struct RomaTranscriptionAutoCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionMinutes: Int?

    public init(isEnabled: Bool?, retentionMinutes: Int?) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }
}

public struct RomaTranscriptionAutoCleanupBackupImportPlan: Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionMinutes: Int?

    public init(isEnabled: Bool?, retentionMinutes: Int?) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }
}

public enum RomaTranscriptionAutoCleanupPreference {
    public static func current(from defaults: UserDefaults = .standard) -> RomaTranscriptionAutoCleanupConfiguration {
        RomaTranscriptionAutoCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionMinutes: retentionMinutes(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RomaUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func retentionMinutes(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: RomaUserDefaultsKey.transcriptionRetentionMinutes) as? Int
            ?? RomaPreferenceDefault.transcriptionRetentionMinutes
    }

    public static func saveRetentionMinutes(_ minutes: Int, to defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: RomaUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.removeObject(forKey: RomaUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func backupPreferences(
        from configuration: RomaTranscriptionAutoCleanupConfiguration
    ) -> RomaTranscriptionAutoCleanupBackupPreferences {
        RomaTranscriptionAutoCleanupBackupPreferences(
            isEnabled: configuration.isEnabled,
            retentionMinutes: configuration.retentionMinutes
        )
    }

    public static func backupImportPlan(
        from preferences: RomaTranscriptionAutoCleanupBackupPreferences
    ) -> RomaTranscriptionAutoCleanupBackupImportPlan {
        RomaTranscriptionAutoCleanupBackupImportPlan(
            isEnabled: preferences.isEnabled,
            retentionMinutes: preferences.retentionMinutes
        )
    }
}

public enum RomaTranscriptionAutoCleanupDiagnostics {
    public static let invalidCompletedTranscriptionMessage = "Invalid transcription or missing model context"

    public static func saveAfterCompletedDeletionFailedMessage(errorDescription: String) -> String {
        "Failed to save after transcription deletion: \(errorDescription)"
    }

    public static func oldTranscriptionsCleanedMessage(deletedCount: Int) -> String {
        "Cleaned up \(deletedCount) old transcription(s)"
    }

    public static func transcriptionCleanupFailedMessage(errorDescription: String) -> String {
        "Failed during transcription cleanup: \(errorDescription)"
    }

    public static func orphanAudioFilesCleanedMessage(deletedCount: Int) -> String {
        "Cleaned up \(deletedCount) orphan audio file(s)"
    }

    public static func orphanAudioCleanupFailedMessage(errorDescription: String) -> String {
        "Failed during orphan audio cleanup: \(errorDescription)"
    }
}

public struct RomaAudioCleanupConfiguration: Equatable, Sendable {
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

public struct RomaAudioCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionDays: Int?

    public init(isEnabled: Bool?, retentionDays: Int?) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }
}

public struct RomaAudioCleanupBackupImportPlan: Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionDays: Int?

    public init(isEnabled: Bool?, retentionDays: Int?) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }
}

public enum RomaAudioCleanupPreference {
    public static let cleanupCheckInterval: TimeInterval = 86_400

    public static func current(from defaults: UserDefaults = .standard) -> RomaAudioCleanupConfiguration {
        RomaAudioCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionDays: retentionDays(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RomaUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func retentionDays(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: RomaUserDefaultsKey.audioRetentionPeriodDays) as? Int
            ?? RomaPreferenceDefault.audioRetentionDays
    }

    public static func saveRetentionDays(_ days: Int, to defaults: UserDefaults = .standard) {
        defaults.set(days, forKey: RomaUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.isAudioCleanupEnabled)
        defaults.removeObject(forKey: RomaUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func backupPreferences(
        from configuration: RomaAudioCleanupConfiguration
    ) -> RomaAudioCleanupBackupPreferences {
        RomaAudioCleanupBackupPreferences(
            isEnabled: configuration.isEnabled,
            retentionDays: configuration.retentionDays
        )
    }

    public static func backupImportPlan(
        from preferences: RomaAudioCleanupBackupPreferences
    ) -> RomaAudioCleanupBackupImportPlan {
        RomaAudioCleanupBackupImportPlan(
            isEnabled: preferences.isEnabled,
            retentionDays: preferences.retentionDays
        )
    }
}

public enum RomaModelRuntimePreference {
    public static let userDefaultsKey = RomaUserDefaultsKey.prewarmModelOnWake
    public static let defaultShouldPrewarmModelOnWake = RomaPreferenceDefault.prewarmModelOnWake
    public static let prewarmScheduleDelay: Duration = .seconds(3)
    public static let settingsPresentation = RomaMacOSAdvancedTranscriptionSettingsPresentation.macOS.modelPrewarm
    public static let macOSSettingsPresentation = settingsPresentation

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

public enum RomaRecorderPreviewPreference {
    public static let userDefaultsKey = RomaUserDefaultsKey.showLiveTextPreview
    public static let defaultIsLiveTextPreviewEnabled = RomaPreferenceDefault.showLiveTextPreview
    public static let macOSSettingsPresentation = RomaMacOSAdvancedTranscriptionSettingsPresentation.macOS.liveTextPreview

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

public enum RomaRecordingShortcutSlot: Sendable {
    case primary
    case secondary
}

public enum RomaRecordingShortcutSelection: String, CaseIterable, Sendable {
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

public enum RomaRecordingShortcutMode: String, CaseIterable, Sendable {
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

public struct RomaShortcutPressContext: Equatable, Sendable {
    public var didPressOtherKeyDuringPress: Bool
    public var didReleaseOtherKeyDuringPress: Bool
    public var hasReliableKeyEvidence: Bool

    public init(
        didPressOtherKeyDuringPress: Bool = false,
        didReleaseOtherKeyDuringPress: Bool = false,
        hasReliableKeyEvidence: Bool = true
    ) {
        self.didPressOtherKeyDuringPress = didPressOtherKeyDuringPress
        self.didReleaseOtherKeyDuringPress = didReleaseOtherKeyDuringPress
        self.hasReliableKeyEvidence = hasReliableKeyEvidence
    }
}

public enum RomaSpecialShortcutKeyEvidencePolicy {
    public static func shouldDiscardShortcut(for context: RomaShortcutPressContext) -> Bool {
        context.didPressOtherKeyDuringPress ||
        context.didReleaseOtherKeyDuringPress ||
        !context.hasReliableKeyEvidence
    }
}

public enum RomaShortcutInterruptionPolicy {
    public static let interruptionWindow: TimeInterval = 1.0

    public static func isWithinInterruptionWindow(pressedAt: TimeInterval, eventTime: TimeInterval) -> Bool {
        eventTime - pressedAt <= interruptionWindow
    }
}

public enum RomaRecordingShortcutTimingPolicy {
    public static let pressCooldown: TimeInterval = 0.08
    public static let hybridPushToTalkThreshold: TimeInterval = 0.5

    public static func isPressWithinCooldown(
        lastPressTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastPressTime else { return false }
        return now.timeIntervalSince(lastPressTime) < pressCooldown
    }

    public static func shouldStopHybridRecording(
        pressDuration: TimeInterval,
        recordingState: RomaRecordingState
    ) -> Bool {
        pressDuration >= hybridPushToTalkThreshold && recordingState == .recording
    }

    public static func sleepNanoseconds(delaySeconds: TimeInterval) -> UInt64 {
        guard delaySeconds.isFinite else { return 0 }
        let safeDelay = max(delaySeconds, 0)
        let nanoseconds = (safeDelay * 1_000_000_000).rounded()
        guard nanoseconds.isFinite, nanoseconds < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(nanoseconds)
    }
}

public enum RomaSpecialShortcutEmptyFallbackPolicy {
    public static let emptyTapThreshold: TimeInterval = 0.32
    public static let fallbackLifetime: TimeInterval = 30

    public static func shouldScheduleFallback(
        pressDuration: TimeInterval,
        threshold: TimeInterval = emptyTapThreshold
    ) -> Bool {
        pressDuration < threshold
    }

    public static func shouldConsumeFallback(
        createdAt: Date,
        now: Date = Date(),
        transcriptionStatus: RomaTranscriptionStatus?,
        rawText: String,
        enhancedText: String?,
        lifetime: TimeInterval = fallbackLifetime
    ) -> Bool {
        guard now.timeIntervalSince(createdAt) <= lifetime else { return false }
        guard transcriptionStatus == .completed else { return false }
        guard rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard enhancedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return false }
        return true
    }
}

public enum RomaShortcutActionIdentifier: Hashable, Sendable {
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

    public var recordingShortcutSlot: RomaRecordingShortcutSlot? {
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
        recordingShortcutSlot.map(RomaRecordingShortcutPreference.selectionKey(for:)) ?? shortcutStorageKey
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
        recordingShortcutSlot.map(RomaRecordingShortcutPreference.modeKey(for:)) ?? shortcutStorageKey
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

public enum RomaShortcutActionPresentation {
    public static let primaryRecordingDisplayName = "Primary Shortcut"
    public static let secondaryRecordingDisplayName = "Secondary Shortcut"
    public static let pasteLastTranscriptionDisplayName = "Paste Last Transcription"
    public static let pasteLastEnhancementDisplayName = "Paste Last Enhanced Transcription"
    public static let retryLastTranscriptionDisplayName = "Retry Last Transcription"
    public static let cancelRecorderDisplayName = "Cancel Recording"
    public static let openHistoryWindowDisplayName = RomaHistoryPresentation.macOSShortcutTip.shortcutLabel
    public static let quickAddToDictionaryDisplayName = "Quick Add to Dictionary"
    public static let toggleEnhancementDisplayName = "Toggle Enhancement"
    public static let fallbackPowerModeDisplayName = "Power Mode"
    public static let miniRecorderEscapeDisplayName = "Mini Recorder Cancel"

    public static func displayName(
        for identifier: RomaShortcutActionIdentifier,
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

public enum RomaShortcutValidationIssue: Equatable, Sendable {
    case plainKeyRequiresModifier
    case shiftTypingKeyRequiresAdditionalModifier
    case reservedBySystem
    case alreadyUsedBy(String)
}

public enum RomaShortcutValidationPresentation {
    public static func notificationTitle(
        for issue: RomaShortcutValidationIssue,
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

public struct RomaMacOSShortcutNotificationPresentation: Equatable, Sendable {
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

public enum RomaMiniRecorderEscapeShortcutPolicy {
    public static let doublePressThreshold: TimeInterval = 1.5

    public static var confirmationPresentation: RomaMacOSShortcutNotificationPresentation {
        RomaMacOSShortcutNotificationPresentation.miniRecorderEscapeConfirmation(
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
        RomaRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: threshold)
    }
}

public enum RomaLegacyRecordingShortcutPreset: String, CaseIterable, Sendable {
    case rightOption
    case leftOption
    case leftControl
    case rightControl
    case fn
    case rightCommand
    case rightShift
    case leftShift
}

public struct RomaMacOSRecordingShortcutSettingsPresentation: Equatable, Sendable {
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

    public static let macOS = RomaMacOSRecordingShortcutSettingsPresentation(
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

public struct RomaMacOSShortcutRecorderPresentation: Equatable, Sendable {
    public let recordingPlaceholderText: String
    public let idleAccessibilityLabel: String
    public let idleButtonText: String

    public static let macOS = RomaMacOSShortcutRecorderPresentation(
        recordingPlaceholderText: "Press shortcut",
        idleAccessibilityLabel: "Record shortcut",
        idleButtonText: "Record"
    )
}

public struct RomaRecordingShortcutBackupPreferences: Codable, Equatable, Sendable {
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

public struct RomaRecordingShortcutBackupImportPlan: Equatable, Sendable {
    private let primaryRecordingShortcut: RomaRecordingShortcutSelection?
    private let secondaryRecordingShortcut: RomaRecordingShortcutSelection?
    private let primaryRecordingShortcutMode: RomaRecordingShortcutMode?
    private let secondaryRecordingShortcutMode: RomaRecordingShortcutMode?
    private let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    private let isMiddleClickToggleEnabled: Bool?
    private let middleClickActivationDelay: Int?

    public init(
        primaryRecordingShortcut: RomaRecordingShortcutSelection?,
        secondaryRecordingShortcut: RomaRecordingShortcutSelection?,
        primaryRecordingShortcutMode: RomaRecordingShortcutMode?,
        secondaryRecordingShortcutMode: RomaRecordingShortcutMode?,
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

    public func applyRuntimeState(
        setPrimaryRecordingShortcut: (RomaRecordingShortcutSelection) -> Void,
        setSecondaryRecordingShortcut: (RomaRecordingShortcutSelection) -> Void,
        setPrimaryRecordingShortcutMode: (RomaRecordingShortcutMode) -> Void,
        setSecondaryRecordingShortcutMode: (RomaRecordingShortcutMode) -> Void,
        setSpecialShortcutPasteLastTranscriptOnEmptyTap: (Bool) -> Void,
        setMiddleClickToggleEnabled: (Bool) -> Void,
        setMiddleClickActivationDelay: (Int) -> Void
    ) {
        if let primaryRecordingShortcut {
            setPrimaryRecordingShortcut(primaryRecordingShortcut)
        }
        if let secondaryRecordingShortcut {
            setSecondaryRecordingShortcut(secondaryRecordingShortcut)
        }
        if let primaryRecordingShortcutMode {
            setPrimaryRecordingShortcutMode(primaryRecordingShortcutMode)
        }
        if let secondaryRecordingShortcutMode {
            setSecondaryRecordingShortcutMode(secondaryRecordingShortcutMode)
        }
        if let specialShortcutPasteLastTranscriptOnEmptyTap {
            setSpecialShortcutPasteLastTranscriptOnEmptyTap(specialShortcutPasteLastTranscriptOnEmptyTap)
        }
        if let isMiddleClickToggleEnabled {
            setMiddleClickToggleEnabled(isMiddleClickToggleEnabled)
        }
        if let middleClickActivationDelay {
            setMiddleClickActivationDelay(middleClickActivationDelay)
        }
    }
}

public struct RomaShortcutBackupImport: Equatable, Sendable {
    public let actionIdentifier: RomaShortcutActionIdentifier
    public let recordingShortcutSlot: RomaRecordingShortcutSlot?
    public let recordingShortcutSelection: RomaRecordingShortcutSelection?

    public init(
        actionIdentifier: RomaShortcutActionIdentifier,
        recordingShortcutSlot: RomaRecordingShortcutSlot?,
        recordingShortcutSelection: RomaRecordingShortcutSelection?
    ) {
        self.actionIdentifier = actionIdentifier
        self.recordingShortcutSlot = recordingShortcutSlot
        self.recordingShortcutSelection = recordingShortcutSelection
    }
}

public enum RomaShortcutBackupPolicy {
    public static let generalBackupShortcutActionIdentifiers: [RomaShortcutActionIdentifier] = [
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
        availableActionIdentifiers: Set<RomaShortcutActionIdentifier>
    ) -> [RomaShortcutActionIdentifier] {
        generalBackupShortcutActionIdentifiers.filter(availableActionIdentifiers.contains)
    }

    public static func generalBackupShortcutRecords<ShortcutBackup>(
        backupForActionIdentifier: (RomaShortcutActionIdentifier) -> ShortcutBackup?
    ) -> [RomaShortcutActionIdentifier: ShortcutBackup] {
        let candidates = generalBackupShortcutActionIdentifiers
            .reduce(into: [RomaShortcutActionIdentifier: ShortcutBackup]()) { records, actionIdentifier in
                guard let backup = backupForActionIdentifier(actionIdentifier) else {
                    return
                }
                records[actionIdentifier] = backup
            }

        return generalBackupShortcutExportPlan(
            availableActionIdentifiers: Set(candidates.keys)
        ).reduce(into: [RomaShortcutActionIdentifier: ShortcutBackup]()) { records, actionIdentifier in
            records[actionIdentifier] = candidates[actionIdentifier]
        }
    }

    public static func generalBackupShortcutImportPlan(
        importedActionIdentifiers: Set<RomaShortcutActionIdentifier>
    ) -> [RomaShortcutBackupImport] {
        generalBackupShortcutActionIdentifiers.compactMap { actionIdentifier in
            guard importedActionIdentifiers.contains(actionIdentifier) else {
                return nil
            }

            let slot = actionIdentifier.recordingShortcutSlot
            return RomaShortcutBackupImport(
                actionIdentifier: actionIdentifier,
                recordingShortcutSlot: slot,
                recordingShortcutSelection: slot == nil ? nil : .custom
            )
        }
    }
}

public struct RomaShortcutStorageState: Equatable, Sendable {
    public let shortcutData: Data?
    public let clearedValue: Bool?

    public init(shortcutData: Data?, clearedValue: Bool?) {
        self.shortcutData = shortcutData
        self.clearedValue = clearedValue
    }
}

public struct RomaRecordingShortcutSelectionMigrationPlan: Equatable, Sendable {
    public let selection: RomaRecordingShortcutSelection
    public let destinationKey: String?
    public let legacyKeyToRemove: String?
    public let presetToStore: RomaLegacyRecordingShortcutPreset?
    public let defaultPresetToStore: RomaLegacyRecordingShortcutPreset?

    public init(
        selection: RomaRecordingShortcutSelection,
        destinationKey: String?,
        legacyKeyToRemove: String?,
        presetToStore: RomaLegacyRecordingShortcutPreset?,
        defaultPresetToStore: RomaLegacyRecordingShortcutPreset?
    ) {
        self.selection = selection
        self.destinationKey = destinationKey
        self.legacyKeyToRemove = legacyKeyToRemove
        self.presetToStore = presetToStore
        self.defaultPresetToStore = defaultPresetToStore
    }
}

public enum RomaShortcutStoragePreference {
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
    ) -> RomaShortcutStorageState {
        let clearedKey = clearedKey(for: shortcutKey)
        return RomaShortcutStorageState(
            shortcutData: shortcutData(for: shortcutKey, from: defaults),
            clearedValue: defaults.object(forKey: clearedKey) == nil ? nil : defaults.bool(forKey: clearedKey)
        )
    }

    public static func restoreStoredState(
        _ state: RomaShortcutStorageState,
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

public enum RomaRecordingShortcutPreference {
    public static let legacyKeyboardShortcutsMigrationKey = "Shortcut_LegacyKeyboardShortcutsMigrated"
    public static let legacyCustomRecordingShortcutsMigrationKey = "Shortcut_LegacyCustomRecordingShortcutsMigrated"
    public static let minimumMiddleClickActivationDelay = 0
    public static let shortcutDidChangeNotificationName = Notification.Name("ShortcutStoreShortcutDidChange")
    public static let shortcutRecordingDidStartNotificationName = Notification.Name("ShortcutRecorderRecordingDidStart")

    public static let macOSSettingsPresentation = RomaMacOSRecordingShortcutSettingsPresentation.macOS
    public static let macOSRecorderPresentation = RomaMacOSShortcutRecorderPresentation.macOS

    public static var registeredDefaults: [String: Any] {
        [
            RomaUserDefaultsKey.isMiddleClickToggleEnabled: RomaPreferenceDefault.isMiddleClickToggleEnabled,
            RomaUserDefaultsKey.middleClickActivationDelay: RomaPreferenceDefault.middleClickActivationDelay,
            RomaUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap: RomaPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
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
        for action: RomaShortcutActionIdentifier,
        allowsNone: Bool,
        from defaults: UserDefaults = .standard
    ) -> RomaRecordingShortcutSelectionMigrationPlan {
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
            return RomaRecordingShortcutSelectionMigrationPlan(
                selection: .none,
                destinationKey: nil,
                legacyKeyToRemove: nil,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        let slot = action.recordingShortcutSlot ?? .primary
        return RomaRecordingShortcutSelectionMigrationPlan(
            selection: defaultSelection(for: slot),
            destinationKey: destinationKey,
            legacyKeyToRemove: nil,
            presetToStore: nil,
            defaultPresetToStore: action == .primaryRecording ? .leftShift : nil
        )
    }

    public static func applyShortcutSelectionMigrationPlan(
        _ plan: RomaRecordingShortcutSelectionMigrationPlan,
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
        for action: RomaShortcutActionIdentifier,
        in defaults: UserDefaults = .standard
    ) -> RomaRecordingShortcutMode {
        let destinationKey = action.modeKey
        let legacyKey = action.legacyModeKey
        let legacyKeyToRemove = legacyKey == destinationKey ? nil : legacyKey

        if let storedValue = nonEmptyString(forKey: destinationKey, from: defaults),
           let mode = RomaRecordingShortcutMode(rawValue: storedValue) {
            if let legacyKeyToRemove {
                defaults.removeObject(forKey: legacyKeyToRemove)
            }
            return mode
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey, from: defaults),
           let mode = RomaRecordingShortcutMode(rawValue: legacyValue) {
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
        for action: RomaShortcutActionIdentifier,
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: action.legacyCustomRecordingShortcutKey)
    }

    public static func removeLegacyKeyboardShortcut(
        for action: RomaShortcutActionIdentifier,
        from defaults: UserDefaults = .standard
    ) {
        guard let key = action.legacyKeyboardShortcutStorageKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func selectionKey(for slot: RomaRecordingShortcutSlot) -> String {
        switch slot {
        case .primary:
            return RomaUserDefaultsKey.primaryRecordingShortcut
        case .secondary:
            return RomaUserDefaultsKey.secondaryRecordingShortcut
        }
    }

    public static func modeKey(for slot: RomaRecordingShortcutSlot) -> String {
        switch slot {
        case .primary:
            return RomaUserDefaultsKey.primaryRecordingShortcutMode
        case .secondary:
            return RomaUserDefaultsKey.secondaryRecordingShortcutMode
        }
    }

    public static func defaultSelection(for slot: RomaRecordingShortcutSlot) -> RomaRecordingShortcutSelection {
        switch slot {
        case .primary:
            return .custom
        case .secondary:
            return .none
        }
    }

    public static func defaultMode(for slot: RomaRecordingShortcutSlot) -> RomaRecordingShortcutMode {
        switch slot {
        case .primary:
            return .special
        case .secondary:
            return .hybrid
        }
    }

    public static func backupPreferences(
        primaryRecordingShortcut: RomaRecordingShortcutSelection,
        secondaryRecordingShortcut: RomaRecordingShortcutSelection,
        primaryRecordingShortcutMode: RomaRecordingShortcutMode,
        secondaryRecordingShortcutMode: RomaRecordingShortcutMode,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool,
        isMiddleClickToggleEnabled: Bool,
        middleClickActivationDelay: Int
    ) -> RomaRecordingShortcutBackupPreferences {
        RomaRecordingShortcutBackupPreferences(
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
        from backup: RomaRecordingShortcutBackupPreferences
    ) -> RomaRecordingShortcutBackupImportPlan {
        RomaRecordingShortcutBackupImportPlan(
            primaryRecordingShortcut: backup.primaryRecordingShortcutRawValue.flatMap(RomaRecordingShortcutSelection.init(rawValue:)),
            secondaryRecordingShortcut: backup.secondaryRecordingShortcutRawValue.flatMap(RomaRecordingShortcutSelection.init(rawValue:)),
            primaryRecordingShortcutMode: backup.primaryRecordingShortcutModeRawValue.flatMap(RomaRecordingShortcutMode.init(rawValue:)),
            secondaryRecordingShortcutMode: backup.secondaryRecordingShortcutModeRawValue.flatMap(RomaRecordingShortcutMode.init(rawValue:)),
            specialShortcutPasteLastTranscriptOnEmptyTap: backup.specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: backup.isMiddleClickToggleEnabled,
            middleClickActivationDelay: backup.middleClickActivationDelay.map(Self.normalizedMiddleClickActivationDelay)
        )
    }

    public static func selection(
        for slot: RomaRecordingShortcutSlot,
        from defaults: UserDefaults = .standard
    ) -> RomaRecordingShortcutSelection? {
        defaults.string(forKey: selectionKey(for: slot)).flatMap(RomaRecordingShortcutSelection.init(rawValue:))
    }

    public static func saveSelection(
        _ selection: RomaRecordingShortcutSelection,
        for slot: RomaRecordingShortcutSlot,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(selection.rawValue, forKey: selectionKey(for: slot))
    }

    public static func mode(
        for slot: RomaRecordingShortcutSlot,
        from defaults: UserDefaults = .standard
    ) -> RomaRecordingShortcutMode {
        defaults.string(forKey: modeKey(for: slot)).flatMap(RomaRecordingShortcutMode.init(rawValue:))
            ?? defaultMode(for: slot)
    }

    public static func saveMode(
        _ mode: RomaRecordingShortcutMode,
        for slot: RomaRecordingShortcutSlot,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: modeKey(for: slot))
    }

    public static func isMiddleClickToggleEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: RomaUserDefaultsKey.isMiddleClickToggleEnabled) as? Bool
            ?? RomaPreferenceDefault.isMiddleClickToggleEnabled
    }

    public static func saveMiddleClickToggleEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.isMiddleClickToggleEnabled)
    }

    public static func middleClickActivationDelay(from defaults: UserDefaults = .standard) -> Int {
        normalizedMiddleClickActivationDelay(
            defaults.object(forKey: RomaUserDefaultsKey.middleClickActivationDelay) as? Int
                ?? RomaPreferenceDefault.middleClickActivationDelay
        )
    }

    public static func saveMiddleClickActivationDelay(
        _ delay: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(
            normalizedMiddleClickActivationDelay(delay),
            forKey: RomaUserDefaultsKey.middleClickActivationDelay
        )
    }

    public static func normalizedMiddleClickActivationDelay(_ delay: Int) -> Int {
        max(delay, minimumMiddleClickActivationDelay)
    }

    public static func middleClickActivationDelayFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: minimumMiddleClickActivationDelay)
        return formatter
    }

    public static func shouldPasteLastTranscriptOnEmptyTap(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: RomaUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap) as? Bool
            ?? RomaPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
    }

    public static func saveShouldPasteLastTranscriptOnEmptyTap(
        _ shouldPaste: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPaste, forKey: RomaUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.primaryRecordingShortcut)
        defaults.removeObject(forKey: RomaUserDefaultsKey.secondaryRecordingShortcut)
        defaults.removeObject(forKey: RomaUserDefaultsKey.primaryRecordingShortcutMode)
        defaults.removeObject(forKey: RomaUserDefaultsKey.secondaryRecordingShortcutMode)
        defaults.removeObject(forKey: RomaUserDefaultsKey.isMiddleClickToggleEnabled)
        defaults.removeObject(forKey: RomaUserDefaultsKey.middleClickActivationDelay)
        defaults.removeObject(forKey: RomaUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap)
    }

    private static func shortcutSelectionMigrationPlan(
        from rawValue: String,
        destinationKey: String,
        legacyKeyToRemove: String?,
        allowsNone: Bool
    ) -> RomaRecordingShortcutSelectionMigrationPlan {
        if rawValue == RomaRecordingShortcutSelection.custom.rawValue {
            return RomaRecordingShortcutSelectionMigrationPlan(
                selection: .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        if rawValue == RomaRecordingShortcutSelection.none.rawValue {
            return RomaRecordingShortcutSelectionMigrationPlan(
                selection: allowsNone ? .none : .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        if let preset = RomaLegacyRecordingShortcutPreset(rawValue: rawValue) {
            return RomaRecordingShortcutSelectionMigrationPlan(
                selection: .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: preset,
                defaultPresetToStore: nil
            )
        }

        return RomaRecordingShortcutSelectionMigrationPlan(
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

public enum RomaSharedPreferenceReset {
    public static func clearCoreUserSettings(
        from defaults: UserDefaults = .standard,
        providers: [RomaProviderKind] = RomaProviderKind.userAPIKeyProviders
    ) {
        RomaModeStorage.clear(from: defaults)
        RomaOnboardingPreference.clear(from: defaults)
        RomaProviderAPIKeyVerificationState.clearAll(from: providers, in: defaults)
        RomaAudioSessionTimeoutPreference.clear(from: defaults)
        RomaVADPreference.clear(from: defaults)
        RomaTranscriptionPromptPreference.clearPrompt(from: defaults)
        PunctuationCleanupMode.clearCurrent(in: defaults)
        RomaTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)
        RomaFillerWordPreference.clearWords(from: defaults)
        RomaWordReplacementPreference.clearRules(from: defaults)
        RomaCustomVocabularyPreference.clearTerms(from: defaults)
        RomaDictionaryListSortPreference.clear(from: defaults)
        RomaTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)
        RomaCurrentTranscriptionModelPreference.clearModelName(from: defaults)
        RomaAIEnhancementProviderPreference.clear(from: defaults)
        RomaDynamicAIProviderPreference.clear(from: defaults)
        RomaLocalCLIPreference.clear(from: defaults)
        RomaAIEnhancementRequestPreference.clear(from: defaults)
        RomaTranscriptionAutoCleanupPreference.clear(from: defaults)
        RomaAudioCleanupPreference.clear(from: defaults)
        RomaAudioPlaybackRate.clear(from: defaults)
        RomaCustomPromptStorage.clear(from: defaults)
        RomaAIEnhancementContextPreference.clear(from: defaults)
        RomaPowerModePreference.clear(from: defaults)
        RomaPowerModeConfigurationPreference.clear(from: defaults)
        RomaPowerModeSessionPreference.clear(from: defaults)
        RomaModelRuntimePreference.clear(from: defaults)
        RomaRecorderPreviewPreference.clear(from: defaults)
        RomaRecordingShortcutPreference.clear(from: defaults)
        RomaAudioInputPreference.clearLastUsedMicrophoneDeviceID(from: defaults)
    }
}

public enum RomaModeStorage {
    public static func saveModes(
        _ modes: [Mode],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(modes) {
            defaults.set(data, forKey: RomaUserDefaultsKey.modes)
        }
    }

    public static func loadModes(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [Mode] {
        guard let data = defaults.data(forKey: RomaUserDefaultsKey.modes),
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
            defaults.set(selectedModeId.uuidString, forKey: RomaUserDefaultsKey.selectedModeId)
        } else {
            defaults.removeObject(forKey: RomaUserDefaultsKey.selectedModeId)
        }
    }

    public static func loadSelectedModeId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: RomaUserDefaultsKey.selectedModeId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.modes)
        defaults.removeObject(forKey: RomaUserDefaultsKey.selectedModeId)
    }
}

public enum RomaPowerModeConfigurationPreference {
    public static func saveConfigurations(
        _ configurations: [PowerModeConfig],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(configurations) {
            defaults.set(data, forKey: RomaUserDefaultsKey.powerModeConfigurations)
        }
    }

    public static func loadConfigurations(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [PowerModeConfig] {
        guard let data = defaults.data(forKey: RomaUserDefaultsKey.powerModeConfigurations),
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
            defaults.set(id.uuidString, forKey: RomaUserDefaultsKey.activePowerModeConfigurationId)
        } else {
            defaults.removeObject(forKey: RomaUserDefaultsKey.activePowerModeConfigurationId)
        }
    }

    public static func loadActiveConfigurationId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: RomaUserDefaultsKey.activePowerModeConfigurationId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.powerModeConfigurations)
        defaults.removeObject(forKey: RomaUserDefaultsKey.activePowerModeConfigurationId)
    }
}

public enum RomaPowerModePreference {
    public static var registeredDefaults: [String: Any] {
        [
            RomaUserDefaultsKey.powerModePersistConfig: RomaPreferenceDefault.powerModePersistConfiguredPreferences
        ]
    }

    public static func isUIEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: RomaUserDefaultsKey.powerModeUIFlag) != nil else {
            return RomaPreferenceDefault.powerModeUIEnabled
        }

        return defaults.bool(forKey: RomaUserDefaultsKey.powerModeUIFlag)
    }

    public static func saveIsUIEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: RomaUserDefaultsKey.powerModeUIFlag)
    }

    public static func initializeUIFlagIfNeeded(
        hasEnabledConfigurations: Bool,
        in defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: RomaUserDefaultsKey.powerModeUIFlag) == nil else {
            return
        }

        saveIsUIEnabled(hasEnabledConfigurations, to: defaults)
    }

    public static func shouldPersistConfiguredPreferences(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: RomaUserDefaultsKey.powerModePersistConfig) != nil else {
            return RomaPreferenceDefault.powerModePersistConfiguredPreferences
        }

        return defaults.bool(forKey: RomaUserDefaultsKey.powerModePersistConfig)
    }

    public static func saveShouldPersistConfiguredPreferences(
        _ shouldPersist: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPersist, forKey: RomaUserDefaultsKey.powerModePersistConfig)
    }

    public static func canUseShortcuts(
        hasEnabledConfigurations: Bool,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        isUIEnabled(from: defaults) && hasEnabledConfigurations
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.powerModeUIFlag)
        defaults.removeObject(forKey: RomaUserDefaultsKey.powerModePersistConfig)
    }
}

public enum RomaPowerModeSessionPreference {
    public static func saveActiveSession(
        _ session: RomaPowerModeSession,
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(session)
        defaults.set(data, forKey: RomaUserDefaultsKey.activePowerModeSession)
    }

    public static func loadActiveSession(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> RomaPowerModeSession? {
        guard let data = defaults.data(forKey: RomaUserDefaultsKey.activePowerModeSession) else {
            return nil
        }

        return try decoder.decode(RomaPowerModeSession.self, from: data)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.activePowerModeSession)
    }
}

public enum RomaCustomPromptStorage {
    public static func savePrompts(
        _ prompts: [RomaCustomPrompt],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(prompts) {
            defaults.set(data, forKey: RomaUserDefaultsKey.customPrompts)
        }
    }

    public static func loadPrompts(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [RomaCustomPrompt] {
        guard let data = defaults.data(forKey: RomaUserDefaultsKey.customPrompts),
              let prompts = try? decoder.decode([RomaCustomPrompt].self, from: data) else {
            return []
        }

        return prompts
    }

    public static func saveSelectedPromptId(_ selectedPromptId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedPromptId {
            defaults.set(selectedPromptId.uuidString, forKey: RomaUserDefaultsKey.selectedPromptId)
        } else {
            defaults.removeObject(forKey: RomaUserDefaultsKey.selectedPromptId)
        }
    }

    public static func loadSelectedPromptId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: RomaUserDefaultsKey.selectedPromptId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: RomaUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: RomaUserDefaultsKey.selectedPromptId)
    }
}

public enum RomaProviderAPIKeyVerificationState {
    public static func verifiedProviders(
        from providers: [RomaProviderKind] = RomaProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) -> Set<RomaProviderKind> {
        Set(providers.filter { isVerified($0, in: defaults) })
    }

    public static func isVerified(
        _ provider: RomaProviderKind,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = provider.apiKeyVerificationStateKey else {
            return false
        }

        return defaults.bool(forKey: key)
    }

    public static func setVerified(
        _ verified: Bool,
        for provider: RomaProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.set(verified, forKey: key)
    }

    public static func clear(
        for provider: RomaProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func clearAll(
        from providers: [RomaProviderKind] = RomaProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) {
        providers.forEach { clear(for: $0, in: defaults) }
    }
}
