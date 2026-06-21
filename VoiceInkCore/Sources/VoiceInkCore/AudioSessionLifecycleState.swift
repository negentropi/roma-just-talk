import Foundation

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
