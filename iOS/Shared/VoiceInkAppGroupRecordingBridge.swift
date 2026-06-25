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
        recordingStateReadPlan(in: defaults, now: now).state
    }

    static func recordingStateReadPlan(
        in defaults: UserDefaults?,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateReadPlan {
        VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: defaults?.bool(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
            ) ?? false,
            lastRecordingTimestamp: defaults?.double(
                forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
            ) ?? 0,
            now: now
        )
    }

    static func apply(
        _ mutationPlan: VoiceInkAppGroupRecordingStateMutationPlan,
        to defaults: UserDefaults?
    ) {
        apply(mutationPlan.writePlan, to: defaults)
    }

    private static func apply(
        _ plan: VoiceInkAppGroupRecordingStateWritePlan,
        to defaults: UserDefaults?
    ) {
        plan.applyRuntimeState(
            setIsRecording: {
                defaults?.set(
                    $0,
                    forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording
                )
            },
            setLastRecordingTimestamp: {
                defaults?.set(
                    $0,
                    forKey: VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp
                )
            }
        )
    }
}
