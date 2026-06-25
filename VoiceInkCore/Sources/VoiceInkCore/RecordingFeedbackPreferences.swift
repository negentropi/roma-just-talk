import Foundation

public enum VoiceInkSystemMuteMode: String, CaseIterable, Identifiable, Sendable {
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

public struct VoiceInkRecordingFeedbackDelayOption: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: TimeInterval

    public var id: TimeInterval { value }

    public init(label: String, value: TimeInterval) {
        self.label = label
        self.value = value
    }
}

public struct VoiceInkMacOSRecordingFeedbackSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let soundFeedbackLabel: String
    public let systemMuteModeLabel: String
    public let audioResumptionDelayLabel: String
    public let audioResumptionDelayOptions: [VoiceInkRecordingFeedbackDelayOption]
    public let experimentalSectionTitle: String
    public let pauseMediaLabel: String
    public let pauseMediaInfoMessage: String
    public let pauseMediaResumeDelayLabel: String

    public init(
        sectionTitle: String,
        soundFeedbackLabel: String,
        systemMuteModeLabel: String,
        audioResumptionDelayLabel: String,
        audioResumptionDelayOptions: [VoiceInkRecordingFeedbackDelayOption],
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

public struct VoiceInkRecordingFeedbackBackupPreferences: Codable, Equatable, Sendable {
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

public struct VoiceInkRecordingFeedbackBackupImportPlan: Equatable, Sendable {
    private let isSoundFeedbackEnabled: Bool?
    private let systemMuteMode: VoiceInkSystemMuteMode?
    private let isPauseMediaEnabled: Bool?
    private let audioResumptionDelay: Double?
    private let isExperimentalFeaturesEnabled: Bool?

    public var shouldDisablePauseMediaForExperimentalImport: Bool {
        isExperimentalFeaturesEnabled == false
    }

    public init(
        isSoundFeedbackEnabled: Bool?,
        systemMuteMode: VoiceInkSystemMuteMode?,
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
        setSystemMuteMode: (VoiceInkSystemMuteMode) -> Void,
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

public enum VoiceInkBuiltInRecordingSound: String, CaseIterable, Identifiable, Sendable {
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

public enum VoiceInkCustomSoundType: String, CaseIterable, Sendable {
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

    public var defaultBuiltInSound: VoiceInkBuiltInRecordingSound {
        switch self {
        case .start:
            return .sound1
        case .stop:
            return .sound2
        }
    }

    public var recordingSoundCue: VoiceInkRecordingSoundCue {
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

public enum VoiceInkCustomSoundMenuSelection: Hashable, Sendable {
    case builtIn(VoiceInkBuiltInRecordingSound)
    case custom
}

public struct VoiceInkCustomSoundSelectionState: Equatable, Sendable {
    public let type: VoiceInkCustomSoundType
    public let isUsingCustomSound: Bool
    public let selectedBuiltInSound: VoiceInkBuiltInRecordingSound
    public let customFilename: String?

    public init(
        type: VoiceInkCustomSoundType,
        isUsingCustomSound: Bool,
        selectedBuiltInSound: VoiceInkBuiltInRecordingSound,
        customFilename: String?
    ) {
        self.type = type
        self.isUsingCustomSound = isUsingCustomSound
        self.selectedBuiltInSound = selectedBuiltInSound
        self.customFilename = customFilename
    }

    public var menuSelection: VoiceInkCustomSoundMenuSelection {
        isUsingCustomSound ? .custom : .builtIn(selectedBuiltInSound)
    }

    public var isDefaultSelection: Bool {
        VoiceInkCustomSoundPreference.isDefaultSelection(
            for: type,
            isUsingCustomSound: isUsingCustomSound,
            selectedBuiltInSound: selectedBuiltInSound
        )
    }

    public func customSoundURL(in customSoundsDirectory: URL?) -> URL? {
        VoiceInkCustomSoundPreference.customSoundURL(
            isUsingCustomSound: isUsingCustomSound,
            filename: customFilename,
            in: customSoundsDirectory
        )
    }

    public func storedCustomSoundURL(in customSoundsDirectory: URL?) -> URL? {
        VoiceInkCustomSoundPreference.storedCustomSoundURL(
            filename: customFilename,
            in: customSoundsDirectory
        )
    }

    public func selectingBuiltInSound(
        _ sound: VoiceInkBuiltInRecordingSound
    ) -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: false,
            selectedBuiltInSound: sound,
            customFilename: customFilename
        )
    }

    public func usingExistingCustomSound() -> VoiceInkCustomSoundSelectionState? {
        guard customFilename != nil else { return nil }
        return VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: true,
            selectedBuiltInSound: selectedBuiltInSound,
            customFilename: customFilename
        )
    }

    public func settingCustomFilename(_ filename: String) -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: true,
            selectedBuiltInSound: selectedBuiltInSound,
            customFilename: filename
        )
    }

    public func resettingToDefault() -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: false,
            selectedBuiltInSound: type.defaultBuiltInSound,
            customFilename: nil
        )
    }
}

public enum VoiceInkCustomSoundSettingsPresentation {
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

    public static func label(for type: VoiceInkCustomSoundType) -> String {
        "\(type.displayName) Sound"
    }

    public static func customMenuTitle(filename: String?) -> String {
        "Custom: \(filename ?? customFallbackTitle)"
    }

    public static func openPanelTitle(for type: VoiceInkCustomSoundType) -> String {
        "Choose \(type.displayName) Sound"
    }
}

public enum VoiceInkRecordingSoundCue: CaseIterable, Sendable {
    case start
    case stop
    case esc
}

public enum VoiceInkRecordingSoundPlayerSlot: CaseIterable, Hashable, Sendable {
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

public enum VoiceInkRecordingSoundPlaybackPolicy {
    public static let setupSlots: [VoiceInkRecordingSoundPlayerSlot] = [
        .defaultStart,
        .defaultStop,
        .defaultEsc,
        .customStart,
        .customStop
    ]

    public static func playbackSlots(
        for cue: VoiceInkRecordingSoundCue
    ) -> [VoiceInkRecordingSoundPlayerSlot] {
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

public enum VoiceInkCustomSoundError: LocalizedError, Equatable, Sendable {
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

fileprivate enum VoiceInkCustomSoundCopyAction: Equatable, Sendable {
    case useExistingDestination
    case copy
    case replaceExistingDestinationAndCopy
}

public struct VoiceInkCustomSoundCopyPlan: Equatable, Sendable {
    public let filename: String
    public let destinationURL: URL
    private let action: VoiceInkCustomSoundCopyAction

    fileprivate init(
        filename: String,
        destinationURL: URL,
        action: VoiceInkCustomSoundCopyAction
    ) {
        self.filename = filename
        self.destinationURL = destinationURL
        self.action = action
    }

    public func applyRuntimeState(
        removeExistingDestination: (URL) throws -> Void,
        copyToDestination: (URL) throws -> Void
    ) -> Result<String, VoiceInkCustomSoundError> {
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

public enum VoiceInkCustomSoundPreference {
    public static let customSoundsRelativeDirectory = "VoiceInk/CustomSounds"
    public static let changedNotificationName = "CustomSoundsChanged"
    public static let maxDuration: TimeInterval = 3.0

    public static var registeredDefaults: [String: Any] {
        [
            VoiceInkCustomSoundType.start.builtInSoundKey: VoiceInkCustomSoundType.start.defaultBuiltInSound.rawValue,
            VoiceInkCustomSoundType.stop.builtInSoundKey: VoiceInkCustomSoundType.stop.defaultBuiltInSound.rawValue
        ]
    }

    public static func selectionState(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: isUsingCustomSound(for: type, from: defaults),
            selectedBuiltInSound: selectedBuiltInSound(for: type, from: defaults),
            customFilename: customFilename(for: type, from: defaults)
        )
    }

    public static func isUsingCustomSound(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: type.isUsingKey)
    }

    public static func saveIsUsingCustomSound(
        _ isUsingCustomSound: Bool,
        for type: VoiceInkCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isUsingCustomSound, forKey: type.isUsingKey)
    }

    public static func customFilename(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: type.filenameKey)
    }

    public static func saveCustomFilename(
        _ filename: String?,
        for type: VoiceInkCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        if let filename {
            defaults.set(filename, forKey: type.filenameKey)
        } else {
            defaults.removeObject(forKey: type.filenameKey)
        }
    }

    public static func selectedBuiltInSound(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkBuiltInRecordingSound {
        if let rawValue = defaults.string(forKey: type.builtInSoundKey),
           let sound = VoiceInkBuiltInRecordingSound(rawValue: rawValue) {
            return sound
        }

        return type.defaultBuiltInSound
    }

    public static func saveSelectedBuiltInSound(
        _ sound: VoiceInkBuiltInRecordingSound,
        for type: VoiceInkCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(sound.rawValue, forKey: type.builtInSoundKey)
    }

    public static func isDefaultSelection(
        for type: VoiceInkCustomSoundType,
        isUsingCustomSound: Bool,
        selectedBuiltInSound: VoiceInkBuiltInRecordingSound
    ) -> Bool {
        !isUsingCustomSound && selectedBuiltInSound == type.defaultBuiltInSound
    }

    public static func copiedFilename(
        sourceExtension: String,
        for type: VoiceInkCustomSoundType
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
        for type: VoiceInkCustomSoundType,
        fileManager: FileManager = .default
    ) -> VoiceInkCustomSoundCopyPlan {
        let filename = copiedFilename(sourceExtension: sourceURL.pathExtension, for: type)
        let destinationURL = customSoundsDirectory.appendingPathComponent(filename)

        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return VoiceInkCustomSoundCopyPlan(
                filename: filename,
                destinationURL: destinationURL,
                action: .useExistingDestination
            )
        }

        return VoiceInkCustomSoundCopyPlan(
            filename: filename,
            destinationURL: destinationURL,
            action: fileManager.fileExists(atPath: destinationURL.path) ? .replaceExistingDestinationAndCopy : .copy
        )
    }

    public static func preflightValidationError(
        fileExists: Bool,
        duration: TimeInterval
    ) -> VoiceInkCustomSoundError? {
        guard fileExists else { return .fileNotFound }
        guard duration.isFinite && duration > 0 else { return .invalidAudioFile }

        if duration > maxDuration {
            return .durationTooLong(duration: duration, maxDuration: maxDuration)
        }

        return nil
    }
}

public enum VoiceInkRecordingFeedbackPreference {
    public static let systemMuteModeKey = "systemMuteMode"
    public static let legacyIsSystemMuteEnabledKey = "isSystemMuteEnabled"
    public static let audioResumptionDelayKey = "audioResumptionDelay"
    public static let isPauseMediaEnabledKey = "isPauseMediaEnabled"
    public static let isSoundFeedbackEnabledKey = "isSoundFeedbackEnabled"
    public static let experimentalFeaturesEnabledKey = "isExperimentalFeaturesEnabled"

    public static let defaultSystemMuteMode = VoiceInkSystemMuteMode.automatic
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

    public static let macOSSettingsPresentation = VoiceInkMacOSRecordingFeedbackSettingsPresentation(
        sectionTitle: "Recording Feedback",
        soundFeedbackLabel: "Sound Feedback",
        systemMuteModeLabel: "Mute Audio While Recording",
        audioResumptionDelayLabel: "Audio Resume Delay",
        audioResumptionDelayOptions: [
            VoiceInkRecordingFeedbackDelayOption(label: "0s", value: 0.0),
            VoiceInkRecordingFeedbackDelayOption(label: "1s", value: 1.0),
            VoiceInkRecordingFeedbackDelayOption(label: "2s", value: 2.0),
            VoiceInkRecordingFeedbackDelayOption(label: "3s", value: 3.0),
            VoiceInkRecordingFeedbackDelayOption(label: "4s", value: 4.0),
            VoiceInkRecordingFeedbackDelayOption(label: "5s", value: 5.0)
        ],
        experimentalSectionTitle: "Experimental",
        pauseMediaLabel: "Pause Media While Recording",
        pauseMediaInfoMessage: "Pauses playing media when recording starts and resumes when done.",
        pauseMediaResumeDelayLabel: "Resume Delay"
    )

    public static func systemMuteMode(from defaults: UserDefaults = .standard) -> VoiceInkSystemMuteMode {
        if let rawValue = defaults.string(forKey: systemMuteModeKey),
           let mode = VoiceInkSystemMuteMode(rawValue: rawValue) {
            return mode
        }

        if let legacyEnabled = defaults.object(forKey: legacyIsSystemMuteEnabledKey) as? Bool,
           legacyEnabled == false {
            return .never
        }

        return defaultSystemMuteMode
    }

    public static func saveSystemMuteMode(
        _ mode: VoiceInkSystemMuteMode,
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
    ) -> VoiceInkRecordingFeedbackBackupPreferences {
        VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkRecordingFeedbackBackupPreferences
    ) -> VoiceInkRecordingFeedbackBackupImportPlan {
        VoiceInkRecordingFeedbackBackupImportPlan(
            isSoundFeedbackEnabled: preferences.isSoundFeedbackEnabled,
            systemMuteMode: preferences.isSystemMuteEnabled.map { $0 ? .always : .never },
            isPauseMediaEnabled: preferences.isPauseMediaEnabled,
            audioResumptionDelay: preferences.audioResumptionDelay,
            isExperimentalFeaturesEnabled: preferences.isExperimentalFeaturesEnabled
        )
    }
}
