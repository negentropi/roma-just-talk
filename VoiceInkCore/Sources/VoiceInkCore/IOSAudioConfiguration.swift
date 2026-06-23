import Foundation

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

public struct VoiceInkIOSAudioPlaybackSessionConfiguration: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case playback
    }

    public enum Mode: String, Equatable, Sendable {
        case spokenAudio
    }

    public let category: Category
    public let mode: Mode

    public init(category: Category, mode: Mode) {
        self.category = category
        self.mode = mode
    }

    public static let notePlayback = Self(category: .playback, mode: .spokenAudio)
}

public enum VoiceInkAudioSessionDiagnostics {
    public static let activatedForRecordingMessage = "Audio session activated for recording"
    public static let activatedForPlaybackMessage = "Audio session activated for playback"
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

public struct VoiceInkAudioSessionPlaybackActivationPlan: Equatable, Sendable {
    public let shouldCancelScheduledDeactivation: Bool
    public let shouldDeactivateCurrentSession: Bool

    public init(
        shouldCancelScheduledDeactivation: Bool,
        shouldDeactivateCurrentSession: Bool
    ) {
        self.shouldCancelScheduledDeactivation = shouldCancelScheduledDeactivation
        self.shouldDeactivateCurrentSession = shouldDeactivateCurrentSession
    }
}

public struct VoiceInkAudioSessionImmediateDeactivationPlan: Equatable, Sendable {
    public let shouldCancelScheduledDeactivation: Bool
    public let shouldDeactivateSession: Bool

    public init(
        shouldCancelScheduledDeactivation: Bool,
        shouldDeactivateSession: Bool
    ) {
        self.shouldCancelScheduledDeactivation = shouldCancelScheduledDeactivation
        self.shouldDeactivateSession = shouldDeactivateSession
    }
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

    public mutating func markActivatedForPlayback() {
        isSessionActive = true
        cancelScheduledDeactivation()
    }

    public mutating func beginPlaybackActivation() -> VoiceInkAudioSessionPlaybackActivationPlan {
        let plan = VoiceInkAudioSessionPlaybackActivationPlan(
            shouldCancelScheduledDeactivation: true,
            shouldDeactivateCurrentSession: isSessionActive
        )
        cancelScheduledDeactivation()
        return plan
    }

    public mutating func beginImmediateDeactivation() -> VoiceInkAudioSessionImmediateDeactivationPlan {
        let plan = VoiceInkAudioSessionImmediateDeactivationPlan(
            shouldCancelScheduledDeactivation: true,
            shouldDeactivateSession: isSessionActive
        )
        cancelScheduledDeactivation()
        return plan
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

public struct VoiceInkIOSAudioRecorderConfiguration: Equatable, Sendable {
    public enum Format: String, Equatable, Sendable {
        case linearPCM
    }

    public enum Quality: String, Equatable, Sendable {
        case high
    }

    public let format: Format
    public let sampleRate: Double
    public let channelCount: Int
    public let bitDepth: Int
    public let isBigEndian: Bool
    public let isFloatingPoint: Bool
    public let quality: Quality
    public let isMeteringEnabled: Bool

    public init(
        format: Format,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int,
        isBigEndian: Bool,
        isFloatingPoint: Bool,
        quality: Quality,
        isMeteringEnabled: Bool
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isBigEndian = isBigEndian
        self.isFloatingPoint = isFloatingPoint
        self.quality = quality
        self.isMeteringEnabled = isMeteringEnabled
    }

    public static let voiceRecording = Self(
        format: .linearPCM,
        sampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
        channelCount: VoiceInkPCM16Audio.monoChannelCount,
        bitDepth: VoiceInkPCM16Audio.bitsPerSample,
        isBigEndian: VoiceInkPCM16Audio.isBigEndian,
        isFloatingPoint: VoiceInkPCM16Audio.isFloatingPoint,
        quality: .high,
        isMeteringEnabled: true
    )
}
