import Foundation
import VoiceInkCore

enum VoiceInkAppGroupRecordingBridge {
    static let appGroupIdentifier = VoiceInkAppIdentity.iOSAppGroupIdentifier

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    @discardableResult
    static func markStopRequested(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateMutationPlan {
        let mutationPlan = VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan(now: now)
        apply(mutationPlan.writePlan, to: defaults)
        return mutationPlan
    }

    @discardableResult
    static func writeRecordingState(
        _ isRecording: Bool,
        to defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateMutationPlan {
        let mutationPlan = VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: isRecording,
            now: now
        )
        apply(mutationPlan.writePlan, to: defaults)
        return mutationPlan
    }

    static func recordingState(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingState {
        VoiceInkAppGroupRecordingStatePolicy.state(
            storedIsRecording: defaults?.bool(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            ) ?? false,
            lastRecordingTimestamp: defaults?.double(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
            ) ?? 0,
            now: now
        )
    }

    private static func apply(
        _ plan: VoiceInkAppGroupRecordingStateWritePlan,
        to defaults: UserDefaults?
    ) {
        if let isRecording = plan.isRecording {
            defaults?.set(
                isRecording,
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            )
        }

        defaults?.set(
            plan.lastRecordingTimestamp,
            forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
        )
    }
}
