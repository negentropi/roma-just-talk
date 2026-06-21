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

    public init(
        isSoundFeedbackEnabled: Bool?,
        isSystemMuteEnabled: Bool?,
        isPauseMediaEnabled: Bool?,
        audioResumptionDelay: Double?
    ) {
        self.isSoundFeedbackEnabled = isSoundFeedbackEnabled
        self.isSystemMuteEnabled = isSystemMuteEnabled
        self.isPauseMediaEnabled = isPauseMediaEnabled
        self.audioResumptionDelay = audioResumptionDelay
    }
}

public struct VoiceInkRecordingFeedbackBackupImportPlan: Equatable, Sendable {
    public let isSoundFeedbackEnabled: Bool?
    public let systemMuteMode: VoiceInkSystemMuteMode?
    public let isPauseMediaEnabled: Bool?
    public let audioResumptionDelay: Double?
    public let isExperimentalFeaturesEnabled: Bool?

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

    private var capitalizedRawValue: String {
        rawValue.capitalized
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
        audioResumptionDelay: Double
    ) -> VoiceInkRecordingFeedbackBackupPreferences {
        VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkRecordingFeedbackBackupPreferences,
        experimentalFeaturesEnabled: Bool? = nil
    ) -> VoiceInkRecordingFeedbackBackupImportPlan {
        VoiceInkRecordingFeedbackBackupImportPlan(
            isSoundFeedbackEnabled: preferences.isSoundFeedbackEnabled,
            systemMuteMode: preferences.isSystemMuteEnabled.map { $0 ? .always : .never },
            isPauseMediaEnabled: preferences.isPauseMediaEnabled,
            audioResumptionDelay: preferences.audioResumptionDelay,
            isExperimentalFeaturesEnabled: experimentalFeaturesEnabled
        )
    }
}
