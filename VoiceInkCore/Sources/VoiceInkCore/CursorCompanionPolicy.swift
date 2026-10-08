import Foundation

public enum VoiceInkCursorCompanionStyle: String, CaseIterable, Identifiable, Sendable {
    case cartoon
    case storybook
    case anime
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cartoon:
            return "Cartoon"
        case .storybook:
            return "Storybook"
        case .anime:
            return "Anime"
        case .none:
            return "None"
        }
    }
}

public struct VoiceInkMacOSCursorCompanionSettingsPresentation: Equatable, Sendable {
    public let pickerTitle: String
    public let caption: String

    public init(pickerTitle: String, caption: String) {
        self.pickerTitle = pickerTitle
        self.caption = caption
    }
}

public enum VoiceInkCursorCompanionPreference {
    public static let userDefaultsKey = "CursorCompanionStyle"
    public static let defaultStyle: VoiceInkCursorCompanionStyle = .cartoon
    public static let macOSSettingsPresentation = VoiceInkMacOSCursorCompanionSettingsPresentation(
        pickerTitle: "Cursor Companion",
        caption: "Pops onto your cursor when roma starts listening."
    )

    public static func style(from defaults: UserDefaults = .standard) -> VoiceInkCursorCompanionStyle {
        defaults.string(forKey: userDefaultsKey)
            .flatMap(VoiceInkCursorCompanionStyle.init(rawValue:)) ?? defaultStyle
    }

    public static func save(
        _ style: VoiceInkCursorCompanionStyle,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(style.rawValue, forKey: userDefaultsKey)
    }
}

public enum VoiceInkCursorCompanionPose: String, Sendable {
    case perch
    case hug
    case oops
}

public enum VoiceInkCursorCompanionPhase: Equatable, Sendable {
    case hidden
    /// Recording started but no microphone audio has arrived yet; nothing is shown.
    case awaitingAudio
    case arriving
    case listening
    case leaving
    /// Recording could not start.
    case failed
    /// Recording is running but the microphone stopped delivering audio; held until it recovers or ends.
    case stalled

    public var isVisible: Bool {
        self != .hidden && self != .awaitingAudio
    }
}

public enum VoiceInkCursorCompanionEvent: Equatable, Sendable {
    case recordingStarted
    case audioReceived
    case audioStalled
    case recordingEnded
    case startFailed
    case animationFinished
}

public enum VoiceInkCursorCompanionPolicy {
    public static func next(
        _ phase: VoiceInkCursorCompanionPhase,
        on event: VoiceInkCursorCompanionEvent
    ) -> VoiceInkCursorCompanionPhase {
        switch (phase, event) {
        case (_, .startFailed):
            return .failed
        case (.hidden, .recordingStarted), (.leaving, .recordingStarted), (.failed, .recordingStarted):
            return .awaitingAudio
        case (.awaitingAudio, .audioReceived), (.stalled, .audioReceived):
            return .arriving
        case (.awaitingAudio, .audioStalled), (.arriving, .audioStalled), (.listening, .audioStalled):
            return .stalled
        case (.arriving, .animationFinished):
            return .listening
        case (.awaitingAudio, .recordingEnded):
            return .hidden
        case (.arriving, .recordingEnded), (.listening, .recordingEnded), (.stalled, .recordingEnded):
            return .leaving
        case (.leaving, .animationFinished), (.failed, .animationFinished):
            return .hidden
        default:
            return phase
        }
    }

    public static func event(
        from old: VoiceInkRecordingState,
        to new: VoiceInkRecordingState
    ) -> VoiceInkCursorCompanionEvent? {
        if old != .recording && new == .recording {
            return .recordingStarted
        }
        if old == .recording && new != .recording {
            return .recordingEnded
        }
        return nil
    }

    public static func duration(of phase: VoiceInkCursorCompanionPhase) -> TimeInterval? {
        switch phase {
        case .arriving:
            return 1.4
        case .leaving:
            return 0.35
        case .failed:
            return 2.6
        case .hidden, .awaitingAudio, .listening, .stalled:
            return nil
        }
    }
}

/// Turns a monotonically increasing count of captured microphone buffers into flow events,
/// so "listening" means audio is actually arriving rather than that recording was requested.
public struct VoiceInkCaptureFlowMonitor: Equatable, Sendable {
    public static let stallInterval: TimeInterval = 2

    private var lastCount: UInt64
    private var lastAdvance: TimeInterval
    private var isFlowing = false
    private var isStalled = false

    public init(count: UInt64, now: TimeInterval) {
        lastCount = count
        lastAdvance = now
    }

    public mutating func observe(count: UInt64, now: TimeInterval) -> VoiceInkCursorCompanionEvent? {
        if count != lastCount {
            lastCount = count
            lastAdvance = now
            guard !isFlowing else { return nil }
            isFlowing = true
            isStalled = false
            return .audioReceived
        }
        guard !isStalled, now - lastAdvance >= Self.stallInterval else { return nil }
        isStalled = true
        isFlowing = false
        return .audioStalled
    }
}
