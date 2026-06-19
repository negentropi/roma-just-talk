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

public enum VoiceInkRecordingFeedbackPreference {
    public static let systemMuteModeKey = "systemMuteMode"
    public static let legacyIsSystemMuteEnabledKey = "isSystemMuteEnabled"
    public static let audioResumptionDelayKey = "audioResumptionDelay"
    public static let isPauseMediaEnabledKey = "isPauseMediaEnabled"
    public static let isSoundFeedbackEnabledKey = "isSoundFeedbackEnabled"

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
}
