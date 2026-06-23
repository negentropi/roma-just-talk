import Foundation

public enum VoiceInkAudioSessionDiagnostics {
    public static let activatedForRecordingMessage = "Audio session activated for recording"
    public static let deactivatedMessage = "Audio session deactivated"

    public static func activationFailedMessage(localizedDescription: String, code: Int) -> String {
        "Audio session activation failed: \(localizedDescription) (code: \(code))"
    }

    public static func deactivationScheduledMessage(seconds: Int) -> String {
        "Audio session deactivation scheduled in \(seconds) seconds"
    }

    public static func deactivationFailedMessage(localizedDescription: String) -> String {
        "Failed to deactivate audio session: \(localizedDescription)"
    }
}

public struct VoiceInkIOSAudioSessionRecordingConfiguration: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case playAndRecord
    }

    public enum Mode: String, Equatable, Sendable {
        case spokenAudio
    }

    public enum Option: String, Equatable, Sendable {
        case defaultToSpeaker
        case allowBluetooth
        case allowBluetoothA2DP
        case mixWithOthers
    }

    public let category: Category
    public let mode: Mode
    public let options: [Option]

    public init(category: Category, mode: Mode, options: [Option]) {
        self.category = category
        self.mode = mode
        self.options = options
    }

    public static let voiceRecording = Self(
        category: .playAndRecord,
        mode: .spokenAudio,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
    )
}

public struct VoiceInkAudioSessionLifecycleState: Equatable, Sendable {
    public private(set) var isSessionActive: Bool
    public private(set) var timeoutRemaining: TimeInterval

    public init(
        isSessionActive: Bool = false,
        timeoutRemaining: TimeInterval = 0
    ) {
        self.isSessionActive = isSessionActive
        self.timeoutRemaining = timeoutRemaining
    }

    public mutating func markActivatedForRecording() {
        isSessionActive = true
        cancelScheduledDeactivation()
    }

    public mutating func scheduleDeactivation(timeoutSeconds: Int) -> VoiceInkAudioSessionDeactivationPlan {
        cancelScheduledDeactivation()

        let plan = VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: timeoutSeconds)
        if case .delayed(let interval) = plan {
            timeoutRemaining = interval
        }

        return plan
    }

    public mutating func scheduleDeactivationExecution(timeoutSeconds: Int) -> VoiceInkAudioSessionDeactivationExecutionPlan {
        scheduleDeactivation(timeoutSeconds: timeoutSeconds).executionPlan
    }

    public mutating func advanceCountdown() -> VoiceInkAudioSessionDeactivationPlan {
        timeoutRemaining = VoiceInkAudioSessionTimeoutPreference.remainingTimeAfterCountdownTick(timeoutRemaining)
        return timeoutRemaining <= 0 ? .immediate : .delayed(timeoutRemaining)
    }

    public mutating func advanceCountdownExecution() -> VoiceInkAudioSessionDeactivationExecutionPlan {
        advanceCountdown().executionPlan
    }

    public mutating func cancelScheduledDeactivation() {
        timeoutRemaining = 0
    }

    public mutating func markDeactivated() {
        isSessionActive = false
        cancelScheduledDeactivation()
    }
}
